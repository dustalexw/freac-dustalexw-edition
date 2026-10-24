import Foundation

/// Everything the window lets you choose. Saved between launches.
struct ConversionSettings: Codable, Equatable {
    var encoderID = "lame"
    /// encoder id → option spec → value ("on"/"off" for switches)
    var encoderValues: [String: [String: String]] = [:]

    var outputFolder = (NSHomeDirectory() as NSString).appendingPathComponent("Music/freac")
    var pattern = "<artist>/<album>/<track> - <title>"

    var singleFile = false
    var singleFileName = "Combined"
    var cueSheet = false
    var playlist = false

    var superFast = false
    var threads = 0                 // 0 = let fre:ac decide

    var splitChapters = false
    var ignoreChapters = false
    var ignoreAlbumArt = false
    var coverFront = ""
    var coverBack = ""

    // Audio CD
    var drive = 0
    var tracks = "all"
    var cddb = true
    var eject = false

    static let patternPresets: [(label: String, pattern: String)] = [
        ("Artist / Album / 01 - Title", "<artist>/<album>/<track> - <title>"),
        ("Artist - Title", "<artist> - <title>"),
        ("01 - Title", "<track> - <title>"),
        ("Same name as the source", "<filename>"),
    ]

    static let patternTokens = ["<artist>", "<album>", "<title>", "<track>", "<disc>", "<year>",
                                "<genre>", "<albumartist>", "<composer>", "<filename>"]
}

enum ConversionSource: Equatable {
    case files([String])
    case audioCD
}

enum CommandBuilder {
    /// Values the user changed from an encoder's defaults, as freaccmd arguments.
    static func encoderArguments(_ encoder: EncoderInfo?, values: [String: String]) -> [String] {
        guard let encoder else { return [] }
        var args: [String] = []
        for p in encoder.parameters {
            guard let v = values[p.spec], !v.isEmpty else { continue }
            switch p.kind {
            case .toggle:
                if v == "on" { args += p.arguments(for: v) }
            default:
                if v != p.defaultValue { args += p.arguments(for: v) }
            }
        }
        return args
    }

    /// freaccmd [program options] -- [encoder options] [files]
    static func arguments(settings s: ConversionSettings, encoder: EncoderInfo?, source: ConversionSource) -> [String] {
        var args = ["-e", s.encoderID]

        if s.singleFile {
            args += ["-o", singleFilePath(s)]
        } else {
            args += ["-d", s.outputFolder]
            if !s.pattern.trimmingCharacters(in: .whitespaces).isEmpty { args += ["-p", s.pattern] }
        }

        if s.cueSheet { args.append("--cuesheet") }
        if s.playlist { args.append("--playlist") }
        if s.superFast {
            args.append("--superfast")
            if s.threads > 0 { args.append("--threads=\(s.threads)") }
        }
        if s.splitChapters { args.append("--split-chapters") }
        if s.ignoreChapters { args.append("--ignore-chapters") }
        if s.ignoreAlbumArt { args.append("--ignore-albumart") }
        if !s.coverFront.isEmpty { args.append("--add-cover=\(s.coverFront)") }
        if !s.coverBack.isEmpty { args.append("--add-cover-back=\(s.coverBack)") }

        if case .audioCD = source {
            args += ["-cd", String(s.drive)]
            let t = s.tracks.trimmingCharacters(in: .whitespaces)
            args += ["-t", t.isEmpty ? "all" : t]
            if s.cddb { args.append("--cddb") }
            if s.eject { args.append("--eject") }
        }

        let encoderArgs = encoderArguments(encoder, values: s.encoderValues[s.encoderID] ?? [:])
        args.append("--")
        args += encoderArgs

        if case .files(let files) = source { args += files }
        return args
    }

    /// File extensions of fre:ac's encoders, for naming a combined single file.
    static let extensions: [String: String] = [
        "lame": "mp3", "coreaudio": "m4a", "fdkaac": "m4a", "faac": "m4a", "voaacenc": "m4a", "exhale": "m4a",
        "flac": "flac", "opus": "opus", "vorbis": "ogg", "speex": "spx", "mac": "ape", "wavpack": "wv",
        "tta": "tta", "sndfile-wave": "wav", "sndfile-aiff": "aiff", "wave": "wav", "wma": "wma", "twinvq": "vqf",
        "bonk": "bonk", "bladeenc": "mp3", "alac": "m4a", "mpg123": "mp3",
    ]

    /// Output path in single-file mode: the chosen name in the output folder, with the encoder's extension added if missing.
    static func singleFilePath(_ s: ConversionSettings) -> String {
        var name = s.singleFileName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Combined" }
        if (name as NSString).pathExtension.isEmpty, let ext = extensions[s.encoderID] { name += "." + ext }
        return (s.outputFolder as NSString).appendingPathComponent(name)
    }

    /// A copy-pasteable command line for the preview bar.
    static func display(executable: String?, arguments: [String]) -> String {
        let exe = executable ?? "freaccmd"
        return ([exe] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:,+@%")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Validates a CD track list such as "all", "1-5,7,9".
    static func isValidTrackList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty || t == "all" { return true }
        return t.split(separator: ",", omittingEmptySubsequences: false).allSatisfy { part in
            let bits = part.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bits.count) else { return false }
            let nums = bits.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count == bits.count, nums.allSatisfy({ $0 > 0 }) else { return false }
            return nums.count == 1 || nums[0] <= nums[1]
        }
    }
}

/// What freaccmd says while converting: "Processing file: X..." then "done." or "aborted."
/// It writes "Processing file: X..." without a newline, so this works on the raw stream.
struct ProgressParser {
    private(set) var buffer = ""
    private(set) var started: [String] = []
    private(set) var finished = 0
    private(set) var aborted = false

    enum Event: Equatable {
        case started(String)
        case finished(String)
        case message(String)
    }

    /// Feeds new output; returns what happened, in order.
    mutating func feed(_ chunk: String) -> [Event] {
        buffer += chunk
        var events: [Event] = []
        let marker = "Processing file: "
        while true {
            if buffer.hasPrefix(marker) {
                guard let dots = buffer.range(of: "...") else { break }
                let file = String(buffer[buffer.index(buffer.startIndex, offsetBy: marker.count)..<dots.lowerBound])
                started.append(file)
                events.append(.started(file))
                buffer = String(buffer[dots.upperBound...])
                continue
            }
            if buffer.hasPrefix("done.\n") || buffer.hasPrefix("aborted.\n") {
                let ok = buffer.hasPrefix("done.")
                if !ok { aborted = true }
                if let last = started.last {
                    if ok { finished += 1 }
                    events.append(ok ? .finished(last) : .message("Stopped while converting \(last)."))
                }
                buffer = String(buffer[(buffer.firstIndex(of: "\n").map { buffer.index(after: $0) } ?? buffer.endIndex)...])
                continue
            }
            guard let nl = buffer.firstIndex(of: "\n") else { break } // wait for the rest of the line
            let line = String(buffer[..<nl]).trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[buffer.index(after: nl)...])
            if !line.isEmpty { events.append(.message(line)) }
        }
        return events
    }

    mutating func flush() -> [Event] {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? [] : [.message(rest)]
    }
}
