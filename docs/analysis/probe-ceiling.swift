import Foundation
// READ-ONLY. Compares ViggoClean's CURRENT all-or-nothing guard (strict)
// against a per-entry SKIP variant (lenient) on the real candidate set.
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
func fmtB(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

struct R { var strictOK = false; var strictBytes: Int64 = 0
           var lenientBytes: Int64 = 0; var movedBytes: Int64 = 0
           var skipped = 0; var firstRefusal = "" }

func analyze(_ url: URL) -> R? {
    guard let base = try? fm.attributesOfItem(atPath: url.path) else { return nil }
    let device = base[.systemNumber] as? NSNumber
    var r = R(); var refused = false
    func visit(_ e: URL, _ depth: Int) {
        guard let a = try? fm.attributesOfItem(atPath: e.path) else { return }
        let t = a[.type] as? FileAttributeType
        let v = try? e.resourceValues(forKeys: [.fileAllocatedSizeKey, .isPackageKey])
        let size = Int64(v?.fileAllocatedSize ?? 0)
        let links = (a[.referenceCount] as? NSNumber)?.intValue ?? 1
        var bad: String? = nil
        if t != .typeDirectory && t != .typeRegular { bad = "link/special" }
        else if a[.systemNumber] as? NSNumber != device { bad = "cross-volume" }
        else if v?.isPackage == true { bad = "package" }
        else if t == .typeRegular && links > 1 { bad = "hard link" }
        if t == .typeRegular { r.movedBytes += size }   // trashItem moves it regardless
        if let bad {
            if !refused { refused = true
                r.firstRefusal = "\(bad): \(e.path.replacingOccurrences(of: home.path, with: "~"))" }
            r.skipped += 1
            if v?.isPackage == true, t == .typeDirectory {      // still moved, just not descended
                if let sub = try? fm.subpathsOfDirectory(atPath: e.path) {
                    for s in sub { let f = e.appendingPathComponent(s)
                        if let sa = try? fm.attributesOfItem(atPath: f.path),
                           sa[.type] as? FileAttributeType == .typeRegular {
                            r.movedBytes += Int64((try? f.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize ?? 0) } } }
            }
            return                                      // LENIENT: skip, do not abort
        }
        if t == .typeRegular { r.lenientBytes += size; if !refused { r.strictBytes += size } }
        if t == .typeDirectory, let kids = try? fm.contentsOfDirectory(at: e, includingPropertiesForKeys: nil) {
            for k in kids.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { visit(k, depth+1) }
        }
    }
    visit(url, 0)
    r.strictOK = !refused
    if !r.strictOK { r.strictBytes = 0 }
    return r
}

var rows: [(String, R)] = []
let rules = ["Library/Developer/Xcode/DerivedData","Library/Caches/org.swift.swiftpm",
             ".npm/_cacache",".gradle/caches/build-cache-1"]
for p in rules { if let r = analyze(home.appendingPathComponent(p)) { rows.append((p, r)) } }

// Third-party ~/Library/Caches children, as Scanner.swift:76-92 selects them
let cacheRoot = home.appendingPathComponent("Library/Caches")
let reserved = ["Homebrew","org.swift.swiftpm","CocoaPods","pip"]
if let kids = try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) {
    for u in kids.sorted(by: { $0.path < $1.path }) {
        let n = u.lastPathComponent
        guard !n.hasPrefix("com.apple."), !n.hasPrefix("."), !reserved.contains(n) else { continue }
        if let r = analyze(u), r.lenientBytes > 50_000_000 { rows.append(("Library/Caches/" + n, r)) }
    }
}

func pad(_ s: String, _ n: Int) -> String {
    let t = String(s.prefix(n)); return t + String(repeating: " ", count: max(0, n - t.count)) }
func lpad(_ s: String, _ n: Int) -> String {
    let t = String(s.prefix(n)); return String(repeating: " ", count: max(0, n - t.count)) + t }

print(pad("CANDIDATE", 44) + lpad("TODAY", 12) + lpad("IF FIXED", 12) + lpad("SKIPPED", 9))
print(String(repeating: "-", count: 77))
var today: Int64 = 0, fixed: Int64 = 0, moved: Int64 = 0
for (p, r) in rows.sorted(by: { $0.1.lenientBytes > $1.1.lenientBytes }) {
    today += r.strictBytes; fixed += r.lenientBytes; moved += r.movedBytes
    print(pad(p, 44) + lpad(r.strictOK ? fmtB(r.strictBytes) : "REFUSED", 12)
        + lpad(fmtB(r.lenientBytes), 12) + lpad(String(r.skipped), 9))
}
print(String(repeating: "-", count: 77))
print(pad("TOTAL", 44) + lpad(fmtB(today), 12) + lpad(fmtB(fixed), 12))
print("")
print("Bytes actually MOVED to Trash if fixed: " + fmtB(moved))
print("Under-report gap (moved minus measured): " + fmtB(moved - fixed))
