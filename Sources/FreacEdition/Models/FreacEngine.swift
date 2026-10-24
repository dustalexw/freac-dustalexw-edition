import Foundation
import AppKit

/// Finds fre:ac's command-line converter and learns what it can do: version, encoders and their options, CD drives.
@MainActor
final class FreacEngine: ObservableObject {
    static let freacBundleID = "org.freac.freac"
    static let customPathKey = "freaccmdPath"

    @Published private(set) var cmdPath: String?
    @Published private(set) var version: String?
    @Published private(set) var encoders: [EncoderInfo] = []
    @Published private(set) var drives: [CDDrive] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isScanningDrives = false
    @Published var problem: String?

    var appURL: URL? {
        guard let cmdPath else { return nil }
        // …/freac.app/Contents/MacOS/freaccmd → …/freac.app
        let url = URL(fileURLWithPath: cmdPath)
        let app = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    func encoder(_ id: String) -> EncoderInfo? { encoders.first { $0.id == id } }

    static func locate() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: customPathKey), !custom.isEmpty { candidates.append(custom) }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: freacBundleID) {
            candidates.append(app.appendingPathComponent("Contents/MacOS/freaccmd").path)
        }
        candidates += ["/Applications/freac.app/Contents/MacOS/freaccmd",
                       (NSHomeDirectory() as NSString).appendingPathComponent("Applications/freac.app/Contents/MacOS/freaccmd"),
                       "/opt/homebrew/bin/freaccmd", "/usr/local/bin/freaccmd"]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Accepts either freac.app or the freaccmd executable itself.
    func useCustom(_ url: URL) {
        var path = url.path
        if url.pathExtension == "app" { path = url.appendingPathComponent("Contents/MacOS/freaccmd").path }
        UserDefaults.standard.set(path, forKey: Self.customPathKey)
        Task { await refresh() }
    }

    func resetCustom() {
        UserDefaults.standard.removeObject(forKey: Self.customPathKey)
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        problem = nil
        guard let path = Self.locate() else {
            cmdPath = nil; version = nil; encoders = []
            return
        }
        cmdPath = path
        do {
            let help = try await Shell.run(path, [])
            version = FreacHelp.version(fromHelp: help.output)
            let ids = FreacHelp.encoderIDs(fromHelp: help.output)
            guard !ids.isEmpty else {
                problem = "fre:ac answered, but didn't list any encoders."
                encoders = []
                return
            }
            let loaded = await withTaskGroup(of: EncoderInfo?.self) { group -> [EncoderInfo] in
                for id in ids {
                    group.addTask {
                        guard let r = try? await Shell.run(path, ["-h", id]) else { return nil }
                        return FreacHelp.encoder(id: id, fromHelp: r.output)
                    }
                }
                var all: [EncoderInfo] = []
                for await e in group { if let e { all.append(e) } }
                return all
            }
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            encoders = loaded.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } catch {
            problem = "Couldn't start fre:ac's converter: \(error.localizedDescription)"
            encoders = []
        }
    }

    func scanDrives() async {
        guard let cmdPath else { return }
        isScanningDrives = true
        defer { isScanningDrives = false }
        if let r = try? await Shell.run(cmdPath, ["--list-drives"]) {
            drives = FreacHelp.drives(fromList: r.output)
        } else {
            drives = []
        }
    }
}

/// Saves the window's choices between launches.
@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "conversionSettings"

    @Published var settings: ConversionSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(ConversionSettings.self, from: data) {
            settings = s
        } else {
            settings = ConversionSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// The value shown for an encoder option: what was chosen, or fre:ac's default.
    func value(for p: EncoderParameter, encoder: String) -> String {
        if let v = settings.encoderValues[encoder]?[p.spec] { return v }
        switch p.kind {
        case .toggle: return "off"
        case .choice: return p.defaultValue ?? ""  // "" = leave it to fre:ac
        case .range(let lo, _, _, _): return p.defaultValue ?? Self.format(lo)
        }
    }

    func setValue(_ v: String, for p: EncoderParameter, encoder: String) {
        var values = settings.encoderValues[encoder] ?? [:]
        values[p.spec] = v
        settings.encoderValues[encoder] = values
    }

    func resetEncoder(_ encoder: String) { settings.encoderValues[encoder] = nil }

    func isCustomized(_ encoder: String) -> Bool { !(settings.encoderValues[encoder] ?? [:]).isEmpty }

    static func format(_ d: Double) -> String {
        d.rounded() == d ? String(Int(d)) : String(d)
    }
}
