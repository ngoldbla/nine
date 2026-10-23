// TVShelf.swift — the Apple TV shelf as one board per screen (tvOS input pass).
//
// The shelf was three rows of web-style cards — three difficulty tiles, two
// extras, then SharePlay and Game Center — at phone proportions scaled up.
// Review: "a messy version of a website; it needs to be rethought for the 4K
// TV screen", with "a full-screen swipe between options for game modes".
//
// So the shelf is a pager. Each page is one mode — Continue (when a board is
// in progress), Gentle, Steady, Sharp — and its subject is a large board drawn
// in that band's own hue, digits arriving in a scatter as the page lands and
// then holding perfectly still (the idle-pixel test: a shelf left alone draws
// nothing). Swipe left and right to page, tap or click to play.
//
// Everything that is not a mode — Boards, History, Play together, Game Center,
// Replays — is one row of Liquid Glass buttons along the bottom, reached by
// swiping down. The rest of the chrome (the page dots, "tap to play") is
// transient: it shows on input and recedes, as every surface in Nine does.
#if os(tvOS)
import SwiftUI
import CouchKit

/// One page of the shelf.
enum ShelfPage: Hashable {
    case resume
    case band(Difficulty)
}

/// A secondary door off the shelf, in the bottom glass row.
struct ShelfAction: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let action: @MainActor () -> Void
}

struct TVShelf: View {
    let model: AppModel
    let accent: Color
    /// False while a sheet, the ambient surface or the welcome card owns the
    /// remote, so the pager lets go of focus.
    let isActive: Bool
    let actions: [ShelfAction]
    /// Every gesture on the shelf is activity, for the ambient idle clock.
    let onActivity: @MainActor () -> Void

    @State private var index = 0
    /// +1 when the last page change went forward, -1 back — the direction the
    /// board slides in from.
    @State private var direction = 1
    @State private var actionsOpen = false
    @State private var chrome = ChromeVisibility()
    @FocusState private var focusedAction: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pages: [ShelfPage] {
        (model.savedFree != nil ? [.resume] : []) + Difficulty.rowBands.map { .band($0) }
    }

    private var page: ShelfPage { pages[min(index, pages.count - 1)] }
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    var body: some View {
        ZStack {
            stage
            chromeLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: pages.count) { _, count in index = min(index, count - 1) }
        #if DEBUG
        .onAppear { registerInjector() }
        #endif
    }

    // MARK: - The page

    @ViewBuilder
    private var stage: some View {
        let surface = ZStack {
            ShelfPageView(model: model, page: page, accent: accent, tones: tones,
                          direction: direction, reduceMotion: reduceMotion)
                .id(page)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // While the action row is open, the surface lets go of the remote so
        // the focus engine can walk the glass buttons.
        if isActive && !actionsOpen {
            surface.couchRemote(chrome: chrome) { gesture in handle(gesture) }
        } else {
            surface
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(direction) * 260)),
            removal: .opacity.combined(with: .offset(x: CGFloat(-direction) * 260)))
    }

    private func handle(_ gesture: CouchGesture) {
        onActivity()
        switch gesture {
        case .swipe(.left): turn(-1)
        case .swipe(.right): turn(+1)
        case .swipe(.down): openActions()
        case .tap, .click: play()
        default: break
        }
    }

    private func turn(_ step: Int) {
        let next = index + step
        guard pages.indices.contains(next) else { return }
        direction = step
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { index = next }
    }

    private func play() {
        switch page {
        case .resume: model.continueSaved()
        case .band(let band): model.startFree(band)
        }
    }

    private func openActions() {
        withAnimation(.couchFast) { actionsOpen = true }
        Task { @MainActor in focusedAction = actions.first?.id }
    }

    private func closeActions() {
        withAnimation(.couchFast) { actionsOpen = false }
        chrome.touch()
    }

    // MARK: - Chrome

    /// The page dots and the play hint on input; the glass action row along
    /// the bottom, present while open or while the chrome is awake.
    private var chromeLayer: some View {
        let awake = chrome.isVisible || actionsOpen
        return VStack(spacing: 26) {
            Spacer()
            HStack(spacing: 14) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? accent : Color.primary.opacity(0.28))
                        .frame(width: i == index ? 34 : 12, height: 12)
                }
            }
            .opacity(awake && !actionsOpen ? 1 : 0)
            .accessibilityHidden(true)
            HStack(spacing: 22) {
                ForEach(actions) { action in
                    Button {
                        // The row lets go before the door opens. Left open it
                        // kept focus under the sheet, so Back closed the row,
                        // not the sheet — and History, with nothing else on it
                        // the focus engine would leave the row for, could not
                        // be left at all (1.2 beta).
                        withAnimation(.couchFast) { actionsOpen = false }
                        action.action()
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(ShelfGlassButtonStyle(accent: accent))
                    .focused($focusedAction, equals: action.id)
                }
            }
            .opacity(actionsOpen ? 1 : (awake ? 0.55 : 0))
            .disabled(!actionsOpen || !isActive)
            .focusSection()
            .onMoveCommand { direction in
                if direction == .up { closeActions() }
            }
            .onExitCommand { closeActions() }
            if !actionsOpen {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(awake ? 0.8 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 10)
        .animation(.couchFast, value: awake)
    }

    #if DEBUG
    /// `-NineRemoteInjector` on the shelf: the pager's gestures, and the glass
    /// row's buttons by name (the focus engine is not reachable from a sim).
    private func registerInjector() {
        RemoteInjector.shared.onGesture = { gesture in
            if actionsOpen {
                if gesture == .back || gesture == .swipe(.up) { closeActions() }
                return
            }
            handle(gesture)
        }
    }
    #endif
}

