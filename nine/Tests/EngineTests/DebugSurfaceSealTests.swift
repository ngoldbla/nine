// The seal on PRD-37's photograph rig: `-NineDebugSurface` opens a sheet, a
// card or the drawer at launch, and a launch argument anybody can pass has no
// business in a shipping build. Enforced against source text, the shape
// `ParlorSealTests` uses for the loopback parlor.
import XCTest

final class DebugSurfaceSealTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    /// Blank out `//` and `/* */` comments, keeping every line.
    private func codeOnly(_ text: String) -> String {
        var out = ""
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var body = String(line)
            if inBlock {
                guard let end = body.range(of: "*/") else { out += "\n"; continue }
                body = String(body[end.upperBound...])
                inBlock = false
            }
            if let start = body.range(of: "/*") {
                let head = String(body[..<start.lowerBound])
                if let end = body.range(of: "*/", range: start.upperBound..<body.endIndex) {
                    body = head + String(body[end.upperBound...])
                } else {
                    body = head
                    inBlock = true
                }
            }
            if let slashes = body.range(of: "//") { body = String(body[..<slashes.lowerBound]) }
            out += body + "\n"
        }
        return out
    }

    /// Every Swift file under `Sources`, swept rather than listed: the rig's
    /// names are the argument here, not a file's responsibility, and a new
    /// call site in any file must be fenced too.
    private func sources() throws -> [(String, String)] {
        let root = Self.nineRoot.appendingPathComponent("Sources")
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var found: [(String, String)] = []
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found.append((url.path, try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    func testTheSurfaceRigCannotBeReachedInRelease() throws {
        let names = ["DebugSurface", "NineDebugSurface", "openDebugSurface"]
        var sightings = 0
        for (path, text) in try sources() {
            var depth = 0
            var debugDepth: Int?
            for line in codeOnly(text).split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") {
                    depth += 1
                    if trimmed.contains("DEBUG"), debugDepth == nil { debugDepth = depth }
                } else if trimmed.hasPrefix("#endif") {
                    if debugDepth == depth { debugDepth = nil }
                    depth -= 1
                }
                for name in names where line.contains(name) {
                    sightings += 1
                    XCTAssertNotNil(debugDepth,
                                    "\(path): \(name) is outside #if DEBUG — a launch "
                                        + "argument that opens surfaces must not ship")
                }
            }
        }
        // A seal that finds nothing proves nothing: the rig must exist for
        // the sweep to be checking it.
        XCTAssertGreaterThan(sightings, 3)
    }
}
