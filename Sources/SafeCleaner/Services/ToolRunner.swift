import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

/// The one place the app launches a process. Only a catalogue command can reach it, the
/// executable is validated first, and the process gets a minimal environment, no stdin,
/// and a hard timeout. Cancelling the surrounding task terminates the process.
struct ToolRunner: ToolRunning {
    static let timeout: TimeInterval = 120

    func run(_ command: ToolCommand) async throws -> Data {
        try command.validateExecutable()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        let name = ([URL(fileURLWithPath: command.executable).lastPathComponent] + command.arguments.prefix(2)).joined(separator: " ")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try process.run() } catch {
                        continuation.resume(throwing: ToolCommand.ToolError.failed(name, -1, error.localizedDescription)); return
                    }
                    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: deadline)
                    // Drain both pipes concurrently so neither can fill and block the tool.
                    var errorText = Data()
                    let drained = DispatchGroup()
                    drained.enter()
                    DispatchQueue.global().async { errorText = errors.fileHandleForReading.readDataToEndOfFile(); drained.leave() }
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    drained.wait()
                    process.waitUntilExit()
                    deadline.cancel()
                    guard process.terminationStatus == 0 else {
                        let text = String(decoding: errorText.suffix(400), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ToolCommand.ToolError.failed(name, process.terminationStatus,
                            text.isEmpty ? "No details were reported." : text))
                        return
                    }
                    continuation.resume(returning: data)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
