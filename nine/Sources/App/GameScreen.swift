// GameScreen.swift — the board screen and the complete remote grammar
// (PRD §4.4, reworked by the tvOS input pass). One focusable surface
// (`.couchRemote`); the cursor lives in-canvas; the rose is an input layer that
// captures gestures while open.
//
//   swipe            move cell cursor · in the rose, move the petal focus
//   tap              open the rose · in the rose, place the focused petal
//   click            the same as tap (a click is never *required*)
//   play/pause       pencil mode on / off (the remote's one free button is
//                    the pencil switch; a chip in the corner says it is on)
//   play/pause hold  undo, with a note showing the reverted digit
//   hold-click       settings, beside the board (the controls guide is one
//                    press further, from the panel's header)
//   back             close the rose or panel · else arm, and a second Back
//                    within 2.5 s saves and goes home
//
// Nothing the remote says is drawn on the board: the timer, the pencil chip
// and the SharePlay dots sit in the screen's top corners and every transient
// note in the bottom-leading one, in the margin the 956pt board leaves.
//
// The rose no longer places on a swipe. An eight-way stroke only *moves* the
// focus (diagonals included — `RoseFocus` reconciles it with the four-way move
// commands), and the tap is the commit. A swipe that was only looking can never
// write a digit.
//
// PRD-5 (revised): a real controller is adopted automatically. The remote body
// listens for pad gesture traffic and, on the first one, seeds the cursor and
// flips `model.padSession` — PadKit's reader then drives the SAME AppModel
// mutation paths through `PadPlayController` (RemoteKit ignored; Menu still
// exits). A drop mid-session falls back to the remote grammar in place. One
// master at a time, by design.
import SwiftUI
import CouchKit

#if os(tvOS)
struct GameScreen: View {
    let model: AppModel

    @State private var chrome = ChromeVisibility()
    @State private var cursor = 40
    @State private var rose: RoseState?
    /// The petal focus of the open rose, which owns the swipe/stroke
    /// reconciliation; mirrored into `rose.focusedIndex` for the drawing.
    @State private var roseFocus = RoseFocus()
    /// One primary press per thumb, whether it arrived as a tap or a click.
    @State private var pressGate = PrimaryPressGate()
    /// Back on a quiet board arms the exit rather than taking it.
    @State private var backGuard = BackGuard()
    @State private var showBackHint = false
    /// Settings or the controls guide, beside the board. Nil is the board alone.
    @State private var panel: TVPanel?
    @State private var toast: UndoToastState?
    @State private var toastDismissal: Task<Void, Never>?
    /// Play/Pause is the remote's pencil switch: every rose it opens writes
    /// corner notes while this is on.
    @State private var remotePencil = false
    /// When Play/Pause last flipped pencil mode. A *long* press also leaks a
    /// plain `.playPause` first (RemoteKit attaches both handlers), so an undo
    /// that arrives just after a flip un-flips it before undoing.
    @State private var lastPencilFlip: Date?
    /// The settings-discoverability chip, flashed on the first board of a
    /// session (the once-per-launch gate lives on the model).
    @State private var showHint = false

    // MARK: Pad session (PRD-5)
    /// The controller-locked play state. A reference type (not `@State` value)
    /// because PadKit's gesture stream is an external event source; the
    /// reference is stable across re-renders so `padReader.onGesture` can point
    /// at it once.
    @State private var pad: PadPlayController
    /// The pad discoverability chip, flashed once per launch on the first pad
    /// session (session-scoped, never persisted).
    @State private var showPadHint = false
    @State private var padHintFlashed = false
    /// Brief chip shown when a controller drops mid-session and the remote
    /// grammar takes over in place.
    @State private var showDisconnected = false

    @Environment(\.colorScheme) private var colorScheme
    /// PRD-22: the petal lens is motion, so Reduce Motion keeps the material.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// The TV rose's geometry (PRD-22). `clamped: false` on purpose: the tvOS
    /// ring has never been pulled back onto the plane, and PRD-22 is a
    /// rendering change — moving where the rose blooms on a corner cell is a
    /// UX change the TV's IA pass should make, not this one. So the lens bends
    /// exactly where the petals already are, including the part that hangs off
    /// the board, where there is nothing to bend and nothing happens.
    private func padRoseLens(cursor: Int, pencil: Bool) -> RoseLens {
        RoseLens(
            cursor: cursor,
            side: Double(BoardMetrics.side),
            inset: 28,
            pencil: pencil,
            scale: 1.0,
            clamped: false
        )
    }

