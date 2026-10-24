import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OptionsPane: View {
    @EnvironmentObject private var engine: FreacEngine
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FormatCard()
                OutputCard()
                ExtrasCard()
            }
            .padding(14)
        }
        .disabled(engine.cmdPath == nil)
    }
}

// MARK: - Format

struct FormatCard: View {
    @EnvironmentObject private var engine: FreacEngine
    @EnvironmentObject private var store: SettingsStore

    private var encoder: EncoderInfo? { engine.encoder(store.settings.encoderID) }

    var body: some View {
        Card(title: "Format", symbol: "waveform", trailing: resetButton) {
            if engine.isLoading && engine.encoders.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Hint("Asking fre:ac for its encoders…")
                }
            } else {
                Picker("Encoder", selection: $store.settings.encoderID) {
                    ForEach(engine.encoders) { e in
                        Text(e.name).tag(e.id)
                    }
                }
                .labelsHidden()

                if let encoder {
                    if encoder.parameters.isEmpty {
                        Hint("\(encoder.name) has no options — fre:ac uses its standard settings.")
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(encoder.parameters) { p in
                                ParameterRow(parameter: p, encoderID: encoder.id)
                            }
                        }
                        .padding(.top, 2)
                        Hint("These are \(encoder.name)'s own options, read from fre:ac. Only changes from its defaults are passed on.")
                    }
                }
            }
        }
    }

    private var resetButton: AnyView? {
        guard let encoder, store.isCustomized(encoder.id) else { return nil }
        return AnyView(
            Button("Defaults") { store.resetEncoder(encoder.id) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .help("Go back to fre:ac's defaults for this encoder")
        )
    }
}

/// One encoder option as a native control: switch, menu or slider.
struct ParameterRow: View {
    @EnvironmentObject private var store: SettingsStore
    let parameter: EncoderParameter
    let encoderID: String

    private var value: Binding<String> {
        Binding(get: { store.value(for: parameter, encoder: encoderID) },
                set: { store.setValue($0, for: parameter, encoder: encoderID) })
    }

    var body: some View {
        switch parameter.kind {
        case .toggle:
            Toggle(isOn: Binding(get: { value.wrappedValue == "on" }, set: { value.wrappedValue = $0 ? "on" : "off" })) {
                label
            }
        case .choice(let choices):
            HStack(alignment: .center, spacing: 10) {
                label
                Spacer(minLength: 8)
                Picker(parameter.name, selection: value) {
                    if parameter.defaultValue == nil {
                        Text("fre:ac default").tag("")
                    }
                    ForEach(choices) { c in
                        Text(c.label == c.value ? c.value : "\(c.label)").tag(c.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        case .range(let lo, let hi, let loLabel, let hiLabel):
            RangeRow(parameter: parameter, label: AnyView(label), lo: lo, hi: hi, loLabel: loLabel, hiLabel: hiLabel, value: value)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(parameter.name).font(.system(size: 12.5)).foregroundStyle(Theme.cream)
            Text(parameter.flag)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
    }
}

struct RangeRow: View {
    let parameter: EncoderParameter
    let label: AnyView
    let lo: Double
    let hi: Double
    let loLabel: String?
    let hiLabel: String?
    @Binding var value: String

    private var isInteger: Bool { lo.rounded() == lo && hi.rounded() == hi }
    private var number: Double { Double(value) ?? Double(parameter.defaultValue ?? "") ?? lo }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label
                Spacer()
                TextField("", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
            Slider(value: Binding(get: { min(max(number, lo), hi) },
                                  set: { value = isInteger ? String(Int($0.rounded())) : String(format: "%.2f", $0) }),
                   in: lo...hi)
            HStack {
                Text(loLabel ?? SettingsStore.format(lo))
                Spacer()
                if let d = parameter.defaultValue { Text("default \(d)") }
                Spacer()
                Text(hiLabel ?? SettingsStore.format(hi))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.dim)
        }
    }
}

// MARK: - Output

struct OutputCard: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "Output", symbol: "folder", colors: [Theme.sky, Theme.coral]) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Save to", color: Theme.slate)
                HStack(spacing: 8) {
                    Text((store.settings.outputFolder as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1).truncationMode(.head)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
                    Button("Browse…") { chooseFolder() }.buttonStyle(PlateButtonStyle())
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: store.settings.outputFolder)) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconButtonStyle(diameter: 28))
                    .disabled(!FileManager.default.fileExists(atPath: store.settings.outputFolder))
                    .help("Open in Finder")
                }
            }

            Toggle(isOn: $store.settings.singleFile) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Combine everything into one file").foregroundStyle(Theme.cream)
                    Hint("Tracks become chapters in a single file, as in fre:ac's “Encode to a single file”.")
                }
            }

            if store.settings.singleFile {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "File name", color: Theme.slate)
                    TextField("Combined", text: $store.settings.singleFileName)
                        .textFieldStyle(.roundedBorder)
                    Hint("→ \((CommandBuilder.singleFilePath(store.settings) as NSString).abbreviatingWithTildeInPath)")
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Kicker(text: "Name files like", color: Theme.slate)
                        Spacer()
                        Menu("Presets") {
                            ForEach(ConversionSettings.patternPresets, id: \.pattern) { preset in
                                Button(preset.label) { store.settings.pattern = preset.pattern }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    TextField("<filename>", text: $store.settings.pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                    TokenRow { store.settings.pattern += $0 }
                    Hint("A “/” makes a folder. Tags come from your files; for CDs, from CDDB. → \(example)")
                }
            }
        }
    }

    private var example: String {
        var s = store.settings.pattern.isEmpty ? "<filename>" : store.settings.pattern
        let sample = ["<artist>": "Air", "<album>": "Moon Safari", "<title>": "La Femme d'Argent", "<track>": "01",
                      "<disc>": "1", "<year>": "1998", "<genre>": "Electronic", "<albumartist>": "Air",
                      "<composer>": "Air", "<filename>": "track01"]
        for (k, v) in sample { s = s.replacingOccurrences(of: k, with: v) }
        let ext = CommandBuilder.extensions[store.settings.encoderID] ?? "…"
        return s + "." + ext
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose where converted files go"
        panel.directoryURL = URL(fileURLWithPath: store.settings.outputFolder)
        if panel.runModal() == .OK, let url = panel.url { store.settings.outputFolder = url.path }
    }
}

