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

/// A control legend in the same corner: one row per job, read straight down.
///
/// On the remote it is two rows and nothing else — the Play/Pause button's
/// glyph, and what pressing and holding it do. Settings are not in it: the
/// chevron beside the board (`PanelChevron`) says where they are.
///
/// The remote's hint was a `CornerNote` — four jobs run together with middle
/// dots, capped at three lines in a 380pt corner — and on a real television
/// the last job, the only one that says where settings are, was the one cut to
/// an ellipsis (1.2 beta: "it indicates to click something, but gets cut
/// off"). Every catalog entry already separates its jobs with " · ", so the
/// dots are where the rows break, in every language, and no row has a limit.
struct CornerLegend: View {
    let text: String
    /// A leading symbol naming the device, or nil when the rows' own glyphs
    /// already say which device they mean.
    var systemImage: String? = nil

    private var rows: [String] {
        text.components(separatedBy: " · ").filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    GlyphText(row)
                        .font(CouchTypography.label)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .couchGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .leading)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The way to the panel

/// A small chevron in the margin on the board's trailing side: the panel
/// lives there, and a swipe past the board's edge brings it in.
///
/// It replaced the sentence that explained settings (input pass, round 3:
/// "remove the settings explanation and replace it with a subtle chevron").
/// Quiet at rest — a mark in the margin, not a button — and it lifts to the
/// accent when the cursor reaches the edge column, where one more swipe opens
/// the panel. Not a focusable thing and not read aloud: the swipe is the
/// control, and VoiceOver players reach settings by the hold.
struct PanelChevron: View {
    /// The cursor is in the edge column: the next swipe that way opens it.
    let armed: Bool
    let accent: Color

    static let width: CGFloat = 40

    var body: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 54, weight: .semibold))
            .foregroundStyle(armed ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
            .opacity(armed ? 0.95 : 0.45)
            .offset(x: armed ? 6 : 0)
            .flipsForRightToLeftLayoutDirection(true)
            // A fixed slot, so `GameScreen` can centre the board, not the pair.
            .frame(width: Self.width)
            .animation(.couchFast, value: armed)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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