    init(model: AppModel) {
        self.model = model
        _pad = State(initialValue: PadPlayController(model: model))
    }

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// The board's own ink, so the rose's petal numerals are the same colour as
    /// the digits they will become (PRD-22's `digitTone`). Computed here rather
    /// than threaded, exactly as `accent` above is.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    var body: some View {
        Group {
            if model.padSession {
                padBody
            } else {
                remoteBody
            }
        }
        // The pad-probe HUD rides the OUTER Group so it survives the remote↔pad
        // body swap — the exact transition under observation (Phase 0.2).
        .overlay(alignment: .topTrailing) { padProbeOverlay }
        // While not in a session the remote body listens for real pad traffic
        // and adopts the controller grammar in place on the first gesture (the
        // sim's phantom pad emits none, so it never adopts). Home needs no
        // listener — a gamepad drives shelf focus natively.
        .onAppear { if !model.padSession { installAdoptionListener() } }
        .onDisappear { model.padReader.onGesture = nil }
        .onChange(of: model.padSession) { _, session in
            if !session { installAdoptionListener() }
            // session == true is wired by padBody.onAppear → syncPadRouting().
        }
        // A controller dropped mid-session falls back to the remote grammar in
        // place — seed the remote cursor, keep the timer running, flash a chip.
        // No reconnect veil, no pause (PRD-5 revised).
        .onChange(of: model.padConnected) { _, connected in
            guard model.padSession, !connected else { return }
            fallBackToRemote()
        }
        #if DEBUG
        .onAppear { registerInjector() }
        #endif
    }

    #if DEBUG
    /// `-NineRemoteInjector`: the simulator's stand-in for a thumb. Gestures go
    /// through `handle(_:)` exactly as `.couchRemote` delivers them; while
    /// settings own the focus engine only Back reaches the board, as on a TV.
    private func registerInjector() {
        RemoteInjector.shared.onGesture = { gesture in
            guard !model.padSession else { return }
            if panel == .settings {
                if gesture == .back { closePanel() }
                return
            }
            handle(gesture)
        }
        RemoteInjector.shared.onCommand = { command in
            switch command {
            case "panel.remote": openPanel(.controls(.remote))
            case "panel.controller": openPanel(.controls(.controller))
            case "pref.accent":
                let all = AccentChoice.allCases
                let next = ((all.firstIndex(of: model.prefs.accent) ?? 0) + 1) % all.count
                model.prefs.accent = all[next]
            case "pref.theme":
                let all = ThemeChoice.allCases
                let next = ((all.firstIndex(of: model.prefs.theme) ?? 0) + 1) % all.count
                model.prefs.theme = all[next]
            case "pref.timer":
                model.prefs.showTimer.toggle()
            default:
                break
            }
        }
    }
    #endif

    @ViewBuilder
    private var padProbeOverlay: some View {
        #if DEBUG
        if model.padProbe { PadProbeHUD(model: model) }
        #endif
    }

    // MARK: - Remote body (unchanged grammar)

    @ViewBuilder
    private var remoteBody: some View {
        // While settings are up, the remote surface detaches so the tvOS focus
        // engine can walk the panel's controls; Back brings it home again. The
        // controls guide is read-only and leaves the board live — a player
        // learns a gesture by doing it with its label in view.
        if panel == .settings {
            core
                .onExitCommand { closePanel() }
        } else {
            core.couchRemote(chrome: chrome, eightWay: true, interceptsBack: true) { gesture in
                // A pad's first Circle lands here before adoption flips the
                // body; it must undo, not quit.
                if case .back = gesture {
                    backUnlessPadCircle { handle(gesture) }
                } else {
                    handle(gesture)
                }
            }
        }
    }

    private var core: some View {
        ZStack {
            stage(board)
            panelChevron
            screenChrome(pencil: remotePencil)
            completionChip
            sidePanel {
                // New Game ships for remote players too (PRD-5 §2.3: a widened
                // gate lands for everyone, not just the pad). Home is offered
                // here as well now that a single Back no longer leaves.
                TVSettingsList(model: model, accent: accent, onNewGame: { difficulty in
                    closePanel()
                    cursor = 40
                    model.startFree(difficulty)
                }, onHome: {
                    panel = nil
                    model.goHome()
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { flashHint() }
    }

    /// The chevron in the margin on the panel's side of the centred board,
    /// while there is a board to swipe off: not over a panel, the rose or a
    /// solved board. Remote only — a controller opens settings with ☰.
    @ViewBuilder
    private var panelChevron: some View {
        if panel == nil, rose == nil, model.solvedAt == nil {
            // A board-wide gap, then the chevron: an HStack, so the trailing
            // side is the trailing side under either layout direction.
            HStack(spacing: 24) {
                Color.clear.frame(width: TVPanelMetrics.boardSide)
                PanelChevron(
                    armed: Self.leavesTowardPanel(
                        cursor: cursor,
                        direction: layoutDirection == .rightToLeft ? .left : .right,
                        layout: layoutDirection),
                    accent: accent)
            }
            // Centred on the board, not on the pair.
            .padding(.leading, 24 + PanelChevron.width)
            .transition(.opacity)
        }
    }

    // MARK: - Side by side

    /// The board's stage: centred alone, scaled and moved to the leading edge
    /// while a panel shares the screen. A scale rather than a smaller board,
    /// so the rose, the lens and the Afterglow keep the geometry they were
    /// drawn for.
    private func stage(_ content: some View) -> some View {
        let open = panel != nil
        // `scaleEffect` draws smaller without laying out smaller, so the
        // scaled stage is given its scaled frame — otherwise it keeps claiming
        // the full 956pt and slides under the panel.
        let side = TVPanelMetrics.boardSide * (open ? TVPanelMetrics.boardScale : 1)
        return content
            .scaleEffect(open ? TVPanelMetrics.boardScale : 1)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: open ? .leading : .center)
            .animation(.couchFast, value: open)
    }

    @ViewBuilder
    private func sidePanel(@ViewBuilder settings: @escaping () -> some View) -> some View {
        if let panel {
            TVSidePanel(panel: panel, accent: accent, onShow: { next in
                withAnimation(.couchFast) { self.panel = next }
            }, settings: settings)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func openPanel(_ next: TVPanel) {
        withAnimation(.couchFast) {
            rose = nil
            panel = next
        }
        if next == .settings { pad.showPrefs = model.padSession }
    }

    private func closePanel() {
        withAnimation(.couchFast) { panel = nil }
        pad.showPrefs = false
    }

    /// SharePlay presence (PRD-28 §5): the same row of dots the phone shows,
    /// present only inside a shared parlor, in the screen's top-trailing corner.
    @ViewBuilder
    private var parlorRow: some View {
        if let room = model.parlor.room, room.isShared, model.game != nil {
            // The phone's row at couch scale, grown from the corner it sits in.
            ParlorPresenceRow(room: room, accent: accent)
                .scaleEffect(1.6, anchor: .topTrailing)
                .transition(.opacity)
        }
    }

    // MARK: - The screen's corners

    /// Everything the screen says that is not the board, in the margins the
    /// 956pt board leaves on a 1920pt screen: the clock and the pencil switch
    /// top-leading, the SharePlay dots top-trailing, and every transient note
    /// stacked bottom-leading. Nothing here may sit on the board (input pass
    /// review: "the clock overlaps the board", "the undo note covers it").
    private func screenChrome(pencil: Bool) -> some View {
        let open = panel != nil
        return ZStack {
            VStack(alignment: .leading, spacing: 14) {
                timerChip
                if pencil {
                    GlassChip(Strings.string("game.chip.pencil"), systemImage: "pencil")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The panel takes the trailing third while it is open; the dots
            // come back with the board.
            if !open {
                parlorRow
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            VStack(alignment: .leading, spacing: 12) {
                notes
            }
            // Beside a centred board the margin is ~400pt and a note may wrap;
            // under the shrunk board it is one line across the board's width.
            .frame(width: open ? TVPanelMetrics.boardSide * TVPanelMetrics.boardScale
                               : TVChrome.noteWidth,
                   alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .animation(.couchFast, value: pencil)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var notes: some View {
        let oneLine = panel != nil
        // The two control legends are rows, never one squeezed line: they
        // are the only place the screen says how settings open.
        // Not while a panel is open: the player has found settings, and under
        // the shrunk board the legend would sit on the board.
        if showHint && panel == nil {
            CornerLegend(text: Strings.string("game.tv.remoteHint"))
        }
        if showPadHint && panel == nil {
            CornerLegend(text: Strings.string("game.tv.padHint"),
                         systemImage: "gamecontroller")
        }
        if let toast = model.padSession ? pad.undoToast : toast {
            CornerNote(text: toast.text, systemImage: "arrow.uturn.backward", oneLine: oneLine)
                .id(toast.id)
        }
        if showBackHint {
            CornerNote(text: Strings.string("game.tv.backAgain"), systemImage: "house",
                       oneLine: oneLine)
        }
        if showDisconnected {
            CornerNote(text: Strings.string("game.tv.disconnected"),
                       systemImage: "gamecontroller", oneLine: oneLine)
        }
    }

    // MARK: - The rose, standing off the board

    /// The board while the rose is up: dimmed and softened, so nine glass
    /// petals stop competing with eighty-one glass cells (review: "the rose
    /// needs a better stand-off from its highly similar board"). The theme's
    /// own scrim recipe, so a light theme dims rather than greys.
    private func standOff(_ board: some View, roseOpen: Bool) -> some View {
        board
            .blur(radius: roseOpen && !reduceMotion ? 5 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Scrim.overlay(for: tones))
                    .opacity(roseOpen ? 0.7 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.couchFast, value: roseOpen)
    }

    /// The rose on its plate — one glass slab with one shadow under the nine
    /// petals, the plate the phone's rose already stands on (`RoseLens`).
    private func roseLayer(_ rose: RoseState, cursor: Int, game: NineGame) -> some View {
        let center = BoardMetrics.center(of: cursor)
        let span = CGFloat(RoseLens.plateSpan(pencil: rose.pencil, scale: 1))
        let plate = RoundedRectangle(
            cornerRadius: CGFloat(RoseLens.plateCornerRadius(pencil: rose.pencil, scale: 1)),
            style: .continuous)
        return ZStack {
            plate
                .fill(tones.isLight ? Color.white.opacity(0.5) : Color.black.opacity(0.32))
                .frame(width: span, height: span)
                .couchGlass(in: plate)
                .shadow(color: .black.opacity(tones.isLight ? 0.25 : 0.55), radius: 30, y: 16)
            FlickRoseView(
                state: rose,
                accent: accent,
                completedDigits: Set((1...9).filter { game.isDigitComplete($0) }),
                showsFocusRing: true,
                digitTone: tones.digitTone
            )
        }
        .position(x: center.x + 28, y: center.y + 28) // board padding inset
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    // MARK: - Pad body (PRD-5)

    @ViewBuilder
    private var padBody: some View {
        Group {
            // Settings owns the focus engine while up, so the board surface
            // detaches (the prefs-sheet detach pattern) and Circle — which the
            // system still sees as Menu here — closes it.
            if panel == .settings {
                padCore
                    .onExitCommand { closePanel() }
            } else {
                // The shield stops tvOS turning Circle into Menu, so the only
                // Circle the board sees is PadKit's, and it means Back with the
                // two-press guard — never "leave the app" (1.2 playtest).
                PadEventShield {
                    padCore.couchRemote(chrome: chrome, interceptsBack: true) { gesture in
                        if case .back = gesture {
                            backUnlessPadCircle { padBack() }
                        }
                    }
                    // A hosted controller starts a fresh environment: carry the
                    // root's theme, scheme and tint across the boundary.
                    .environment(\.nineTheme, model.prefs.theme)
                    .environment(\.colorScheme, colorScheme)
                    .tint(accent)
                }
            }
        }
        .onAppear {
            pad.onBack = { padBack() }
            pad.syncHaptics()
            syncPadRouting()
            // The first controller session ever opens the Controller guide
            // beside the board — the manual is a drawing now, not a tutorial.
            if !model.padTutorialSeen {
                model.padTutorialSeen = true
                withAnimation(.couchFast) { panel = .controls(.controller) }
            } else {
                flashPadHint()
            }
        }
        .onChange(of: pad.showPrefs) { _, wants in
            // The pad's settings button opens the same side panel the remote
            // uses; closing either way closes both.
            if wants, panel != .settings { withAnimation(.couchFast) { panel = .settings } }
            if !wants, panel == .settings { withAnimation(.couchFast) { panel = nil } }
        }
        .onChange(of: panel) { _, now in
            if now != .settings, pad.showPrefs { pad.showPrefs = false }
        }
        .onChange(of: model.prefs.controllerHaptics) { pad.syncHaptics() }
    }

    private var padCore: some View {
        ZStack {
            stage(padBoard)
            screenChrome(pencil: pad.pencilSticky)
            completionChip
            sidePanel {
                TVSettingsList(model: model, accent: accent, onNewGame: startPadNewGame, onHome: {
                    closePanel()
                    model.goHome()
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Back during a pad session — Circle, or the Siri Remote's Menu: close
    /// what is open, else the same two-press exit the remote grammar uses.
    private func padBack() {
        if panel != nil { closePanel(); return }
        if pad.learningRose != nil { pad.learningRose = nil; return }
        guardedExit()
    }

    /// Run a Back action only if it came from the Siri Remote's Menu, not a
    /// gamepad's Circle. tvOS delivers a pad's B / Circle to UIKit as Menu as
    /// well as to PadKit, so without this every Circle tap undid a move *and*
    /// saved-and-quit to the shelf (1.2 playtest). The UIKit command can beat
    /// PadKit's 60 Hz poll to the edge, so wait a few frames before asking.
    private func backUnlessPadCircle(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if model.padReader.changedRecently(.circle, within: 0.3) { return }
            action()
        }
    }

    /// Point the reader at the board's controller grammar (a stable reference).
    private func syncPadRouting() {
        guard model.padSession else { installAdoptionListener(); return }
        model.padReader.onGesture = { [pad] gesture in pad.handle(gesture) }
        setRoutingLabel("pad-grammar")
    }

    /// Listen for real pad gesture traffic while playing on the remote; the
    /// first one adopts the controller grammar in place.
    private func installAdoptionListener() {
        guard !model.padSession else { return }
        model.padReader.onGesture = { gesture in adoptIfRealGesture(gesture) }
        setRoutingLabel("adoption-listener")
    }

    private func setRoutingLabel(_ label: String) {
        #if DEBUG
        model.padRoutingLabel = label
        #endif
    }

    /// Adopt the controller grammar on the first *input* gesture (never on a
    /// bare connect/disconnect — the sim's phantom pad only ever connects).
    private func adoptIfRealGesture(_ gesture: PadGesture) {
        switch gesture {
        case .connect, .disconnect: return
        default: break
        }
        guard !model.padSession else { return }
        // Seed the pad cursor from where the remote left off; clear remote UI.
        pad.cursor = cursor
        pad.learningRose = nil
        pad.showPrefs = false
        withAnimation(.couchFast) { rose = nil }
        // The controls guide follows the device that is now in charge.
        if case .controls = panel { panel = .controls(.controller) }
        if panel == .settings { panel = nil }
        model.padSession = true
        // Light the DualSense bar to the accent on the session flip (Phase 3.4;
        // nil-safe no-op on Xbox pads / no light).
        let rgb = model.prefs.accent.lightBarRGB
        model.padReader.setLight(red: rgb.red, green: rgb.green, blue: rgb.blue)
        // Forward the triggering gesture so the first input isn't swallowed.
        pad.handle(gesture)
    }

    /// Controller dropped mid-session: hand control back to the remote grammar
    /// where the pad left the cursor, keep the timer running, flash a chip.
    private func fallBackToRemote() {
        cursor = pad.cursor
        withAnimation(.couchFast) { rose = nil }
        if case .controls = panel { panel = .controls(.remote) }
        if panel == .settings { panel = nil }
        pad.showPrefs = false
        pad.learningRose = nil
        model.padSession = false
        flashDisconnectedChip()
    }

    private func flashDisconnectedChip() {
        withAnimation(.couchFast) { showDisconnected = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.couchAmbient) { showDisconnected = false }
        }
    }

    /// Flash the pad discoverability chip once per launch on a pad session
    /// (session-scoped; the first-ever session gets the guide instead).
    private func flashPadHint() {
        guard !padHintFlashed else { return }
        padHintFlashed = true
        withAnimation(.couchFast) { showPadHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            withAnimation(.couchAmbient) { showPadHint = false }
        }
    }

    private func startPadNewGame(_ difficulty: Difficulty) {
        closePanel()
        pad.learningRose = nil
        pad.cursor = 40
        model.startFree(difficulty) // keeps padSession on
    }


    @ViewBuilder
    private var padBoard: some View {
        if let game = model.game {
            standOff(BoardView(
                game: game,
                cursor: pad.cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: pad.learningRose != nil,
                roseLens: reduceMotion ? nil : pad.learningRose.map {
                    padRoseLens(cursor: pad.cursor, pencil: $0.pencil)
                },
                previewDigit: pad.previewDigit,
                previewPencil: pad.learningRose?.pencil ?? false,
                // Same-number highlight, as on the remote: the cursor's digit.
                highlightDigit: model.prefs.numberHighlight ? pad.highlightDigit : nil,
                channelRules: model.currentRules,
                // Gyro trophy: DualSense/DualShock tilt steers the sheen after
                // the sweep settles (PRD-5 §2.2). No motion → a calm centered
                // highlight, which keeps the loop alive but harmless.
                waveOrigin: model.lastPlacedCell,
                afterglowTilt: { model.padReader.motionTilt(at: $0) }
            ), roseOpen: pad.learningRose != nil)
            .overlay { padRoseOverlay(game: game) }
        } else {
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private func padRoseOverlay(game: NineGame) -> some View {
        if let rose = pad.learningRose {
            roseLayer(rose, cursor: pad.cursor, game: game)
        }
    }

    // MARK: - Board + rose (remote)

    @ViewBuilder
    private var board: some View {
        if let game = model.game {
            standOff(BoardView(
                game: game,
                cursor: cursor,
                accent: accent,
                showErrors: model.prefs.errorHighlight,
                solvedAt: model.solvedAt,
                roseOpen: rose != nil,
                roseLens: reduceMotion ? nil : rose.map {
                    padRoseLens(cursor: cursor, pencil: $0.pencil)
                },
                previewDigit: previewDigit,
                previewPencil: rose?.pencil ?? false,
                // Same-number highlight, remote grammar: parking the cursor
                // on a digit lights up all of its kind (notes included).
                highlightDigit: model.prefs.numberHighlight && game.entry(at: cursor) != 0
                    ? game.entry(at: cursor) : nil,
                channelRules: model.currentRules,
                // Afterglow: the wave detonates from the winning cell; no
                // tilt source on tvOS — the sheen settles and the loop stops.
                waveOrigin: model.lastPlacedCell
            ), roseOpen: rose != nil)
            .overlay {
                if let rose {
                    roseLayer(rose, cursor: cursor, game: game)
                }
            }
        } else {
            // Momentary state while a puzzle is composed.
            GlassChip(Strings.string("status.composing"), systemImage: "sparkles")
        }
    }

    /// The digit a click would place right now, ghosted into the selected
    /// cell. Live on every remote: swipes walk the petals everywhere, and
    /// even on eight-way remotes the click path needs an honest preview.
    private var previewDigit: Int? {
        guard let rose else { return nil }
        return rose.focusedIndex + 1
    }

    // MARK: - Chrome

    @ViewBuilder
    private var timerChip: some View {
        if model.prefs.showTimer, let game = model.game, model.solvedAt == nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                GlassChip(SolveCardFacts.elapsedText(game.timer.elapsed(at: timeline.date)), systemImage: "clock")
            }
        }
    }



    /// Flash the settings-discoverability chip once per launch, on the first
    /// board only (session-scoped by design — never persisted).
    private func flashHint() {
        guard !model.hintFlashed else { return }
        model.hintFlashed = true
        withAnimation(.couchFast) { showHint = true }
        Task {
            // Long enough to read four rows from a sofa; it was 4.2 s for one
            // run-on line, and the job that mattered came last.
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            withAnimation(.couchAmbient) { showHint = false }
        }
    }

    @ViewBuilder
    private var completionChip: some View {
        if let solvedAt = model.solvedAt {
            TimelineView(.periodic(from: solvedAt, by: 0.5)) { timeline in
                if timeline.date.timeIntervalSince(solvedAt) > 2.4 {
                    VStack(spacing: 24) {
                        Spacer()
                        // PRD-28 §6 on the TV: once every board in the parlor
                        // is done, everybody's comet, side by side. The section
                        // draws nothing alone or before the room completes.
                        if let members = model.parlor.room?.members {
                            ParlorCometsSection(members: members, tones: tones, accent: accent)
                                .padding(24)
                                .couchGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                                .scaleEffect(1.4)
                        }
                        GlassChip(completionText, systemImage: "checkmark")
                            .transition(.opacity)
                            .padding(.bottom, 90)
                    }
                    .animation(.couchAmbient, value: model.solvedAt)
                }
            }
        }
    }

    private var completionText: String {
        Strings.string("status.solved")
    }

    // MARK: - Remote grammar

    private func handle(_ gesture: CouchGesture) {
        guard model.game != nil else { return }

        // Anything but Back disarms a pending exit: Back, a move, then Back is
        // two separate thoughts, not a double press.
        if gesture != .back, backGuard.isArmed {
            backGuard.disarm()
            withAnimation(.couchAmbient) { showBackHint = false }
        }

        if model.solvedAt != nil {
            if case .back = gesture { model.goHome() }
            return
        }

        if rose != nil {
            handleRose(gesture)
        } else {
            handleBoard(gesture)
        }
    }

    private func handleBoard(_ gesture: CouchGesture) {
        switch gesture {
        case .swipe(let direction):
            // Past the board's edge on the panel's side is settings: the
            // panel lives there, so the thumb goes where the panel will be.
            // A route a four-way remote and a thumb that cannot find "hold"
            // both have (1.2 beta: settings could not be opened in a game).
            if Self.leavesTowardPanel(cursor: cursor, direction: direction,
                                      layout: layoutDirection) {
                openPanel(.settings)
            } else {
                moveCursor(direction)
            }
        case .tap:
            primary(.tap) { openRose() }
        case .click:
            primary(.click) { openRose() }
        case .holdBegan:
            // Press and hold the clickpad, anywhere: settings. It is also the
            // four-way remotes' only route, since `.playPauseLongPress` needs
            // the 8-way reader (see DEVIATIONS.md).
            openPanel(.settings)
        case .playPause:
            withAnimation(.couchFast) { remotePencil.toggle() }
            lastPencilFlip = Date()
        case .playPauseLongPress:
            // The long press leaked a `.playPause` first — un-flip it.
            if let flip = lastPencilFlip, Date().timeIntervalSince(flip) < 1.2 {
                withAnimation(.couchFast) { remotePencil.toggle() }
            }
            lastPencilFlip = nil
            performUndo()
        case .back:
            if panel != nil {
                closePanel()
            } else {
                guardedExit()
            }
        case .flick, .holdEnded:
            // Cardinal flicks already arrive as .swipe; acting on .flick too
            // would double-move the cursor.
            break
        }
    }

    private func handleRose(_ gesture: CouchGesture) {
        guard rose != nil else { return }
        let now = Date.timeIntervalSinceReferenceDate
        switch gesture {
        case .swipe(let direction):
            // Applied at once so the ring answers the thumb; the stroke that
            // ends this swipe may still settle it on a diagonal.
            let step = Self.step(direction)
            roseFocus.swipe(dx: step.dx, dy: step.dy, at: now)
            syncRoseFocus()
        case .flick(let direction):
            // The analog stroke only ever *moves* the focus now. Placing is
            // the tap's job, so a swipe that was only looking writes nothing.
            let step = Self.step(direction)
            roseFocus.stroke(dx: step.dx, dy: step.dy, at: now)
            syncRoseFocus()
        case .tap:
            primary(.tap) { commit(digit: roseFocus.digit) }
        case .click:
            primary(.click) { commit(digit: roseFocus.digit) }
        case .back:
            withAnimation(.couchFast) { rose = nil }
        case .playPause, .playPauseLongPress, .holdBegan, .holdEnded:
            break
        }
    }

    /// Run a primary action once per thumb, whichever of tap or click said it.
    private func primary(_ source: PrimaryPressGate.Source, _ action: () -> Void) {
        guard pressGate.accept(source, at: Date.timeIntervalSinceReferenceDate) else { return }
        action()
    }

    /// The first Back on a quiet board arms the exit and says so; a second
    /// inside the window saves and goes home. See `BackGuard`.
    private func guardedExit() {
        if backGuard.press(at: Date.timeIntervalSinceReferenceDate) {
            showBackHint = false
            model.goHome()
            return
        }
        withAnimation(.couchFast) { showBackHint = true }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(BackGuard.window * 1_000_000_000))
            if backGuard.hasExpired(at: Date.timeIntervalSinceReferenceDate) {
                backGuard.disarm()
                withAnimation(.couchAmbient) { showBackHint = false }
            }
        }
    }


    private func syncRoseFocus() {
        guard var state = rose else { return }
        state.focusedIndex = roseFocus.index
        rose = state
    }

    /// Screen-space steps, down positive — the keypad's own orientation.
    private static func step(_ direction: Direction4) -> (dx: Int, dy: Int) {
        switch direction {
        case .up: return (0, -1)
        case .down: return (0, 1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        }
    }

    private static func step(_ direction: Direction8OrCenter) -> (dx: Int, dy: Int) {
        switch direction {
        case .center: return (0, 0)
        case .up: return (0, -1)
        case .down: return (0, 1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        case .upLeft: return (-1, -1)
        case .upRight: return (1, -1)
        case .downLeft: return (-1, 1)
        case .downRight: return (1, 1)
        }
    }

    private func openRose() {
        guard let game = model.game, !game.isGiven(cursor) else { return }
        // Notes only make sense in empty cells; on a filled one the pencil
        // switch steps aside and the rose writes a digit over it.
        let pencil = remotePencil && game.entry(at: cursor) == 0
        roseFocus = RoseFocus()
        withAnimation(.couchFast) {
            rose = RoseState(pencil: pencil)
        }
    }

    private func commit(digit: Int) {
        guard let state = rose else { return }
        if state.pencil {
            model.togglePencil(digit, at: cursor)
        } else {
            model.place(digit, at: cursor)
        }
        withAnimation(.couchFast) { rose = nil }
    }

    /// Whether a swipe from `cursor` would leave the board on the side the
    /// side panel occupies — trailing, so right, or left under RTL.
    static func leavesTowardPanel(cursor: Int, direction: Direction4,
                                  layout: LayoutDirection) -> Bool {
        let column = cursor % 9
        switch (direction, layout) {
        case (.right, .leftToRight): return column == 8
        case (.left, .rightToLeft): return column == 0
        default: return false
        }
    }

    private func moveCursor(_ direction: Direction4) {
        var row = cursor / 9, col = cursor % 9
        switch direction {
        case .up: row = max(0, row - 1)
        case .down: row = min(8, row + 1)
        case .left: col = max(0, col - 1)
        case .right: col = min(8, col + 1)
        }
        cursor = row * 9 + col
    }

    private func performUndo() {
        guard let move = model.undoMove() else { return }
        let next = UndoToastState(text: UndoPhrase.forMove(move))
        withAnimation(.couchFast) { toast = next }
        toastDismissal?.cancel()
        toastDismissal = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.couchAmbient) {
                if toast?.id == next.id { toast = nil }
            }
        }
    }
}

#endif

/// Undo feedback shared by the TV and touch game screens.
struct UndoToastState: Equatable {
    let id = UUID()
    let text: String
}

/// What the undo toast says, for all four input grammars.
///
/// **One block, because there were four.** `TouchUI`, `MacUI`, `GameScreen` and
/// `PadSession` are fenced to different platforms and each carried its own copy
/// of these three sentences — so a translator would have met "Undid 4" four
/// times, with no way to see they were the same string, and any one of the four
/// could have drifted without a build noticing. This file is where they meet:
/// `UndoToastState` is already the shared type, and it is outside the tvOS
/// fence for exactly that reason.
///
/// `forMove` rather than four call sites switching on `kind`: the switch was
/// also copied four times, and only one of the four handled bulk auto-notes.
enum UndoPhrase {
    static let autoNotes = Strings.string("game.undo.autoNotes")

    static func placement(_ digit: Int) -> String {
        Strings.string("game.undo.placement", .int(digit))
    }
    static func restored(_ digit: Int) -> String {
        Strings.string("game.undo.restored", .int(digit))
    }
    static func note(_ digit: Int) -> String {
        Strings.string("game.undo.note", .int(digit))
    }

    /// The sentence for one undone move. `isBulkNotes` is checked first because
    /// a wand fill arrives as a `.pencil` move and would otherwise report a
    /// single digit it never wrote.
    static func forMove(_ move: NineMove) -> String {
        if move.isBulkNotes { return autoNotes }
        switch move.kind {
        case .place: return placement(move.digit)
        case .erase: return restored(move.digit)
        case .pencil: return note(move.digit)
        }
    }
}
