import Foundation

public struct CommandResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum CommandRunnerError: Error, CustomStringConvertible, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(seconds: TimeInterval)
    case failed(exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .executableNotFound(let path): return "Executable not found: \(path)"
        case .launchFailed(let message): return "Could not launch command: \(message)"
        case .timedOut(let seconds): return "Command timed out after \(Int(seconds))s"
        case .failed(let exitCode, let stderr): return "Command failed (\(exitCode)): \(stderr)"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}

/// Executes a command without shell interpolation.
///
/// stdout/stderr are captured in temporary files rather than `Pipe`. A child process can
/// otherwise block when a large JSON response fills the pipe buffer before the parent
/// starts reading it. Multica workspaces with many issues can legitimately produce such
/// responses, so file-backed capture is intentionally used here.
public struct ProcessCommandRunner: CommandRunning, Sendable {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval = 20) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw CommandRunnerError.executableNotFound(executable)
            }

            let fm = FileManager.default
            let captureDirectory = fm.temporaryDirectory.appendingPathComponent("multica-bridge-command-\(UUID().uuidString)", isDirectory: true)
            let stdoutURL = captureDirectory.appendingPathComponent("stdout")
            let stderrURL = captureDirectory.appendingPathComponent("stderr")
            try fm.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            _ = fm.createFile(atPath: stdoutURL.path, contents: nil)
            _ = fm.createFile(atPath: stderrURL.path, contents: nil)
            defer { try? fm.removeItem(at: captureDirectory) }

            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }

            do {
                try process.run()
            } catch {
                throw CommandRunnerError.launchFailed(String(describing: error))
            }

            let deadline = DispatchTime.now() + max(0.1, timeout)
            if semaphore.wait(timeout: deadline) == .timedOut {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + 2)
                if process.isRunning { process.interrupt() }
                throw CommandRunnerError.timedOut(seconds: timeout)
            }

            try stdoutHandle.synchronize()
            try stderrHandle.synchronize()
            let stdoutData = try Data(contentsOf: stdoutURL)
            let stderrData = try Data(contentsOf: stderrURL)
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let result = CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
            if result.exitCode != 0 {
                let diagnostic = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw CommandRunnerError.failed(exitCode: result.exitCode, stderr: diagnostic.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : diagnostic)
            }
            return result
        }.value
    }
}
