// VisionSealTests.swift — what keeps NineVision from trapping at launch.
//
// `LibraryCloudStore` builds a `CKContainer(identifier:)`, which traps on any
// binary without the CloudKit entitlement. NineVision compiles that store in
// directly (play anywhere), so two facts now have to stay true together, and
// neither shows up as a red build when it breaks:
//
//   1. the target that compiles the store carries a checked-in entitlements
//      file granting CloudKit — and `.gitignore` does not swallow it, which is
//      the trap CLAUDE.md records as having fired before;
//   2. `AppModel` still never reaches the target, so nothing else in it builds
//      a container on a path this file has not looked at.
//
// Plus PRD-28's rule for demo transports, re-aimed at the headset's ghost.
import XCTest

final class VisionSealTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: Self.nineRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The NineVision target's block of project.yml, up to the next target.
    private func visionTarget() throws -> String {
        let yml = try text("project.yml")
        let start = try XCTUnwrap(yml.range(of: "\n  NineVision:\n"), "NineVision target missing")
        let rest = yml[start.upperBound...]
        let end = rest.range(of: #"\n  [A-Za-z]+:\n"#, options: .regularExpression)?.lowerBound
            ?? rest.endIndex
        return String(rest[..<end])
    }

    private func sources(_ target: String) -> [String] {
        target.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- Sources/") }
            .map { String($0.dropFirst(2)) }
    }

    func testAppModelNeverReachesTheVisionTarget() throws {
        let listed = sources(try visionTarget())
        XCTAssertFalse(listed.contains("Sources/App"),
                       "NineVision lists the whole App tree, AppModel included")
        XCTAssertFalse(listed.contains { $0.hasSuffix("AppModel.swift") })
    }

    func testTheTargetThatBuildsAContainerIsEntitledToOne() throws {
        let target = try visionTarget()
        guard sources(target).contains(where: { $0.hasPrefix("Sources/App/CloudSync") }) else {
            return   // no store, no container, nothing to entitle
        }
        let line = try XCTUnwrap(
            target.split(separator: "\n").first { $0.contains("CODE_SIGN_ENTITLEMENTS") },
            "NineVision compiles LibraryCloudStore but names no entitlements file")
        let file = try XCTUnwrap(line.split(separator: ":").last)
            .trimmingCharacters(in: .whitespaces)
        let plist = try text(file)
        XCTAssertTrue(plist.contains("<string>CloudKit</string>"), "\(file) grants no CloudKit")
        XCTAssertTrue(plist.contains("iCloud.com.couchsuite.nine"), "\(file) names no container")
        XCTAssertTrue(plist.contains("aps-environment"),
                      "\(file): ASC rejects icloud-services without aps-environment (90575)")

        let ignore = try String(
            contentsOf: Self.nineRoot.deletingLastPathComponent().appendingPathComponent(".gitignore"),
            encoding: .utf8)
        XCTAssertTrue(ignore.contains("!nine/\(file)"),
                      "`*/*.entitlements` swallows \(file) without its negation")
    }

    /// An entitlements file is the half of the trap a signed build covers. An
    /// unsigned build (`CODE_SIGNING_ALLOWED=NO`, every simulator lane in CI)
    /// has no entitlements at all, so every place that builds the store must
    /// first ask the binary itself — `CloudEntitlement` off macOS, `SecTask` on
    /// it, both behind `mayBuildCloudContainer` in `AppModel`.
    func testEveryCloudStoreIsBuiltBehindTheBinaryEntitlementGuard() throws {
        let root = Self.nineRoot.appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var builders = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (n, line) in lines.enumerated() where line.contains("LibraryCloudStore()")
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                builders += 1
                let before = lines[max(0, n - 6)..<n].joined(separator: "\n")
                XCTAssertTrue(
                    before.contains("CloudEntitlement.thisProcessGrantsCloudKit")
                        || before.contains("mayBuildCloudContainer"),
                    "\(file.lastPathComponent):\(n + 1) builds a LibraryCloudStore without asking the binary first")
            }
        }
        XCTAssertGreaterThanOrEqual(builders, 2, "expected AppModel's and VisionModel's stores")
        let appModel = try text("Sources/App/AppModel.swift")
        XCTAssertTrue(appModel.contains("return CloudEntitlement.thisProcessGrantsCloudKit"),
                      "AppModel off macOS must ask the binary, not return true")
    }

    /// The ghost is a launch argument; in Release it would be one anybody can
    /// pass. Every mention sits inside `#if DEBUG`.
    func testTheGhostTransportCannotBeReachedInRelease() throws {
        for path in ["Sources/Vision/VisionCoSolve.swift", "Sources/Vision/VisionModel.swift"] {
            var depth = 0
            var debugDepth: Int?
            for raw in try text(path).split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                if line.hasPrefix("#if") {
                    depth += 1
                    if line.contains("DEBUG"), debugDepth == nil { debugDepth = depth }
                } else if line.hasPrefix("#endif") {
                    if debugDepth == depth { debugDepth = nil }
                    depth -= 1
                }
                for name in ["VisionGhostTransport", "vision-coplay-demo", "startGhostCoSolve",
                             "vision-theme", "appearanceIsStaged", "vision-offer-demo", "stageOffer",
                             "vision-chooser-demo", "stageChooser"]
                where line.contains(name) {
                    XCTAssertNotNil(debugDepth, "\(path): \(name) is outside #if DEBUG")
                }
            }
        }
    }
}
