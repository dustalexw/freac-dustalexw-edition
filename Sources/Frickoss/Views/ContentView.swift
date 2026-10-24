import SwiftUI
import AppKit

enum SourceMode: String, CaseIterable, Identifiable {
    case files = "Files"
    case cd = "Audio CD"
    var id: Self { self }
    var symbol: String { self == .files ? "music.note.list" : "opticaldisc" }
}

struct ContentView: View {
    @EnvironmentObject private var engine: FreacEngine
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var converter: Converter
    @AppStorage("sourceMode") private var mode: SourceMode = .files
    @AppStorage("showActivity") private var showActivity = true

    private var source: ConversionSource {
        mode == .cd ? .audioCD : .files(converter.jobs.map(\.url.path))
    }

    private var arguments: [String] {
        CommandBuilder.arguments(settings: store.settings, encoder: engine.encoder(store.settings.encoderID), source: source)
    }

    private var canConvert: Bool {
        guard engine.cmdPath != nil, !engine.encoders.isEmpty, !converter.isRunning else { return false }
        if mode == .cd { return CommandBuilder.isValidTrackList(store.settings.tracks) }
        return !converter.jobs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            actionRow
            if engine.cmdPath == nil && !engine.isLoading {
                MissingFreacBanner().padding(.horizontal, 14).padding(.bottom, 10)
            } else if let problem = engine.problem {
                Banner(symbol: "exclamationmark.triangle.fill", color: Theme.amber, text: problem)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }
            HSplitView {
                Group {
                    if mode == .files { QueuePane() } else { CDPane() }
                }
                .glassPanel()
                .padding(.trailing, 6)
                .frame(minWidth: 380, idealWidth: 470)

                OptionsPane()
                    .glassPanel()
                    .padding(.leading, 6)
                    .frame(minWidth: 400, idealWidth: 470)
            }
            .padding(.horizontal, 14)

            if showActivity && (converter.isRunning || !converter.log.isEmpty) {
                ActivityPanel()
                    .glassPanel()
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .frame(height: 170)
            }

            CommandPreviewBar(command: CommandBuilder.display(executable: engine.cmdPath.map { ($0 as NSString).lastPathComponent }, arguments: arguments),
                              fullCommand: CommandBuilder.display(executable: engine.cmdPath, arguments: arguments))
                .padding(.horizontal, 14).padding(.vertical, 10)
            StatusBar(showActivity: $showActivity)
        }
        .background(StudioBackground())
        .background(WindowChrome())
        .ignoresSafeArea(.container, edges: .top)
        .task {
            if engine.encoders.isEmpty { await engine.refresh() }
            chooseDefaultEncoder()
        }
        .onChange(of: engine.encoders) { _ in chooseDefaultEncoder() }
        .onChange(of: mode) { m in
            if m == .cd && engine.drives.isEmpty { Task { await engine.scanDrives() } }
        }
    }

    private func chooseDefaultEncoder() {
        guard !engine.encoders.isEmpty, engine.encoder(store.settings.encoderID) == nil else { return }
        let preferred = ["lame", "coreaudio", "flac", "opus"].first { engine.encoder($0) != nil }
        store.settings.encoderID = preferred ?? engine.encoders[0].id
    }

    // MARK: Brand bar — macOS owns clicks in this strip, so it carries only the brand.

    private var brandBar: some View {
        HStack(spacing: 12) {
            BrandMark()
            Spacer()
            if let v = engine.version {
                Chip(text: "fre:ac \(v)", color: Theme.slate)
            }
            Chip(text: "v\(AppInfo.version)", color: Theme.coral, fill: Theme.coral.opacity(0.14))
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Theme.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.wave).frame(height: 2) }
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $mode) {
                ForEach(SourceMode.allCases) { m in
                    Label(m.rawValue, systemImage: m.symbol).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            .disabled(converter.isRunning)

            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.slate)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.chipFill))
                .overlay(Capsule().strokeBorder(Theme.hairline))

            Spacer()

            if converter.isRunning {
                Button { converter.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PlateButtonStyle())
                .keyboardShortcut(".", modifiers: .command)
            }
            Button(action: convert) {
                HStack(spacing: 7) {
                    Image(systemName: mode == .cd ? "opticaldisc" : "waveform")
                        .font(.system(size: 12, weight: .bold))
                    Text(convertTitle)
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!canConvert)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Start (⌘↩)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var convertTitle: String {
        if converter.isRunning { return mode == .cd ? "Ripping…" : "Converting…" }
        if mode == .cd { return "Rip CD" }
        let n = converter.jobs.count
        return n > 1 ? "Convert \(n)" : "Convert"
    }

    private var summary: String {
        let s = store.settings
        guard let enc = engine.encoder(s.encoderID) else { return engine.isLoading ? "Asking fre:ac for its encoders…" : "No encoder" }
        var parts = [enc.name]
        let changed = CommandBuilder.encoderArguments(enc, values: s.encoderValues[s.encoderID] ?? [:])
        if !changed.isEmpty { parts.append(changed.joined(separator: " ")) }
        if s.singleFile { parts.append("one file") }
        if s.superFast { parts.append("SuperFast") }
        return parts.joined(separator: "  ·  ")
    }

    private func convert() {
        guard canConvert, let exe = engine.cmdPath else { return }
        showActivity = true
        converter.start(executable: exe, arguments: arguments, source: source,
                        outputFolder: store.settings.outputFolder,
                        expected: mode == .cd ? 0 : converter.jobs.count)
    }
}

