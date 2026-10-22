// RemoteKit — the one place clickpad input becomes intent (PRD §5.2).
// Apps attach `.couchRemote { gesture in … }` and never touch raw events.
//
// Two layers:
//   • The always-correct 4-way path, built on tvOS-safe SwiftUI commands
//     (`onMoveCommand`, `onPlayPauseCommand`, `onExitCommand`, long press).
//   • An optional GameController-based 8-way flick reader for the 3×3 rose
//     (Nine's digits). It samples the microGamepad's analog dpad during a
//     touch and classifies the stroke with CouchCore's flick math. If no
//     analog data is available it fails soft: apps still get 4-way swipes
//     and `RemoteKit.capability` reports `.fourWay`.
#if os(tvOS)
import SwiftUI
import CouchCore
#if canImport(GameController)
import GameController
#endif

// MARK: - Gestures

/// Declarative gesture intents an app subscribes to.
public enum CouchGesture: Sendable, Equatable {
    /// Discrete flick: up/down/left/right (from the system move command).
    case swipe(Direction4)
    /// 3×3 rose: one of the 8 directions, from a completed stroke. Only
    /// delivered when the 8-way reader is enabled and analog dpad data is
    /// available. A bare touch arrives as `.tap`, never as `.flick(.center)`.
    case flick(Direction8OrCenter)
    /// Clickpad press.
    case click
    /// A light tap on the touch surface — a touch that never clicked and
    /// never travelled. Only delivered when the 8-way reader is enabled (it is
    /// the only thing that can see a touch that did not press), and never for
    /// a touch that also clicked or produced a move command: a click is also a
    /// touch, and so is a press on the ring's edge, and neither may arrive
    /// twice.
    case tap
    case holdBegan
    case holdEnded
    case playPause
    /// Suite-wide: opens the app's single prefs sheet. Delivered by the
    /// 8-way reader (it can time the button); systems without it never
    /// emit this, so apps should also expose the sheet from a pill action.
    case playPauseLongPress
    /// Menu/Back — delivered only when `interceptsBack` is true; at the app
    /// root leave it false and defer to the system (suite rule).
    case back
}

public enum RemoteKit {
    /// What the connected remote can express right now.
    @MainActor public static var capability: RemoteCapability {
        #if canImport(GameController)
        if GCController.current?.microGamepad != nil { return .eightWay }
        return .fourWay
        #else
        return .fourWay
        #endif
    }
}

// MARK: - View modifier

extension View {
    /// Attach the suite gesture grammar. The modified view is made focusable
    /// (a requirement for receiving any remote commands) — do not add your
    /// own `.focusable()` on top.
    ///
    /// - Parameters:
    ///   - chrome: poked on every gesture so transient chrome wakes up.
    ///   - eightWay: also run the analog flick reader and deliver `.flick`.
    ///   - interceptsBack: capture Menu/Back as `.back`. Leave `false` at
    ///     the app root so the system handles exit.
    public func couchRemote(
        chrome: ChromeVisibility? = nil,
        eightWay: Bool = false,
        interceptsBack: Bool = false,
        onGesture: @escaping @MainActor (CouchGesture) -> Void
    ) -> some View {
        modifier(CouchRemoteModifier(
            chrome: chrome,
            eightWay: eightWay,
            interceptsBack: interceptsBack,
            onGesture: onGesture
        ))
    }
}

struct CouchRemoteModifier: ViewModifier {
    let chrome: ChromeVisibility?
    let eightWay: Bool
    let interceptsBack: Bool
    let onGesture: @MainActor (CouchGesture) -> Void

    @State private var holdActive = false
    // tvOS routes remote commands only to the *focused* view, and this
    // modifier is usually a screen's sole focusable — if focus parks nowhere
    // after a screen swap, every click is silently dropped. Claim focus on
    // appear (immediately, then once more after transition animations can
    // steal it). Never re-claim continuously: sheets with native focus
    // Buttons must be able to take focus while a surface stays attached.
    @FocusState private var focused: Bool
    #if canImport(GameController)
    @State private var flickReader: MicroGamepadFlickReader?
    #endif

    @MainActor
    private func emit(_ gesture: CouchGesture) {
        chrome?.touch()
        onGesture(gesture)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .focusable()
            .focused($focused)
            .onMoveCommand { direction in
                // A press on the ring's edge is a touch too; it must not also
                // classify as a tap when the finger lifts.
                suppressTap()
                switch direction {
                case .up: emit(.swipe(.up))
                case .down: emit(.swipe(.down))
                case .left: emit(.swipe(.left))
                case .right: emit(.swipe(.right))
                @unknown default: break
                }
            }
            .onPlayPauseCommand { emit(.playPause) }
            .onTapGesture {
                suppressTap()
                emit(.click)
            }
            .onLongPressGesture(
                minimumDuration: 0.6,
                perform: {
                    holdActive = true
                    emit(.holdBegan)
                },
                onPressingChanged: { pressing in
                    if !pressing && holdActive {
                        holdActive = false
                        emit(.holdEnded)
                    }
                }
            )
            .onAppear {
                startFlickReaderIfNeeded()
                focused = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !focused { focused = true }
                }
            }
            .onDisappear { stopFlickReader() }

