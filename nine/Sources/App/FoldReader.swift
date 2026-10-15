// FoldReader.swift — the one place the iPhone Duo's fold is measured (PRD-37).
//
// `reservedRegions(kind: .division, options: .includeInactive)` is read from a
// GeometryReader behind the root, validated by `FoldRules.validate`, and
// published as `\.foldBand`. Everything else reads that value; when it is nil
// — every other device, every build without the iOS 27.1 SDK, every frame the
// validator rejects mid-fold — every view takes the path it took before.
//
// `.includeInactive` is not optional: a plain query returns the region only
// while the hinge is bent (measured, contrary to the API text), and the spread
// is the same composition flat or bent.
import SwiftUI
import CouchKit

private struct FoldBandKey: EnvironmentKey {
    static let defaultValue: FoldBand? = nil
}

extension EnvironmentValues {
    var foldBand: FoldBand? {
        get { self[FoldBandKey.self] }
        set { self[FoldBandKey.self] = newValue }
    }
}

private struct FoldState: Equatable {
    var band: FoldBand?
    var width: Double = 0
}

private struct FoldReader: ViewModifier {
    @State private var state = FoldState()

    func body(content: Content) -> some View {
        content
            .environment(\.foldBand, state.band)
            // CouchKit's GlassSheet sizes its trailing panel from this; on the
            // open Duo that is the right pane, 339.5pt, leading edge at 511.5.
            .environment(\.couchPanelWidth, state.band.map {
                CGFloat(FoldRules.panelWidth(width: state.width, band: $0))
            })
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)
            .background { FoldProbe(state: $state) }
            #endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85.29)
private struct FoldProbe: View {
    @Binding var state: FoldState

    var body: some View {
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                let measured = Self.measure(proxy)
                Color.clear
                    .onAppear { state = measured }
                    .onChange(of: measured) { _, new in state = new }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    @available(iOS 27.1, *)
    private static func measure(_ proxy: GeometryProxy) -> FoldState {
        let width = Double(proxy.size.width), height = Double(proxy.size.height)
        let band = proxy.reservedRegions(kind: .division, options: [.includeInactive])
            .lazy
            .compactMap { region in
                FoldRules.validate(
                    FoldBand(leading: Double(region.frame.minX),
                             trailing: Double(region.frame.maxX),
                             isActive: region.isActive),
                    width: width, height: height,
                    regionTop: Double(region.frame.minY),
                    regionBottom: Double(region.frame.maxY))
            }
            .first
        return FoldState(band: band, width: width)
    }
}
#endif

extension View {
    /// Publish the open iPhone Duo's fold to everything below (PRD-37).
    func readsFold() -> some View { modifier(FoldReader()) }

    /// Confine a page to the pane before the fold; identity without one.
    func inLeadingFoldPane() -> some View { modifier(LeadingFoldPane()) }
}

private struct LeadingFoldPane: ViewModifier {
    @Environment(\.foldBand) private var band

    func body(content: Content) -> some View {
        if let band {
            content
                .frame(width: CGFloat(band.leading))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}
