// Throwaway measurement probe for PRD-37 (iPhone Duo). Never committed.
// Logs, on launch and on every change, what iOS reports about the window.
import SwiftUI
import UIKit

func log(_ s: String) {
    print("DUOPROBE " + s)
    fflush(stdout)
}

func fmt(_ r: CGRect) -> String {
    String(format: "(%.1f,%.1f %.1fx%.1f)", r.origin.x, r.origin.y, r.size.width, r.size.height)
}

func fmt(_ e: EdgeInsets) -> String {
    String(format: "t%.1f l%.1f b%.1f r%.1f", e.top, e.leading, e.bottom, e.trailing)
}

func fmt(_ e: UIEdgeInsets) -> String {
    String(format: "t%.1f l%.1f b%.1f r%.1f", e.top, e.left, e.bottom, e.right)
}

func dumpUIKit(_ tag: String) {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
        let screen = scene.screen
        log("[\(tag)] uikit.screen bounds=\(fmt(screen.bounds)) native=\(fmt(screen.nativeBounds)) scale=\(screen.scale) nativeScale=\(screen.nativeScale)")
        log("[\(tag)] uikit.scene role=\(scene.session.role.rawValue) coordSpace=\(fmt(scene.coordinateSpace.bounds)) orientation=\(scene.effectiveGeometry.interfaceOrientation.rawValue)")
        let t = scene.traitCollection
        log("[\(tag)] uikit.traits hSC=\(t.horizontalSizeClass.rawValue) vSC=\(t.verticalSizeClass.rawValue) idiom=\(t.userInterfaceIdiom.rawValue)")
        for window in scene.windows {
            log("[\(tag)] uikit.window frame=\(fmt(window.frame)) safe=\(fmt(window.safeAreaInsets))")
            let v: UIView = window
            for r in v.reservedRegions(kind: .division, options: [.includeInactive]) {
                log("[\(tag)] uikit.division frame=\(fmt(r.frame)) margins=\(fmt(r.margins)) active=\(r.isActive)")
            }
            for r in v.reservedRegions(kind: .occlusion, options: [.includeInactive]) {
                log("[\(tag)] uikit.occlusion frame=\(fmt(r.frame)) margins=\(fmt(r.margins)) active=\(r.isActive)")
            }
        }
    }
    log("[\(tag)] uikit.screens count=\(UIScreen.screens.count) " + UIScreen.screens.map { fmt($0.bounds) + "@\($0.scale)" }.joined(separator: " "))
}

struct ProbeView: View {
    @Environment(\.horizontalSizeClass) private var hSC
    @Environment(\.verticalSizeClass) private var vSC
    @State private var hingeText = "hinge: (no update yet)"
    @State private var lines: [String] = []

    var body: some View {
        GeometryReader { proxy in
            let division = proxy.reservedRegions(kind: .division, options: [.includeInactive])
            let occlusion = proxy.reservedRegions(kind: .occlusion, options: [.includeInactive])
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(Array(division.enumerated()), id: \.offset) { _, r in
                    Rectangle().fill(r.isActive ? Color.red.opacity(0.6) : Color.orange.opacity(0.3))
                        .frame(width: r.frame.width, height: r.frame.height)
                        .offset(x: r.frame.minX, y: r.frame.minY)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "size %.1f x %.1f", proxy.size.width, proxy.size.height))
                    Text("safe " + fmt(proxy.safeAreaInsets))
                    Text("hSC \(String(describing: hSC)) vSC \(String(describing: vSC))")
                    Text(hingeText)
                    ForEach(Array(division.enumerated()), id: \.offset) { _, r in
                        Text("div \(fmt(r.frame)) active=\(r.isActive)")
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.top, 80)
                .padding(.leading, 16)
            }
            .onAppear { report(proxy, division, occlusion, "appear") }
            .onChange(of: proxy.size) { _, _ in report(proxy, division, occlusion, "resize") }
            .onChange(of: division.map(\.frame).description + division.map(\.isActive).description) { _, _ in
                report(proxy, division, occlusion, "division-change")
            }
        }
        .ignoresSafeArea()
        .onHingeChange { _, ctx in
            if let h = ctx.hinge {
                hingeText = String(format: "hinge %.1f deg ", h.angle.degrees) + String(describing: h.status)
            } else {
                hingeText = "hinge: nil"
            }
            log("hinge " + hingeText)
        }
    }

    private func report(_ proxy: GeometryProxy, _ division: [ReservedRegion], _ occlusion: [ReservedRegion], _ tag: String) {
        log("[\(tag)] swiftui.size=\(proxy.size.width)x\(proxy.size.height) safe=\(fmt(proxy.safeAreaInsets)) hSC=\(String(describing: hSC)) vSC=\(String(describing: vSC))")
        for r in division { log("[\(tag)] swiftui.division frame=\(fmt(r.frame)) margins=\(fmt(r.margins)) active=\(r.isActive)") }
        for r in occlusion { log("[\(tag)] swiftui.occlusion frame=\(fmt(r.frame)) margins=\(fmt(r.margins)) active=\(r.isActive)") }
        dumpUIKit(tag)
    }
}

// Apple's own adaptive two-pane layout, measured. Mode from PROBE_MODE.
struct PaneReporter: View {
    let name: String
    let color: Color
    var body: some View {
        GeometryReader { p in
            let f = p.frame(in: .global)
            color.opacity(0.55)
                .overlay(Text(name + "\n" + fmt(f)).font(.system(size: 14, design: .monospaced)).foregroundStyle(.white))
                .onAppear { log("[pane] \(name) frame=\(fmt(f))") }
                .onChange(of: f) { _, n in log("[pane] \(name) frame=\(fmt(n))") }
        }
    }
}

struct ArrangementProbe: View {
    let overlay: Bool
    var body: some View {
        GeometryReader { proxy in
            let plain = proxy.reservedRegions(kind: .division)
            let all = proxy.reservedRegions(kind: .division, options: [.includeInactive])
            Group {
                if overlay {
                    ArrangementView {
                        PaneReporter(name: "primary", color: .blue)
                    } secondary: {
                        PaneReporter(name: "secondary", color: .green)
                    }
                    .arrangementViewStyle(.overlay)
                } else {
                    ArrangementView {
                        PaneReporter(name: "primary", color: .blue)
                    } secondary: {
                        PaneReporter(name: "secondary", color: .green)
                    }
                    .arrangementViewStyle(.split)
                }
            }
            .onChange(of: all.map(\.isActive).description + proxy.size.debugDescription) { _, _ in
                log("[arr] size=\(proxy.size) plainQuery=\(plain.map { fmt($0.frame) + " active=\($0.isActive)" }) includeInactive=\(all.map { fmt($0.frame) + " active=\($0.isActive)" })")
            }
        }
        .onHingeChange { _, ctx in log("[arr] hinge " + (ctx.hinge.map { String(format: "%.1f ", $0.angle.degrees) + String(describing: $0.status) } ?? "nil")) }
    }
}

@main
struct DuoProbeApp: App {
    let mode = CommandLine.arguments.dropFirst().first ?? "default"
    var body: some Scene {
        WindowGroup {
            switch mode {
            case "split": ArrangementProbe(overlay: false)
            case "overlay": ArrangementProbe(overlay: true)
            default: ProbeView()
            }
        }
    }
}