        if interceptsBack {
            base.onExitCommand { emit(.back) }
        } else {
            base
        }
    }

    @MainActor
    private func startFlickReaderIfNeeded() {
        #if canImport(GameController)
        guard eightWay, flickReader == nil else { return }
        let reader = MicroGamepadFlickReader()
        reader.onFlick = { direction in
            emit(direction == .center ? .tap : .flick(direction))
        }
        reader.onPlayPauseLongPress = { emit(.playPauseLongPress) }
        reader.start()
        flickReader = reader
        #endif
    }

    /// Tell the reader the touch in progress already meant something else.
    @MainActor
    private func suppressTap() {
        #if canImport(GameController)
        flickReader?.suppressCurrentTap()
        #endif
    }

    @MainActor
    private func stopFlickReader() {
        #if canImport(GameController)
        flickReader?.stop()
        flickReader = nil
        #endif
    }
}

// MARK: - 8-way flick reader

#if canImport(GameController)
/// Samples the Siri Remote's analog dpad (absolute touch coordinates) during
/// a touch and classifies the released stroke through `FlickClassifier`.
/// Ambiguous and rest strokes are dropped on the floor — never misfired.
@MainActor
final class MicroGamepadFlickReader {
    var onFlick: (@MainActor (Direction8OrCenter) -> Void)?
    var onPlayPauseLongPress: (@MainActor () -> Void)?
    var thresholds = FlickThresholds.standard

    private var samples: [(t: TimeInterval, x: Double, y: Double)] = []
    /// Set when the touch in progress clicked or moved the focus. A stroke
    /// that did either is not a tap, whatever its geometry says: the press
    /// beat the finger's lift, and the finger's lift is the only edge the
    /// reader sees.
    private var tapSuppressed = false
    private var playPausePressedAt: TimeInterval?
    private var observer: (any NSObjectProtocol)?

    func start() {
        configure(GCController.current)
        observer = NotificationCenter.default.addObserver(
            forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main
        ) { [weak self] note in
            // Registered with `queue: .main`, so this closure runs on the main
            // thread; the notification payload never actually crosses isolation.
            nonisolated(unsafe) let controller = note.object as? GCController
            MainActor.assumeIsolated {
                self?.configure(controller)
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        samples.removeAll()
        tapSuppressed = false
    }

    /// The touch in progress clicked or moved: whatever it does on lift, it
    /// is not a tap.
    func suppressCurrentTap() {
        tapSuppressed = true
    }

    private func configure(_ controller: GCController?) {
        guard let pad = controller?.microGamepad else { return }
        pad.reportsAbsoluteDpadValues = true
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                self?.handleSample(x: Double(x), y: Double(y))
            }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                self?.handlePlayPause(pressed: pressed)
            }
        }
    }

    private func handleSample(x: Double, y: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        // The dpad reports exactly (0, 0) when the finger lifts.
        if x == 0 && y == 0 {
            finishStroke(at: now)
        } else {
            samples.append((t: now, x: x, y: y))
            // A resting thumb can stream for a long time; cap the buffer.
            if samples.count > 512 { samples.removeFirst(256) }
        }
    }

    private func finishStroke(at now: TimeInterval) {
        let suppressed = tapSuppressed
        defer {
            samples.removeAll(keepingCapacity: true)
            tapSuppressed = false
        }
        guard let first = samples.first, let last = samples.last else { return }
        let duration = max(0.001, now - first.t)
        let result = FlickClassifier.classify8(
            dx: last.x - first.x,
            dy: last.y - first.y,
            duration: duration,
            thresholds: thresholds
        )
        if case .direction(let direction) = result {
            // A still touch that clicked is a click, not a tap. A stroke that
            // travelled keeps its direction even if a move command fired on
            // the way — that is the swipe the reader exists to classify.
            if direction == .center, suppressed { return }
            onFlick?(direction)
        }
        // .ambiguous / .rest: fail soft — better no digit than a wrong digit.
    }

    private func handlePlayPause(pressed: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        if pressed {
            playPausePressedAt = now
        } else if let pressedAt = playPausePressedAt {
            playPausePressedAt = nil
            if now - pressedAt >= 0.6 {
                onPlayPauseLongPress?()
            }
        }
    }
}
#endif
#endif
