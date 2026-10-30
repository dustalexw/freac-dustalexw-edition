import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if !cond { failures += 1; print("FAIL (line \(line)): \(msg)") }
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
func fixture(_ name: String) -> String { try! String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }

// Version and encoder list
let general = fixture("general_help.txt")
check(FreacHelp.version(fromHelp: "objc[123]: Class X is implemented in both A and B.\n" + general) == "1.1.7", "version after a loader warning")
check(FreacHelp.version(fromHelp: general) == "1.1.7", "version: \(String(describing: FreacHelp.version(fromHelp: general)))")
let ids = FreacHelp.encoderIDs(fromHelp: general)
check(ids.count == 15 && ids.first == "coreaudio" && ids.last == "wma" && ids.contains("sndfile-aiff"), "ids: \(ids)")

// Encoder options
let lame = FreacHelp.encoder(id: "lame", fromHelp: fixture("lame_help.txt"))
check(lame.name == "LAME MP3 Encoder", "name: \(lame.name)")
check(lame.parameters.count == 5, "param count \(lame.parameters.count): \(lame.parameters.map(\.name))")
if lame.parameters.count == 5 {
    let p = lame.parameters
    check(p[0].kind == .toggle && p[0].spec == "--resample" && p[0].name == "Resample to 44.1 kHz", "toggle \(p[0])")
    if case .choice(let c) = p[1].kind {
        check(c.map(\.value) == ["auto", "s", "j", "m"] && c[2].label == "Joint Stereo", "choices \(c)")
    } else { check(false, "stereo mode kind \(p[1].kind)") }
    check(p[1].defaultValue == "auto" && p[1].name == "Stereo mode", "stereo default \(String(describing: p[1].defaultValue))")
    if case .range(let lo, let hi, let ll, let hl) = p[2].kind {
        check(lo == 8 && hi == 320 && ll == "8 kbps" && hl == "320 kbps", "bitrate range")
    } else { check(false, "bitrate kind \(p[2].kind)") }
    check(p[2].defaultValue == "192", "bitrate default")
    if case .range(let lo, let hi, let ll, _) = p[3].kind {
        check(lo == 0 && hi == 9 && ll == "Best - slowest", "quality range with dash in alias: \(String(describing: ll))")
    } else { check(false, "quality kind \(p[3].kind)") }
    if case .choice(let c) = p[4].kind { check(c.count == 3 && p[4].defaultValue == nil, "preset") } else { check(false, "preset kind") }
    check(p[2].arguments(for: "256") == ["-b", "256"], "spaced arg")
    check(p[4].arguments(for: "extreme") == ["--preset=extreme"], "inline arg \(p[4].arguments(for: "extreme"))")
    check(p[0].arguments(for: "on") == ["--resample"] && p[0].arguments(for: "off").isEmpty, "toggle args")
    check(p[4].flag == "--preset" && p[2].flag == "-b", "flags \(p[4].flag) \(p[2].flag)")
}

// Drives
let drives = FreacHelp.drives(fromList: fixture("drives.txt"))
check(drives.count == 1 && drives[0].path == "/dev/disk4" && drives[0].name == "MATSHITA DVD-R UJ-8A8", "drives \(drives)")

// Command building
var s = ConversionSettings()
s.outputFolder = "/Users/me/Music/out"
s.encoderValues["lame"] = ["-b <val>": "256", "-m <val>": "auto", "--resample": "on", "--preset=<val>": ""]
s.cueSheet = true
let args = CommandBuilder.arguments(settings: s, encoder: lame, source: .files(["/a b/one.flac", "/x/two.wav"]))
check(args == ["-e", "lame", "-d", "/Users/me/Music/out", "-p", "<artist>/<album>/<track> - <title>", "--cuesheet",
               "--", "--resample", "-b", "256", "/a b/one.flac", "/x/two.wav"], "args \(args)")
s.singleFile = true; s.singleFileName = "Mix"; s.superFast = true; s.threads = 4
let cd = CommandBuilder.arguments(settings: s, encoder: lame, source: .audioCD)
check(cd.prefix(4) == ["-e", "lame", "-o", "/Users/me/Music/out/Mix.mp3"] && cd.contains("--threads=4")
      && cd.contains("-cd") && cd.contains("--cddb") && !cd.contains("-p") && cd.last == "256", "cd \(cd)")
check(CommandBuilder.display(executable: "/A/freaccmd", arguments: ["-p", "<a> - b", "it's"]) == "/A/freaccmd -p '<a> - b' 'it'\\''s'", "quote")
check(CommandBuilder.isValidTrackList("all") && CommandBuilder.isValidTrackList("1-5,7, 9") && !CommandBuilder.isValidTrackList("5-1")
      && !CommandBuilder.isValidTrackList("a") && !CommandBuilder.isValidTrackList("1,,2"), "track lists")

// Progress parsing across chunk boundaries
var pp = ProgressParser()
var events: [ProgressParser.Event] = []
for chunk in ["Processing fi", "le: /a/one.flac...", "do", "ne.\nProcessing file: /a/two.wav...done.\n", "Warning: something\n"] {
    events += pp.feed(chunk)
}
events += pp.flush()
check(events == [.started("/a/one.flac"), .finished("/a/one.flac"), .started("/a/two.wav"), .finished("/a/two.wav"),
                 .message("Warning: something")], "events \(events)")
check(pp.finished == 2 && !pp.aborted, "counts")
var pp2 = ProgressParser()
let e2 = pp2.feed("Processing file: Audio CD 0 - Track 3...aborted.\n")
check(pp2.aborted && e2.count == 2, "aborted \(e2)")

// Saved engine answer: reused only for the same freaccmd
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("frickoss-cache-\(getpid())")
let fakeApp = tmp.appendingPathComponent("freac.app/Contents")
try! FileManager.default.createDirectory(at: fakeApp.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
let fakeCmd = fakeApp.appendingPathComponent("MacOS/freaccmd").path
try! "v1".write(toFile: fakeCmd, atomically: true, encoding: .utf8)
try! "<plist/>".write(to: fakeApp.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
let cacheURL = tmp.appendingPathComponent("support/engine.json")
let fp = EngineCache.Fingerprint.of(executable: fakeCmd)
check(fp != nil && fp?.size == 2 && fp?.bundleInfoModified != nil, "fingerprint \(String(describing: fp))")
if let fp {
    EngineCache(format: EngineCache.currentFormat, fingerprint: fp, version: "1.1.7", encoders: [lame]).save(to: cacheURL)
    let back = EngineCache.load(from: cacheURL, matching: fp)
    check(back?.version == "1.1.7" && back?.encoders == [lame], "cache round trip")
    try! "v1.1.8".write(toFile: fakeCmd, atomically: true, encoding: .utf8)   // fre:ac updated
    let fp2 = EngineCache.Fingerprint.of(executable: fakeCmd)!
    check(fp2 != fp && EngineCache.load(from: cacheURL, matching: fp2) == nil, "stale cache ignored")
    EngineCache(format: EngineCache.currentFormat, fingerprint: fp2, version: "1.1.8", encoders: []).save(to: cacheURL)
    check(EngineCache.load(from: cacheURL, matching: fp2) == nil, "empty answer not reused")
    EngineCache(format: EngineCache.currentFormat - 1, fingerprint: fp2, version: "1.1.8", encoders: [lame]).save(to: cacheURL)
    check(EngineCache.load(from: cacheURL, matching: fp2) == nil, "old format not reused")
}
try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