/// Click-to-insert pattern placeholders.
struct TokenRow: View {
    let insert: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(ConversionSettings.patternTokens + ["/", " - "], id: \.self) { t in
                Button { insert(t) } label: {
                    Text(t == " - " ? "–" : t.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: ""))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.sky)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.sky.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(Theme.sky.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .help("Add \(t)")
            }
        }
    }
}

/// Wraps children onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Extras

struct ExtrasCard: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var expanded = false

    var body: some View {
        Card(title: "Extras", symbol: "slider.horizontal.3", colors: [Theme.coral, Theme.coralDeep]) {
            Toggle(isOn: $store.settings.superFast) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SuperFast mode").foregroundStyle(Theme.cream)
                    Hint("Converts several parts of each file at once on all cores.")
                }
            }
            if store.settings.superFast {
                Stepper(value: $store.settings.threads, in: 0...64) {
                    Text(store.settings.threads == 0 ? "Threads: automatic" : "Threads: \(store.settings.threads)")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate)
                }
                .padding(.leading, 20)
            }
            Toggle(isOn: $store.settings.cueSheet) { Text("Create a cue sheet").foregroundStyle(Theme.cream) }
            Toggle(isOn: $store.settings.playlist) { Text("Create a playlist").foregroundStyle(Theme.cream) }

            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $store.settings.splitChapters) { Text("Split files at their chapters").foregroundStyle(Theme.cream) }
                    Toggle(isOn: $store.settings.ignoreChapters) { Text("Don't write chapters to tags").foregroundStyle(Theme.cream) }
                    Toggle(isOn: $store.settings.ignoreAlbumArt) { Text("Don't write album art to tags").foregroundStyle(Theme.cream) }
                    CoverPicker(title: "Add front cover", path: $store.settings.coverFront)
                    CoverPicker(title: "Add back cover", path: $store.settings.coverBack)
                }
                .padding(.top, 8)
            } label: {
                Text("Chapters & album art").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.cream)
            }
        }
    }
}

struct CoverPicker: View {
    let title: String
    @Binding var path: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.cream)
            Spacer()
            if !path.isEmpty {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11)).foregroundStyle(Theme.slate).lineLimit(1).truncationMode(.middle)
                Button { path = "" } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(diameter: 20))
            }
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.message = "Choose a .png or .jpg image"
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            }
            .buttonStyle(PlateButtonStyle())
        }
    }
}
