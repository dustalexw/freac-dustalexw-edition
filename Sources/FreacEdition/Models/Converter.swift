import Foundation
import AppKit

struct Job: Identifiable, Hashable {
    enum State: Hashable { case waiting, converting, done, failed }
    let id = UUID()
    let url: URL
    let size: Int64
    var state: State = .waiting

    var name: String { url.lastPathComponent }
    var folder: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
    var format: String { url.pathExtension.uppercased() }
}

struct LogLine: Identifiable {
    enum Kind { case info, started, done, warning, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// The job list and the conversion itself.
@MainActor
final class Converter: ObservableObject {
    static let audioExtensions: Set<String> = [
        "mp3", "mp2", "m4a", "m4b", "mp4", "aac", "alac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf",
        "ogg", "oga", "opus", "spx", "wma", "ape", "wv", "tta", "mpc", "ac3", "dts", "au", "snd", "shn", "ofr",
        "tak", "mka", "webm", "cue", "voc", "w64", "rf64", "mid", "midi", "dsf", "dff",
    ]

    @Published var jobs: [Job] = []
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var current: String?
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var status: (text: String, kind: LogLine.Kind)?
    @Published private(set) var lastOutput: String?

    private var runner: ProcessRunner?
    private var parser = ProgressParser()
    private var stopping = false

    var totalBytes: Int64 { jobs.reduce(0) { $0 + $1.size } }
    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }

    // MARK: Job list

    func add(_ urls: [URL]) {
        let fm = FileManager.default
        var found: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL {
                    if Self.audioExtensions.contains(f.pathExtension.lowercased()) { found.append(f) }
                }
            } else {
                found.append(url)
            }
        }
        let existing = Set(jobs.map(\.url.path))
        let fresh = found
            .filter { !existing.contains($0.path) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { url -> Job in
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                return Job(url: url, size: size)
            }
        jobs += fresh
    }

    func remove(_ ids: Set<Job.ID>) {
        guard !isRunning else { return }
        jobs.removeAll { ids.contains($0.id) }
    }

    func clear() {
        guard !isRunning else { return }
        jobs.removeAll()
        log.removeAll()
        status = nil
        completed = 0; total = 0
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.state == .done }
    }

    // MARK: Converting

    func start(executable: String, arguments: [String], source: ConversionSource, outputFolder: String, expected: Int) {
        guard !isRunning else { return }
        try? FileManager.default.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        log.removeAll()
        parser = ProgressParser()
        completed = 0
        total = expected
        current = nil
        stopping = false
        lastOutput = outputFolder
        if case .files = source {
            for i in jobs.indices { jobs[i].state = .waiting }
        }
        let r = ProcessRunner(executable: executable, arguments: arguments)
        r.onOutput = { [weak self] text in self?.consume(text) }
        r.onExit = { [weak self] code in self?.finish(code) }
        do {
            try r.start()
            runner = r
            isRunning = true
            status = (source == .audioCD ? "Ripping the CD…" : "Converting…", .info)
            log.append(LogLine(kind: .info, text: source == .audioCD ? "Reading the CD — fre:ac looks up track names when CDDB is on." :
                                    "Converting \(expected) file\(expected == 1 ? "" : "s")…"))
        } catch {
            status = ("Couldn't start fre:ac: \(error.localizedDescription)", .error)
        }
    }

    func stop() {
        guard isRunning else { return }
        stopping = true
        status = ("Stopping…", .warning)
        runner?.terminate()
    }

    private func consume(_ text: String) {
        for event in parser.feed(text) { handle(event) }
    }

    private func handle(_ event: ProgressParser.Event) {
        switch event {
        case .started(let file):
            current = file
            log.append(LogLine(kind: .started, text: file))
            if let i = jobIndex(for: file) { jobs[i].state = .converting }
        case .finished(let file):
            completed += 1
            if total < completed { total = completed }
            if let i = jobIndex(for: file) { jobs[i].state = .done }
            if let last = log.lastIndex(where: { $0.kind == .started && $0.text == file }) {
                log[last] = LogLine(kind: .done, text: file)
            } else {
                log.append(LogLine(kind: .done, text: file))
            }
        case .message(let m):
            // libcdio prints this at every start when no disc is in a drive; it isn't about the conversion.
            if m.hasPrefix("++ WARN: cdio") && m.contains("No CD/DVD/BD media") { return }
            let lower = m.lowercased()
            let kind: LogLine.Kind = lower.hasPrefix("error") || lower.contains("could not") || lower.contains("not found") || lower.contains("not supported")
                ? .error : (lower.hasPrefix("warning") ? .warning : .info)
            log.append(LogLine(kind: kind, text: m))
        }
    }

    /// freaccmd prints the file name it was given, so match on the full path first, then the name.
    private func jobIndex(for file: String) -> Int? {
        if let i = jobs.firstIndex(where: { $0.url.path == file }) { return i }
        let name = (file as NSString).lastPathComponent
        return jobs.firstIndex(where: { $0.name == name && $0.state != .done })
    }

    private func finish(_ code: Int32) {
        for event in parser.flush() { handle(event) }
        isRunning = false
        runner = nil
        current = nil
        for i in jobs.indices where jobs[i].state == .converting { jobs[i].state = .failed }
        if stopping {
            status = ("Stopped. \(completed) of \(total) finished.", .warning)
        } else if code != 0 || parser.aborted {
            status = ("fre:ac stopped with an error — see the log.", .error)
        } else if completed == 0 {
            status = ("Nothing was converted — see the log.", .warning)
        } else {
            status = ("Done  ·  \(completed) converted", .done)
            NSSound(named: "Glass")?.play()
        }
    }
}