// MARK: - Banners

struct Banner: View {
    let symbol: String
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.cream)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.35)))
    }
}

struct MissingFreacBanner: View {
    @EnvironmentObject private var engine: FreacEngine
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("fre:ac isn't installed").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.cream)
                Text("frickoss is a new window for fre:ac's own converter. Install fre:ac from freac.org, or point to it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.slate)
            }
            Spacer()
            Button("Get fre:ac") { NSWorkspace.shared.open(URL(string: "https://www.freac.org/downloads-mainmenu-33")!) }
                .buttonStyle(PlateButtonStyle())
            Button("Locate…") { locate() }
                .buttonStyle(PlateButtonStyle())
            Button("Check Again") { Task { await engine.refresh() } }
                .buttonStyle(PlateButtonStyle())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.amber.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.amber.opacity(0.35)))
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.message = "Choose freac.app (or its freaccmd program)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { engine.useCustom(url) }
    }
}

// MARK: - Command preview

struct CommandPreviewBar: View {
    let command: String
    let fullCommand: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.waveDiagonal)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.slate)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .fixedSize()
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullCommand, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(IconButtonStyle(diameter: 24))
            .help("Copy the full command to paste into Terminal")
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Activity

struct ActivityPanel: View {
    @EnvironmentObject private var converter: Converter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Kicker(text: converter.isRunning ? "Now converting" : "Last run", color: Theme.coral)
                if let current = converter.current {
                    Text((current as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(progressText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.slate)
            }
            WaveProgress(fraction: converter.fraction, indeterminate: converter.isRunning && converter.total == 0)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(converter.log.suffix(400)) { line in
                            LogRow(line: line).id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: converter.log.count) { _ in
                    if let last = converter.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .padding(12)
    }

    private var progressText: String {
        if converter.total > 0 { return "\(converter.completed) of \(converter.total)" }
        return converter.completed > 0 ? "\(converter.completed) done" : ""
    }
}

struct LogRow: View {
    let line: LogLine
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 78, alignment: .leading)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.kind == .info ? Theme.slate : Theme.cream)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
    private var text: String {
        switch line.kind {
        case .started, .done: return (line.text as NSString).lastPathComponent
        default: return line.text
        }
    }
    private var label: String {
        switch line.kind {
        case .info: return "Note"
        case .started: return "Converting"
        case .done: return "Done"
        case .warning: return "Warning"
        case .error: return "Problem"
        }
    }
    private var color: Color {
        switch line.kind {
        case .info: return Theme.dim
        case .started: return Theme.sky
        case .done: return Theme.success
        case .warning: return Theme.amber
        case .error: return Theme.coral
        }
    }
}

/// A progress bar filled with the coral → sky waveform gradient.
struct WaveProgress: View {
    let fraction: Double
    var indeterminate = false
    @State private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if indeterminate {
                    Capsule().fill(Theme.wave)
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: geo.size.width * phase)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { phase = 0.7 }
                        }
                } else {
                    Capsule().fill(Theme.wave)
                        .frame(width: max(fraction > 0 ? 8 : 0, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.25), value: fraction)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject private var converter: Converter
    @EnvironmentObject private var engine: FreacEngine
    @Binding var showActivity: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer()
            if !converter.log.isEmpty || converter.isRunning {
                Button(showActivity ? "Hide Activity" : "Show Activity") { showActivity.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.slate)
            }
            if let out = converter.lastOutput, !converter.isRunning, converter.completed > 0 {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: out))
                } label: {
                    Text("Show in Finder  ›").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.coral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Theme.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var text: String {
        if let s = converter.status { return s.text }
        if engine.isLoading { return "Asking fre:ac what it can do…" }
        if engine.cmdPath == nil { return "fre:ac not found — install it or click Locate…" }
        let n = engine.encoders.count
        return "Ready — fre:ac \(engine.version ?? "") with \(n) encoder\(n == 1 ? "" : "s")."
    }

    private var dotColor: Color {
        if converter.isRunning { return Theme.coral }
        switch converter.status?.kind {
        case .error: return Theme.coral
        case .warning: return Theme.amber
        case .done: return Theme.success
        default: return engine.cmdPath == nil ? Theme.amber : Theme.success
        }
    }

    private var textColor: Color {
        switch converter.status?.kind {
        case .error: return Theme.coral
        case .warning: return Theme.amber
        case .done: return Theme.success
        default: return Theme.slate
        }
    }
}
