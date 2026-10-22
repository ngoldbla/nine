// TVSidePanel.swift — settings and the controls guide, *beside* the board
// (tvOS input pass).
//
// The prefs sheet used to be `GlassSheet`'s fixed 720pt panel laid over a
// 900pt board, with no scroll view: on a 1080p screen its last two sections
// hung off the bottom of the television and the board under it was hidden by
// exactly the thing a player opens mid-solve to tune. So:
//
//   • **Side by side, not on top.** While a panel is open the board scales to
//     `TVPanelMetrics.boardScale` at the leading edge and the panel takes the
//     trailing side. A colour change shows on the board in the same glance.
//   • **The settings scroll** (`TVSettingsList`), focus-driven as every tvOS
//     list is, so no row is ever below a fold the remote cannot reach.
//
// The controls guide is the other half: Apple's own drawing of the device —
// `appletvremote.gen4.fill`, `gamecontroller.fill` — with one leader line per
// job ending in a dot *on* the control it names. Five jobs on the remote, six
// on a controller, and nothing else (review: "reduce the controls to the
// minimum"). The guide is read-only and leaves the board live, so a player
// learns a gesture by doing it with its label in view. Back closes it.
#if os(tvOS)
import SwiftUI
import CouchKit

/// Which panel is beside the board, if any.
enum TVPanel: Equatable {
    case settings
    case controls(TVControlsDevice)
}

/// Which input device the controls guide draws.
enum TVControlsDevice: Equatable {
    case remote
    case controller
}

enum TVPanelMetrics {
    /// Measured inside tvOS's own safe area (80pt each side, 60 top and
    /// bottom), which already holds both off the bezel: 1760pt across. The
    /// board draws 956 × 0.84 ≈ 803pt from the leading edge and the panel takes
    /// 820 from the trailing one, so 137pt of ground separates them — enough
    /// that no accent's glow on either reaches the other.
    static let width: CGFloat = 820
    static let boardScale: CGFloat = 0.84
    /// The board's own drawn side (`BoardMetrics.side` plus its 28pt inset
    /// either side), so the scaled stage can be given its scaled frame.
    static let boardSide: CGFloat = BoardMetrics.side + 56
    static let padding: CGFloat = 44
    static let corner: CGFloat = 44
    /// The guides' drawing space: the panel's width less its padding.
    static let guide = CGSize(width: 732, height: 640)
}

/// The trailing panel. `settings` is the settings list, built by the caller
/// because the remote and pad bodies hand it different exits.
struct TVSidePanel<Settings: View>: View {
    let panel: TVPanel
    let accent: Color
    let onShow: @MainActor (TVPanel) -> Void
    @ViewBuilder let settings: () -> Settings

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            switch panel {
            case .settings:
                ScrollView {
                    settings()
                }
                // Room inside the clip for a focused row's lift, so the scroll
                // edge never shaves a row in half.
                .contentMargins(.vertical, 16, for: .scrollContent)
                .contentMargins(.horizontal, 8, for: .scrollContent)
            case .controls(.remote):
                RemoteGuide(accent: accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .controls(.controller):
                ControllerGuide(accent: accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            Text(footer)
                .couchText(CouchTypography.caption, Color.primary.opacity(0.62))
        }
        .padding(TVPanelMetrics.padding)
        .frame(width: TVPanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .couchGlass(in: RoundedRectangle(cornerRadius: TVPanelMetrics.corner, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .focusSection()
    }

    @ViewBuilder
    private var header: some View {
        switch panel {
        case .settings:
            HStack(alignment: .center, spacing: 14) {
                Text(TVPanelPhrase.settings)
                    .couchText(CouchTypography.heading)
                Spacer(minLength: 8)
                // The way into the guides, at the top where a player looking
                // for "how do I…" will land. Same row style as every setting.
                guideButton(TVPanelPhrase.remote, symbol: "appletvremote.gen4.fill") {
                    onShow(.controls(.remote))
                }
                guideButton(TVPanelPhrase.controller, symbol: "gamecontroller.fill") {
                    onShow(.controls(.controller))
                }
            }
        case .controls(let device):
            HStack(spacing: 18) {
                Image(systemName: device == .remote ? "appletvremote.gen4.fill" : "gamecontroller.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(device == .remote ? TVPanelPhrase.remote : TVPanelPhrase.controller)
                    .couchText(CouchTypography.heading)
            }
        }
    }

    private var footer: String {
        switch panel {
        case .settings: return TVPanelPhrase.settingsFooter
        case .controls: return TVPanelPhrase.controlsFooter
        }
    }

    private func guideButton(
        _ title: String, symbol: String, action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .buttonStyle(TVRowStyle(accent: accent, isLight: colorScheme == .light))
        .fixedSize()
    }
}

// MARK: - Callouts

/// One leader line and its words: `anchor` is the point *on the control*, in
/// the guide's drawing space; `label` is where the line meets the words.
private struct Callout: Identifiable {
    enum Side { case leading, trailing, below, above }
    let id: String
    let anchor: CGPoint
    let label: CGPoint
    let side: Side
    let width: CGFloat
    let rows: [LegendRow]

    /// The words' frame: beside the line's end for leading/trailing, centred
    /// on it for above/below.
    func wordsOrigin(height: CGFloat) -> CGPoint {
        switch side {
        case .trailing: return CGPoint(x: label.x + 12, y: label.y - 18)
        case .leading: return CGPoint(x: label.x - 12 - width, y: label.y - 18)
        case .below: return CGPoint(x: label.x - width / 2, y: label.y + 10)
        case .above: return CGPoint(x: label.x - width / 2, y: label.y - 10 - height)
        }
    }
}

/// The leader lines with a dot on each control, then the words.
private struct CalloutLayer: View {
    let callouts: [Callout]
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for callout in callouts {
                    var path = Path()
                    path.move(to: callout.anchor)
                    path.addLine(to: callout.label)
                    context.stroke(path, with: .color(accent), lineWidth: 3)
                    let dot = CGRect(x: callout.anchor.x - 9, y: callout.anchor.y - 9,
                                     width: 18, height: 18)
                    context.fill(Path(ellipseIn: dot), with: .color(accent))
                    context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 3)
                }
            }
            .frame(width: TVPanelMetrics.guide.width, height: TVPanelMetrics.guide.height)
            .accessibilityHidden(true)
            ForEach(callouts) { callout in
                CalloutWords(callout: callout, accent: accent)
            }
        }
    }
}

private struct CalloutWords: View {
    let callout: Callout
    let accent: Color
    @State private var height: CGFloat = 0

