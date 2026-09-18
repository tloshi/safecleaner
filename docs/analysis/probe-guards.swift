import Foundation
// Faithful replication of FileSafety.record() guards (Sources/ViggoCleanCore/FileSafety.swift:41-71)
// READ-ONLY. Reports the first refusal per candidate tree, exactly as snapshot() would.
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

enum Refusal: Error { case reason(String, String) }

func probe(_ url: URL) -> (String, Int64, Int) {
    guard let base = try? fm.attributesOfItem(atPath: url.path) else { return ("MISSING", 0, 0) }
    let device = base[.systemNumber] as? NSNumber
    var bytes: Int64 = 0, count = 0
    // Mirrors FileSafety.record. Keep the two in step: this probe is only useful while
    // it is a faithful replica. Symlinks are counted and never followed; packages are
    // ordinary directories; only cross-volume, special files and hard links refuse.
    @discardableResult
    func record(_ e: URL) throws -> FileAttributeType? {
        let a = try fm.attributesOfItem(atPath: e.path)
        let t = a[.type] as? FileAttributeType
        if t == .typeSymbolicLink {
            bytes += (a[.size] as? NSNumber)?.int64Value ?? 0; count += 1; return t
        }
        guard t == .typeDirectory || t == .typeRegular else {
            throw Refusal.reason("special file", e.path) }
        guard a[.systemNumber] as? NSNumber == device else {
            throw Refusal.reason("cross-volume", e.path) }
        if t == .typeRegular, (a[.referenceCount] as? NSNumber)?.intValue ?? 1 > 1 {
            throw Refusal.reason("hard link", e.path) }
        if t == .typeRegular {
            let v = try e.resourceValues(forKeys: [.fileAllocatedSizeKey])
            bytes += Int64(v.fileAllocatedSize ?? 0); count += 1
        }
        return t
    }
    func walk(_ e: URL) throws {
        guard try record(e) == .typeDirectory else { return }
        for c in (try fm.contentsOfDirectory(at: e, includingPropertiesForKeys: nil))
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { try walk(c) }
    }
    do { try walk(url); return ("ACCEPTED", bytes, count) }
    catch let Refusal.reason(why, where_) {
        return ("REFUSED (\(why)): \(where_.replacingOccurrences(of: home.path, with: "~"))", bytes, count) }
    catch { return ("ERROR: \(error.localizedDescription)", bytes, count) }
}

let rules = ["Library/Developer/Xcode/DerivedData","Library/Caches/org.swift.swiftpm",
             ".npm/_cacache",".gradle/caches/build-cache-1","Library/Caches/CocoaPods",
             "Library/Caches/Homebrew/downloads","Library/Caches/pip"]
print("=== The 7 developer rules (Scanner.swift:60-68) ===")
var accepted: Int64 = 0
for r in rules {
    let u = home.appendingPathComponent(r)
    let du = (try? fm.attributesOfItem(atPath: u.path)) != nil
        ? (ProcessInfo.processInfo.environment["SKIPDU"] != nil ? "" : "") : ""
    _ = du
    let (status, b, n) = probe(u)
    if status == "ACCEPTED" { accepted += b }
    print("  \(r)\n      -> \(status)\(status == "ACCEPTED" ? "  [\(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)), \(n) files]" : "")")
}
print("\nTOTAL RECLAIMABLE FROM DEVELOPER RULES: \(ByteCountFormatter.string(fromByteCount: accepted, countStyle: .file))")
