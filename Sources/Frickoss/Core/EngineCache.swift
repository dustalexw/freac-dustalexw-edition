import Foundation

/// What frickoss learned from a particular freaccmd: its version and every encoder's options.
///
/// Reading this takes one freaccmd run plus one per encoder, and because freaccmd lives inside
/// freac.app, macOS puts a fre:ac icon in the Dock for each run. Saving the answer means a normal
/// launch runs freaccmd zero times; it is only asked again when fre:ac itself changes.
struct EngineCache: Codable, Equatable {
    /// Bump when the parser or the saved shape changes, so old answers are re-read.
    static let currentFormat = 1

    var format: Int
    var fingerprint: Fingerprint
    var version: String?
    var encoders: [EncoderInfo]

    /// Identifies one installed copy of freaccmd. Any update to fre:ac replaces the program
    /// (and its bundle's Info.plist), which changes the size or modification date.
    struct Fingerprint: Codable, Equatable {
        var path: String
        var size: Int64
        var modified: Double
        var bundleInfoModified: Double?

        static func of(executable path: String, fileManager fm: FileManager = .default) -> Fingerprint? {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard let attrs = try? fm.attributesOfItem(atPath: resolved),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  let date = attrs[.modificationDate] as? Date else { return nil }
            // …/freac.app/Contents/MacOS/freaccmd → …/freac.app/Contents/Info.plist
            let plist = URL(fileURLWithPath: resolved).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Info.plist").path
            let plistDate = (try? fm.attributesOfItem(atPath: plist))?[.modificationDate] as? Date
            return Fingerprint(path: path, size: size, modified: date.timeIntervalSince1970,
                               bundleInfoModified: plistDate?.timeIntervalSince1970)
        }
    }

    /// The saved answer, if it was made by this version of frickoss for exactly this freaccmd.
    static func load(from url: URL, matching fingerprint: Fingerprint) -> EngineCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(EngineCache.self, from: data),
              cache.format == currentFormat, cache.fingerprint == fingerprint,
              !cache.encoders.isEmpty else { return nil }
        return cache
    }

    func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// ~/Library/Application Support/frickoss/engine.json
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("frickoss", isDirectory: true).appendingPathComponent("engine.json")
    }
}
