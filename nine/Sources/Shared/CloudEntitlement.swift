// CloudEntitlement.swift — does *this binary* carry the CloudKit entitlement?
//
// `CKContainer(identifier:)` traps — not throws, traps — on a binary that asks
// for a container without the entitlement. A signed-in iCloud account is not
// the question: a `CODE_SIGNING_ALLOWED=NO` simulator build has no entitlements
// at all, and a simulator with an account signed in (the CloudKit sync rig does
// exactly that) passes `ubiquityIdentityToken` and then traps on the first
// `LibraryCloudStore()`.
//
// macOS asks `SecTask` (see `AppModel.mayBuildCloudContainer`). `SecTask` is
// not in the public iOS, tvOS or visionOS SDKs, so on those this reads the
// running executable's own Mach-O through the public dyld API, from the two
// places a build puts its entitlements:
//
//   * a simulator build links them into a `__TEXT,__entitlements` section
//     (Xcode's "simulated" entitlements — the simulator honours those, not the
//     ad-hoc signature);
//   * a device build carries them in its code signature, the XML entitlements
//     blob (`0xfade7171`) inside the embedded SuperBlob (`0xfade0cc0`) that
//     `LC_CODE_SIGNATURE` points at in `__LINKEDIT`.
//
// Neither present means no entitlements, which is the honest answer for an
// unsigned build. The parsing is pure and tested on synthetic blobs
// (`CloudEntitlementTests`); only `thisProcessGrantsCloudKit` touches memory.
import Foundation
#if canImport(MachO)
import MachO
#endif

public enum CloudEntitlement {

    /// Either key proves CloudKit; asking for both would fail a future
    /// entitlements file that drops one — `mayBuildCloudContainer`'s rule.
    static let keys = ["com.apple.developer.icloud-services",
                       "com.apple.developer.icloud-container-identifiers"]

    /// Whether an entitlements property list grants CloudKit.
    public static func grantsCloudKit(plist: Data) -> Bool {
        guard let dict = try? PropertyListSerialization.propertyList(
            from: plist, options: [], format: nil) as? [String: Any] else { return false }
        return keys.contains { dict[$0] != nil }
    }

    static let superBlobMagic: UInt32 = 0xfade_0cc0
    static let entitlementsMagic: UInt32 = 0xfade_7171

    /// The XML entitlements inside a code-signature SuperBlob, or nil.
    /// Big-endian throughout: `magic, length, count`, then `count` index
    /// entries of `(type, offset)`; each blob starts `magic, length`.
    /// Every read is bounds-checked against the SuperBlob's own length, so a
    /// truncated or hostile signature answers nil rather than reading past it.
    public static func entitlements(inSuperBlob blob: Data) -> Data? {
        func word(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= blob.count else { return nil }
            let i = blob.startIndex + at
            return blob[i..<i + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        guard word(0) == superBlobMagic, let length = word(4), let count = word(8),
              Int(length) <= blob.count, count < 64 else { return nil }
        for slot in 0..<Int(count) {
            guard let offset = word(12 + slot * 8 + 4).map(Int.init) else { return nil }
            guard word(offset) == entitlementsMagic, let size = word(offset + 4).map(Int.init),
                  size >= 8, offset + size <= Int(length) else { continue }
            let start = blob.startIndex + offset + 8
            return blob[start..<blob.startIndex + offset + size]
        }
        return nil
    }

    /// Whether the running executable is entitled to build a `CKContainer`.
    /// Read once: a binary's entitlements cannot change under it.
    public static let thisProcessGrantsCloudKit: Bool = {
        #if canImport(MachO)
        return executableEntitlements().contains(where: grantsCloudKit(plist:))
        #else
        return false
        #endif
    }()

    #if canImport(MachO)
    /// Every entitlements plist the main executable carries: the simulator
    /// section first, then the code signature's.
    static func executableEntitlements() -> [Data] {
        guard let (header, slide) = mainExecutable() else { return [] }
        var found: [Data] = []
        var size: UInt = 0
        if let bytes = getsectiondata(header, "__TEXT", "__entitlements", &size), size > 0 {
            found.append(Data(bytes: bytes, count: Int(size)))
        }
        if let signature = codeSignature(header, slide: slide),
           let plist = entitlements(inSuperBlob: signature) {
            found.append(plist)
        }
        return found
    }

    private static func mainExecutable() -> (UnsafePointer<mach_header_64>, Int)? {
        for i in 0..<_dyld_image_count() {
            guard let raw = _dyld_get_image_header(i), raw.pointee.filetype == MH_EXECUTE
            else { continue }
            let header = UnsafeRawPointer(raw).assumingMemoryBound(to: mach_header_64.self)
            return (header, _dyld_get_image_vmaddr_slide(i))
        }
        return nil
    }

    /// The SuperBlob `LC_CODE_SIGNATURE` names, read from mapped `__LINKEDIT`.
    private static func codeSignature(_ header: UnsafePointer<mach_header_64>, slide: Int) -> Data? {
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        var linkedit: segment_command_64?
        var signature: linkedit_data_command?
        for _ in 0..<header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == LC_SEGMENT_64 {
                let segment = command.load(as: segment_command_64.self)
                let name = withUnsafeBytes(of: segment.segname) {
                    String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
                }
                if name == "__LINKEDIT" { linkedit = segment }
            } else if load.cmd == LC_CODE_SIGNATURE {
                signature = command.load(as: linkedit_data_command.self)
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        guard let linkedit, let signature,
              UInt64(signature.dataoff) >= linkedit.fileoff,
              UInt64(signature.dataoff) + UInt64(signature.datasize)
                <= linkedit.fileoff + linkedit.filesize else { return nil }
        let address = Int(linkedit.vmaddr) + slide
            + Int(UInt64(signature.dataoff) - linkedit.fileoff)
        guard let base = UnsafeRawPointer(bitPattern: address) else { return nil }
        return Data(bytes: base, count: Int(signature.datasize))
    }
    #endif
}