    var body: some View {
        let trailingAligned = callout.side == .leading
        let alignment: HorizontalAlignment = trailingAligned ? .trailing
            : (callout.side == .trailing ? .leading : .center)
        let textAlignment: TextAlignment = trailingAligned ? .trailing
            : (callout.side == .trailing ? .leading : .center)
        let origin = callout.wordsOrigin(height: height)
        VStack(alignment: alignment, spacing: 8) {
            ForEach(callout.rows) { row in
                VStack(alignment: alignment, spacing: 0) {
                    GlyphText(row.gesture)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                    GlyphText(row.action)
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(textAlignment)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: callout.width,
               alignment: Alignment(horizontal: alignment, vertical: .top))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .offset(x: origin.x, y: origin.y)
    }
}

// MARK: - The remote

/// The Siri Remote (second generation and later) as Apple draws it, with the
/// five jobs it does in Nine. Labels sit on the side of the remote their button
/// is on, so no line crosses another button: the clickpad's two to the right,
/// Back's and Play/Pause's to the left.
private struct RemoteGuide: View {
    let accent: Color

    /// The symbol's frame in the drawing space, and its controls as fractions
    /// of that frame — measured off `appletvremote.gen4.fill` itself, so a dot
    /// lands on the button rather than near it.
    private static let frame = CGRect(x: 268, y: 40, width: 196, height: 520)
    private static func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
    }
    // The clickpad's cutout sits a little lower and larger than its blob's
    // centroid suggests (the ring's lower lip is part of the cutout), so the
    // disc is placed off the rendered remote, not the measurement alone.
    private static let clickpad = at(0.499, 0.262)
    private static let clickpadRadius = frame.width * 0.80 / 2
    private static let back = at(0.315, 0.467)
    private static let playPause = at(0.315, 0.602)

    private var callouts: [Callout] {
        let legend = NineLegend.remote
        // The clickpad does three of the five jobs, so it gets one dot and one
        // block of words — three lines from one place read as three places.
        return [
            Callout(id: "clickpad", anchor: Self.clickpad, label: CGPoint(x: 490, y: 150),
                    side: .trailing, width: 236, rows: [legend.swipe, legend.tap, legend.hold]),
            Callout(id: "back", anchor: Self.back, label: CGPoint(x: 240, y: 230),
                    side: .leading, width: 228, rows: [legend.back]),
            Callout(id: "playPause", anchor: Self.playPause, label: CGPoint(x: 240, y: 400),
                    side: .leading, width: 228, rows: [legend.playPause, legend.holdPlayPause]),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "appletvremote.gen4.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(white: 0.32))
                .frame(width: Self.frame.width, height: Self.frame.height)
                .offset(x: Self.frame.minX, y: Self.frame.minY)
                .accessibilityHidden(true)
            // The clickpad is the board's whole surface in the hand: lit in
            // the accent, so "swipe here, tap here" has a place to point.
            Circle()
                .fill(accent.opacity(0.85))
                .frame(width: Self.clickpadRadius * 2, height: Self.clickpadRadius * 2)
                .position(Self.clickpad)
            Circle()
                .stroke(accent, lineWidth: 4)
                .frame(width: 60, height: 60)
                .position(Self.back)
            Circle()
                .stroke(accent, lineWidth: 4)
                .frame(width: 60, height: 60)
                .position(Self.playPause)
            CalloutLayer(callouts: callouts, accent: accent)
        }
        .frame(width: TVPanelMetrics.guide.width, height: TVPanelMetrics.guide.height,
               alignment: .topLeading)
    }
}

// MARK: - The controller

/// A game controller as Apple draws it, with PlayStation's face glyphs set into
/// the face (an Xbox pad maps A/B/X/Y onto the same four places, which is what
/// GameController's extended profile promises) and the six jobs labelled.
private struct ControllerGuide: View {
    let accent: Color

