import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

/// Lists what the current user's processes hold open, through libproc: every file
/// descriptor that is a file, each working directory and each executable. Read-only; nothing
/// here can signal or affect a process. Other users' processes (root daemons) cannot be
/// inspected without root and are absent, which is why the result is a guard, not a proof.
struct LibprocOpenFileService: OpenFileChecking {
    func index() async -> OpenFileIndex {
        await Task.detached(priority: .userInitiated) { Self.build() }.value
    }

    static func build() -> OpenFileIndex {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return OpenFileIndex(uses: []) }
        // Headroom for processes that start between the two calls. Both calls return a count
        // of pids (measured: 1,324 against 1,326 in ps), not a byte length; unused slots stay 0.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let listed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard listed > 0 else { return OpenFileIndex(uses: []) }
        var uses: [ProcessUse] = []
        for pid in pids.prefix(min(Int(listed), pids.count)) where pid > 0 {
            let name = processName(pid)
            var executable = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if proc_pidpath(pid, &executable, UInt32(executable.count)) > 0 {
                uses.append(ProcessUse(pid: pid, name: name, path: string(in: executable)))
            }
            var vnode = proc_vnodepathinfo()
            let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, vnodeSize) == vnodeSize {
                let cwd = string(of: &vnode.pvi_cdir.vip_path)
                if !cwd.isEmpty { uses.append(ProcessUse(pid: pid, name: name, path: cwd)) }
            }
            uses += openDescriptors(of: pid, name: name)
        }
        return OpenFileIndex(uses: uses)
    }

    private static func openDescriptors(of pid: pid_t, name: String) -> [ProcessUse] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
        guard used > 0 else { return [] }
        var result: [ProcessUse] = []
        let want = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        for descriptor in descriptors.prefix(Int(used) / stride) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, want) == want else { continue }
            let path = string(of: &info.pvip.vip_path)
            if !path.isEmpty { result.append(ProcessUse(pid: pid, name: name, path: path)) }
        }
        return result
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return string(in: buffer)
    }

    /// A NUL-terminated C string held in a fixed-size tuple field, read up to the first NUL
    /// and never past the storage, whatever the kernel wrote.
    private static func string<T>(of tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
    /// The same for a Swift array buffer. `withUnsafeBytes(of:)` on an array would read the
    /// array's own header, not its elements.
    private static func string(in buffer: [CChar]) -> String {
        buffer.withUnsafeBytes { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
