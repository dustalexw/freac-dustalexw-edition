import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Your tracks": the job list. Drop files or folders anywhere on it.
struct QueuePane: View {
    @EnvironmentObject private var converter: Converter
    @State private var selection = Set<Job.ID>()
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Your tracks", color: Theme.coral)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.slate)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button { addFiles() } label: { Label("Add Files…", systemImage: "plus") }
                    .buttonStyle(PlateButtonStyle())
                    .keyboardShortcut("o", modifiers: .command)
                Button { addFolder() } label: { Label("Add Folder…", systemImage: "folder.badge.plus") }
                    .buttonStyle(PlateButtonStyle())
                Spacer()
                Button { converter.remove(selection); selection.removeAll() } label: { Image(systemName: "minus") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(selection.isEmpty || converter.isRunning)
                    .help("Remove selected")
                Button { converter.clear(); selection.removeAll() } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(converter.jobs.isEmpty || converter.isRunning)
                    .help("Clear the list")
            }

            ZStack {
                if converter.jobs.isEmpty {
                    emptyState
                } else {
                    table
                }
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.wave, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: drop)
        }
        .padding(14)
    }

    private var subtitle: String {
        let n = converter.jobs.count
        if n == 0 { return "Drop audio files or folders here" }
        let size = ByteCountFormatter.string(fromByteCount: converter.totalBytes, countStyle: .file)
        return "\(n) file\(n == 1 ? "" : "s")  ·  \(size)"
    }

    private var table: some View {
        Table(converter.jobs, selection: $selection) {
            TableColumn("") { job in StateIcon(state: job.state) }
                .width(18)
            TableColumn("Name") { job in
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text(job.folder).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.head)
                }
                .help(job.url.path)
            }
            TableColumn("Format") { job in
                Text(job.format).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.sky)
            }
            .width(min: 44, ideal: 52, max: 70)
            TableColumn("Size") { job in
                Text(ByteCountFormatter.string(fromByteCount: job.size, countStyle: .file))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.slate)
            }
            .width(min: 56, ideal: 70, max: 90)
        }
        .scrollContentBackground(.hidden)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .onDeleteCommand { converter.remove(selection); selection.removeAll() }
        .contextMenu(forSelectionType: Job.ID.self) { ids in
            Button("Show in Finder") {
                let urls = converter.jobs.filter { ids.contains($0.id) }.map(\.url)
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            Button("Remove") { converter.remove(ids); selection.subtract(ids) }
                .disabled(converter.isRunning)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.coral.opacity(0.10)).frame(width: 86, height: 86)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.waveDiagonal)
            }
            Text("Drop music here").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.cream)
            Text("Files or whole folders — MP3, AAC, FLAC, WAV, Opus, Ogg, WMA, APE and more.\nfre:ac converts them with the format on the right.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.slate).multilineTextAlignment(.center)
            Button { addFiles() } label: { Label("Add Files…", systemImage: "plus") }
                .buttonStyle(PlateButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose audio files or folders to convert"
        if panel.runModal() == .OK { converter.add(panel.urls) }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose folders — every audio file inside is added"
        if panel.runModal() == .OK { converter.add(panel.urls) }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !converter.isRunning else { return false }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { converter.add([url]) }
            }
        }
        return true
    }
}

struct StateIcon: View {
    let state: Job.State
    var body: some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(Theme.dim).font(.system(size: 10))
        case .converting: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.system(size: 11))
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.coral).font(.system(size: 11))
        }
    }
}

/// Audio CD: drive, tracks, CDDB lookup.
struct CDPane: View {
    @EnvironmentObject private var engine: FreacEngine
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Audio CD", color: Theme.coral)
                    Text("fre:ac reads the disc, looks up the track names and converts each track.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.slate)
                }

                Card(title: "Drive", symbol: "opticaldiscdrive", colors: [Theme.coral, Theme.coralDeep],
                     trailing: AnyView(Button {
                         Task { await engine.scanDrives() }
                     } label: {
                         if engine.isScanningDrives { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
                     }
                     .buttonStyle(IconButtonStyle(diameter: 22))
                     .help("Look for drives again"))) {
                    if engine.drives.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "opticaldisc").font(.system(size: 22)).foregroundStyle(Theme.dim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.isScanningDrives ? "Looking for CD drives…" : "No CD drive found")
                                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.cream)
                                Text("Connect a drive and insert a disc, then click ↻.")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.slate)
                            }
                        }
                    } else {
                        Picker("Drive", selection: $store.settings.drive) {
                            ForEach(engine.drives) { d in
                                Text("\(d.name)  —  \(d.path)").tag(d.number)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Card(title: "Tracks", symbol: "list.number", colors: [Theme.sky, Theme.coral]) {
                    TextField("all", text: $store.settings.tracks)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    if CommandBuilder.isValidTrackList(store.settings.tracks) {
                        Hint("“all”, or numbers and ranges such as 1-5, 7, 9.")
                    } else {
                        Hint("Use “all”, or numbers and ranges such as 1-5, 7, 9.", color: Theme.coral)
                    }
                    HStack(spacing: 6) {
                        ForEach(["all", "1", "1-5"], id: \.self) { t in
                            Button(t) { store.settings.tracks = t }.buttonStyle(PlateButtonStyle())
                        }
                    }
                }

                Card(title: "Disc", symbol: "text.magnifyingglass", colors: [Theme.coral, Theme.sky]) {
                    Toggle(isOn: $store.settings.cddb) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Look up track names").foregroundStyle(Theme.cream)
                            Hint("Asks the freedb/CDDB database for artist, album and titles.")
                        }
                    }
                    Toggle(isOn: $store.settings.eject) {
                        Text("Eject the disc when finished").foregroundStyle(Theme.cream)
                    }
                }
            }
            .padding(14)
        }
        .task { if engine.drives.isEmpty { await engine.scanDrives() } }
    }
}
