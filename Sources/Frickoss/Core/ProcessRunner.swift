import Foundation

struct ProcessResult {
    let status: Int32
    let output: String
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum Shell {
    /// Runs a short-lived process and returns its combined output.
    static func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                p.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                continuation.resume(returning: ProcessResult(status: p.terminationStatus,
                                                             output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

/// Runs freaccmd for a conversion and hands its output over as it arrives, on the main queue.
final class ProcessRunner {
    private let process = Process()
    private let queue = DispatchQueue(label: "frickoss.process-runner")

    /// Raw output text, in order — always called on the main queue.
    var onOutput: ((String) -> Void)?
    /// Exit status — always called on the main queue, after all output has been delivered.
    var onExit: ((Int32) -> Void)?

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
    }

    func start() throws {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.deliver(data)
        }
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                let code = proc.terminationStatus
                let text = String(decoding: rest, as: UTF8.self)
                DispatchQueue.main.async {
                    if !text.isEmpty { self.onOutput?(text) }
                    self.onExit?(code)
                }
            }
        }
        try process.run()
    }

    private func deliver(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }

    var isRunning: Bool { process.isRunning }

    /// Asks freaccmd to stop (SIGINT, then SIGTERM, then SIGKILL).
    func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.interrupt()
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let p = self?.process, p.isRunning else { return }
            p.terminate()
            self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                if let p = self?.process, p.isRunning { kill(pid, SIGKILL) }
            }
        }
    }
}
