// TVChrome.swift — the small pieces the TV's screen chrome is made of (tvOS
// input pass): the corner note every transient message now uses, the text view
// that draws "▶︎" as the remote's real Play/Pause glyph, and the shield that
// keeps a controller's Circle from becoming the system's Menu during play.
#if os(tvOS)
import SwiftUI
import UIKit
import GameController
import CouchKit

enum TVChrome {
    /// The bottom-leading margin beside a centred 956pt board on a 1920pt
    /// screen, inside tvOS's 80pt safe inset: 1920 / 2 − 478 − 80 ≈ 402.
    static let noteWidth: CGFloat = 380
}

// MARK: - The Play/Pause glyph

/// Text with every "▶︎" drawn as the Siri Remote's own Play/Pause symbol.
///
/// The catalog keeps the ▶︎ character in all ten languages — translators place
/// it where their grammar wants the button — but on a television a bare
/// triangle reads as "swipe right" (input pass review: "is it the play button
/// or the right button?"). So the character is the placeholder and this is the
/// one place it becomes the button.
struct GlyphText: View {
    let string: String

    init(_ string: String) { self.string = string }

    var body: some View {
        Self.text(string)
    }

    static func text(_ string: String) -> Text {
        let marker = "▶︎"
        let parts = string.components(separatedBy: marker)
        var result = Text(verbatim: parts[0])
        for part in parts.dropFirst() {
            result = result + Text(Image(systemName: "playpause.fill")) + Text(verbatim: part)
        }
        return result
    }
}

// MARK: - Corner notes

/// A transient message in the screen's bottom-leading corner: an icon and a
/// sentence on one pane of glass. Wraps beside a centred board; one line under
/// a shrunk one.
struct CornerNote: View {
    let text: String
    let systemImage: String
    var oneLine = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            GlyphText(text)
                .font(CouchTypography.label)
                .foregroundStyle(.primary)
                .lineLimit(oneLine ? 1 : 3)
                .minimumScaleFactor(oneLine ? 0.8 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .leading)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The controller shield

/// Hosts its content under a `GCEventViewController` that keeps game
/// controller input away from UIKit.
///
/// tvOS turns a gamepad's B / Circle into the system's Menu press as well as
/// delivering it to GameController, which is how "undo" used to leave the
/// board and how Circle on the shelf leaves the app. While this is on screen
/// the system never sees the pad, so PadKit's Circle is the only Circle and the
/// board decides what it means (Back, with the two-press guard).
///
/// **It silences the Siri Remote too** — the remote is a game controller to
/// GameController — which is why only the pad body wears it, and only while
/// settings (which needs the focus engine) are closed.
struct PadEventShield<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> GCEventViewController {
        let shield = GCEventViewController()
        shield.controllerUserInteractionEnabled = false
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        shield.addChild(host)
        host.view.frame = shield.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shield.view.addSubview(host.view)
        host.didMove(toParent: shield)
        return shield
    }

    func updateUIViewController(_ shield: GCEventViewController, context: Context) {
        (shield.children.first as? UIHostingController<Content>)?.rootView = content
    }
}
#endif
