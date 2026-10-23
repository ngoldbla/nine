// CloudEntitlementTests — the reader that decides whether a binary may build a
// `CKContainer` on iOS, tvOS and visionOS, where `SecTask` is not public.
// Synthetic SuperBlobs, because no binary this test runs as is signed the way
// an app is.
import Testing
import Foundation
@testable import NineShared

@Suite("CloudEntitlement")
struct CloudEntitlementTests {

    private static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func be(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
    }

    /// A SuperBlob holding a code directory stand-in, then the entitlements.
    private func superBlob(entitlements: Data) -> Data {
        let directory: [UInt8] = be(0xfade_0c02) + be(12) + be(0)
        let ents: [UInt8] = be(0xfade_7171) + be(UInt32(8 + entitlements.count)) + Array(entitlements)
        let header = 12 + 2 * 8
        let body = directory + ents
        return Data(be(0xfade_0cc0) + be(UInt32(header + body.count)) + be(2)
            + be(0) + be(UInt32(header))
            + be(5) + be(UInt32(header + directory.count))
            + body)
    }

    @Test func theCheckedInEntitlementsGrantCloudKit() throws {
        for file in ["Nine-visionOS.entitlements", "Nine-tvOS.entitlements"] {
            let data = try Data(contentsOf: Self.nineRoot.appendingPathComponent(file))
            #expect(CloudEntitlement.grantsCloudKit(plist: data), "\(file)")
        }
    }

    @Test func anEntitlementsListWithoutICloudGrantsNothing() throws {
        #expect(!CloudEntitlement.grantsCloudKit(plist: try plist(["com.apple.developer.game-center": true])))
        #expect(!CloudEntitlement.grantsCloudKit(plist: Data()))
        #expect(!CloudEntitlement.grantsCloudKit(plist: Data("garbage".utf8)))
    }

    @Test func eitherKeyIsEnough() throws {
        #expect(CloudEntitlement.grantsCloudKit(plist: try plist(
            ["com.apple.developer.icloud-container-identifiers": ["iCloud.com.couchsuite.nine"]])))
        #expect(CloudEntitlement.grantsCloudKit(plist: try plist(
            ["com.apple.developer.icloud-services": ["CloudKit"]])))
    }

    @Test func theEntitlementsBlobIsFoundInASignature() throws {
        let ents = try plist(["com.apple.developer.icloud-services": ["CloudKit"]])
        let found = try #require(CloudEntitlement.entitlements(inSuperBlob: superBlob(entitlements: ents)))
        #expect(found == ents)
        #expect(CloudEntitlement.grantsCloudKit(plist: found))
    }

    @Test func aTruncatedOrForeignSignatureAnswersNil() throws {
        let whole = superBlob(entitlements: try plist(["a": 1]))
        #expect(CloudEntitlement.entitlements(inSuperBlob: whole.prefix(whole.count - 4)) == nil)
        #expect(CloudEntitlement.entitlements(inSuperBlob: whole.subdata(in: 4..<whole.count)) == nil)
        #expect(CloudEntitlement.entitlements(inSuperBlob: Data()) == nil)
        // A slice whose indices do not start at zero reads the same.
        let padded = Data([0, 0, 0]) + whole
        #expect(CloudEntitlement.entitlements(inSuperBlob: padded.dropFirst(3)) != nil)
    }

    /// The test runner is not an app with a container; whatever it is signed
    /// with, it must not claim CloudKit (and reading it must not crash).
    @Test func theTestRunnerIsNotEntitledToAContainer() {
        #expect(!CloudEntitlement.thisProcessGrantsCloudKit)
    }
}
