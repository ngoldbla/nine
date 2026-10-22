// RemoteInjector.swift — a DEBUG-only thumb for the Apple TV simulator.
//
// Xcode 27's simulator has no Siri Remote window any more (Device Hub runs
// headless), and neither `simctl` nor `axe` can send a remote press: keyboard
// HID reaches the device but not the focus engine. So the tvOS input pass could
// not be *seen* working without this.
//
// It listens for Darwin notifications — `xcrun simctl spawn <udid> notifyutil
// -p com.couchsuite.nine.inject.tap` — and hands each one to whichever screen
// registered last, which passes remote gestures into the **same** `handle(_:)`
// that `.couchRemote` calls. What it cannot stand in for is said plainly: the
// touch-surface tap classification in RemoteKit and the focus engine's walk
// through the settings panel. Those are hardware facts, verified on an Apple TV.
//
// Reached only by `-NineRemoteInjector`, and sealed by
// `DebugSurfaceSealTests.testTheRemoteInjectorCannotBeReachedInRelease`.
#if os(tvOS)
#if DEBUG
import Foundation
import CouchKit

/// The notification-name prefix. File scope rather than a static on the
/// main-actor class, because the C callback that reads it is not isolated.
private let injectPrefix = "com.couchsuite.nine.inject."

@MainActor
final class RemoteInjector {
    static let shared = RemoteInjector()

    /// Every command a notification may carry: the remote's gestures, then the
    /// few native-focus actions (a focused Button, a shelf card) that have no
    /// gesture to stand in for them.
    static let commands = [
        "up", "down", "left", "right", "tap", "click", "hold", "holdEnd",
        "playPause", "playPauseLong", "back",
        "flick.upLeft", "flick.up", "flick.upRight", "flick.left",
        "flick.right", "flick.downLeft", "flick.down", "flick.downRight",
        "welcome.start", "free.gentle", "free.steady", "free.sharp",
        "panel.remote", "panel.controller",
        "pref.accent", "pref.theme", "pref.timer",
    ]

    /// The live board's remote handler.
    var onGesture: (@MainActor (CouchGesture) -> Void)?
    /// The live screen's handler for everything that is not a gesture.
    var onCommand: (@MainActor (String) -> Void)?

    private var installed = false

    func installIfRequested() {
        guard !installed, CommandLine.arguments.contains("-NineRemoteInjector") else { return }
        installed = true
        NSLog("RemoteInjector: listening")
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for command in Self.commands {
            CFNotificationCenterAddObserver(
                center, nil,
                { _, _, name, _, _ in
                    guard let full = name?.rawValue as String? else { return }
                    let command = String(full.dropFirst(injectPrefix.count))
                    Task { @MainActor in RemoteInjector.shared.dispatch(command) }
                },
                (injectPrefix + command) as CFString, nil, .deliverImmediately)
        }
    }

    private func dispatch(_ command: String) {
        NSLog("RemoteInjector: %@", command)
        if let gesture = Self.gesture(command) {
            onGesture?(gesture)
        } else {
            onCommand?(command)
        }
    }

    private static func gesture(_ command: String) -> CouchGesture? {
        switch command {
        case "up": return .swipe(.up)
        case "down": return .swipe(.down)
        case "left": return .swipe(.left)
        case "right": return .swipe(.right)
        case "tap": return .tap
        case "click": return .click
        case "hold": return .holdBegan
        case "holdEnd": return .holdEnded
        case "playPause": return .playPause
        case "playPauseLong": return .playPauseLongPress
        case "back": return .back
        default:
            guard command.hasPrefix("flick."),
                  let direction = Direction8OrCenter(rawValue: String(command.dropFirst(6)))
            else { return nil }
            return .flick(direction)
        }
    }
}
#endif
#endif