    private static let frame = CGRect(x: 146, y: 150, width: 440, height: 276)
    private static func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
    }
    private static let dpad = at(0.332, 0.390)
    private static let face = at(0.670, 0.385)
    private static let pitch: CGFloat = 36
    private static let triangle = CGPoint(x: face.x, y: face.y - pitch)
    private static let circle = CGPoint(x: face.x + pitch, y: face.y)
    private static let cross = CGPoint(x: face.x, y: face.y + pitch)
    private static let square = CGPoint(x: face.x - pitch, y: face.y)
    private static let options = at(0.530, 0.150)

    private var callouts: [Callout] {
        let legend = NineLegend.padGuide
        return [
            Callout(id: "options", anchor: Self.options, label: CGPoint(x: 200, y: 110),
                    side: .above, width: 300, rows: [legend.options]),
            Callout(id: "triangle", anchor: Self.triangle, label: CGPoint(x: 570, y: 110),
                    side: .above, width: 300, rows: [legend.triangle]),
            Callout(id: "dpad", anchor: Self.dpad, label: CGPoint(x: 92, y: 470),
                    side: .below, width: 180, rows: [legend.move]),
            Callout(id: "square", anchor: Self.square, label: CGPoint(x: 276, y: 470),
                    side: .below, width: 176, rows: [legend.square]),
            Callout(id: "cross", anchor: Self.cross, label: CGPoint(x: 458, y: 470),
                    side: .below, width: 176, rows: [legend.cross]),
            Callout(id: "circle", anchor: Self.circle, label: CGPoint(x: 640, y: 470),
                    side: .below, width: 180, rows: [legend.circle]),
        ]
    }

    var body: some View {
        let shell = Color(white: 0.32)
        ZStack(alignment: .topLeading) {
            Image(systemName: "gamecontroller.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(shell)
                .frame(width: Self.frame.width, height: Self.frame.height)
                .offset(x: Self.frame.minX, y: Self.frame.minY)
                .accessibilityHidden(true)
            // The symbol has two face buttons; the four PlayStation glyphs go
            // over them, on a patch of the shell's own colour.
            Circle().fill(shell).frame(width: 140, height: 140).position(Self.face)
            faceGlyph("triangle", at: Self.triangle)
            faceGlyph("circle", at: Self.circle)
            faceGlyph("xmark", at: Self.cross)
            faceGlyph("square", at: Self.square)
            Capsule()
                .fill(Color(white: 0.85))
                .frame(width: 14, height: 30)
                .position(Self.options)
            Circle()
                .stroke(accent, lineWidth: 4)
                .frame(width: 100, height: 100)
                .position(Self.dpad)
            CalloutLayer(callouts: callouts, accent: accent)
        }
        .frame(width: TVPanelMetrics.guide.width, height: TVPanelMetrics.guide.height,
               alignment: .topLeading)
    }

    private func faceGlyph(_ symbol: String, at point: CGPoint) -> some View {
        Circle()
            .fill(Color(white: 0.12))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(accent)
            }
            .position(point)
    }
}

// MARK: - Words

enum TVPanelPhrase {
    static var settings: String { Strings.string("game.control.settings") }
    static var remote: String { Strings.string("tv.panel.remote") }
    static var controller: String { Strings.string("tv.panel.controller") }
    static var settingsFooter: String { Strings.string("sheet.dismiss.remote") }
    static var controlsFooter: String { Strings.string("tv.panel.controlsFooter") }
}
#endif