/// One mode, full screen: the board on the leading side, its name and what it
/// asks of you on the trailing side.
private struct ShelfPageView: View {
    let model: AppModel
    let page: ShelfPage
    let accent: Color
    let tones: ThemeTones
    let direction: Int
    let reduceMotion: Bool

    @State private var arrived = false

    private var tint: Color {
        switch page {
        case .resume: return accent
        case .band(let band): return band.bandTone(isLight: tones.isLight)
        }
    }

    var body: some View {
        ZStack {
            // The page's own light: a soft glow in the band's hue behind the
            // board, the size of the screen so it has no edge of its own.
            // Drawn by a shader, not a `RadialGradient`: the gradient banded
            // into rings on a television (see ShelfGlow.metal).
            // The shader ignores what it is drawn over and outputs only light.
            Rectangle()
                .fill(.black)
                .visualEffect { [tint, peak = tones.isLight ? 0.18 : 0.28] content, proxy in
                    content.colorEffect(ShaderLibrary.shelfGlow(
                        .float2(proxy.size.width * 0.33, proxy.size.height * 0.5),
                        .float(620),
                        .color(tint),
                        .float(peak)))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            content
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { arrived = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        HStack(spacing: 110) {
            ShelfBoardArt(page: page, model: model, tint: tint, tones: tones,
                          reveal: arrived || reduceMotion ? 1 : 0)
                .frame(width: 620, height: 620)
                // Parallax: the board travels further than the words.
                .offset(x: arrived || reduceMotion ? 0 : CGFloat(direction) * 120)
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 124, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                status
                    .padding(.top, 18)
            }
            .frame(width: 720, alignment: .leading)
        }
    }

    private var title: String {
        switch page {
        case .resume: return Strings.string("shelf.continue.title")
        case .band(let band): return Strings.difficulty(band)
        }
    }

    private var subtitle: String {
        switch page {
        case .resume:
            guard let saved = model.savedFree else { return "" }
            return Strings.difficulty(saved.difficulty) + " · "
                + Int(saved.game.fillFraction * 100).formatted(.percent)
        case .band(let band): return band.blurb
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .band(let band) = page, model.composing == .free(band) {
            Label(Strings.string("status.composing"), systemImage: "sparkles")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// A board as the shelf draws it: a real sudoku's digits in the band's hue on
/// a glass slab, as many givens as the band deals, arriving in a scatter.
/// The Continue page draws the board in progress, digit for digit.
private struct ShelfBoardArt: View {
    let page: ShelfPage
    let model: AppModel
    let tint: Color
    let tones: ThemeTones
    /// 0 → 1: how much of the scatter has arrived. Animated by the page.
    var reveal: Double

    /// A valid solution grid: the classic shifted-row construction, put
    /// through the permutations that keep a sudoku a sudoku — digits
    /// relabelled, rows shuffled inside their band and columns inside their
    /// stack — seeded per page, so each mode shows its own believable board and
    /// every digit still obeys the rules it advertises.
    private static func solution(_ cell: Int, seed: UInt64) -> Int {
        func shuffled(_ values: [Int], _ salt: Int) -> [Int] {
            values.sorted {
                CouchHash.noise($0, salt, seed: seed) < CouchHash.noise($1, salt, seed: seed)
            }
        }
        let digits = shuffled(Array(1...9), 0)
        let row = cell / 9, column = cell % 9
        let rowOrder = shuffled([0, 1, 2], 10 + row / 3)
        let columnOrder = shuffled([0, 1, 2], 20 + column / 3)
        let r = (row / 3) * 3 + rowOrder[row % 3]
        let c = (column / 3) * 3 + columnOrder[column % 3]
        return digits[(r * 3 + r / 3 + c) % 9]
    }

    /// Givens per box, the same counts `MiniBoard` draws (45 / 36 / 27).
    private static func perBox(_ band: Difficulty) -> Int {
        switch band {
        case .gentle: return 5
        case .steady: return 4
        default: return 3
        }
    }

    /// (cell, digit, arrival order 0…1) for every digit on the art.
    private var digits: [(cell: Int, digit: Int, order: Double)] {
        switch page {
        case .resume:
            guard let game = model.savedFree?.game else { return [] }
            return (0..<81).compactMap { cell in
                let d = game.entry(at: cell)
                return d == 0 ? nil : (cell, d, CouchHash.noise(cell % 9, cell / 9, seed: 0x5E))
            }
        case .band(let band):
            var out: [(Int, Int, Double)] = []
            for box in 0..<9 {
                let cells = (0..<9).map { i in
                    ((box / 3) * 3 + i / 3) * 9 + (box % 3) * 3 + i % 3
                }
                let ranked = cells.sorted {
                    CouchHash.noise($0 % 9, $0 / 9, seed: 0x91) < CouchHash.noise($1 % 9, $1 / 9, seed: 0x91)
                }
                let seed = UInt64(Difficulty.rowBands.firstIndex(of: band) ?? 0) + 0x31
                for cell in ranked.prefix(Self.perBox(band)) {
                    out.append((cell, Self.solution(cell, seed: seed),
                                CouchHash.noise(cell % 9, cell / 9, seed: 0x7A)))
                }
            }
            return out
        }
    }

    var body: some View {
        let digits = self.digits
        let reveal = self.reveal
        let tint = self.tint
        let tones = self.tones
        Canvas { context, size in
            let gutter = size.width * 0.018
            let cell = (size.width - 2 * gutter) / 9
            func rect(_ index: Int) -> CGRect {
                let row = index / 9, column = index % 9
                return CGRect(x: CGFloat(column) * cell + CGFloat(column / 3) * gutter,
                              y: CGFloat(row) * cell + CGFloat(row / 3) * gutter,
                              width: cell, height: cell)
            }
            // Nine plates — the boxes — cut into the slab.
            for box in 0..<9 {
                let first = rect((box / 3) * 27 + (box % 3) * 3)
                let last = rect((box / 3) * 27 + (box % 3) * 3 + 20)
                context.fill(Path(roundedRect: first.union(last).insetBy(dx: 3, dy: 3),
                                  cornerRadius: cell * 0.22),
                             with: .color(tones.wellHue.opacity(tones.isLight ? 0.06 : 0.32)))
            }
            for item in digits {
                // Each digit fades in over its own slice of the reveal, in
                // noise order, so the board composes as a scatter.
                let start = item.order * 0.7
                let alpha = min(1, max(0, (reveal - start) / 0.3))
                guard alpha > 0 else { continue }
                let frame = rect(item.cell)
                let text = Text("\(item.digit)")
                    .font(.system(size: cell * 0.56, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
                context.opacity = alpha
                context.draw(text, at: CGPoint(x: frame.midX, y: frame.midY))
                context.opacity = 1
            }
        }
        .padding(34)
        .couchGlass(in: RoundedRectangle(cornerRadius: 56, style: .continuous))
        .shadow(color: .black.opacity(tones.isLight ? 0.12 : 0.4), radius: 40, y: 24)
        .accessibilityHidden(true)
    }
}

/// The shelf's secondary doors: neutral glass at rest, the accent's glass and
/// a lift under focus — all inside the capsule.
private struct ShelfGlassButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        GlassBody(configuration: configuration, accent: accent)
    }

    private struct GlassBody: View {
        let configuration: ButtonStyle.Configuration
        let accent: Color
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.white : Color.primary)
                .background {
                    if isFocused {
                        Capsule().fill(accent.opacity(0.85))
                    }
                }
                .couchGlassInteractive(in: Capsule())
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 10)
                .animation(.couchFast, value: isFocused)
        }
    }
}
#endif
