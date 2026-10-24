import SwiftUI
import AppKit

/// Custom About window, laid out like the other dustalexw apps: icon, name, version, what it's built on, links.
struct AboutView: View {
    @EnvironmentObject private var engine: FreacEngine
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 10) {
                stat("fre:ac", engine.version ?? "not found")
                stat("Encoders", engine.encoders.isEmpty ? "—" : "\(engine.encoders.count)")
                stat("Platform", "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
            }
            .padding(.horizontal, 26)

            VStack(alignment: .leading, spacing: 12) {
                feature("Every fre:ac format", "MP3, AAC, FLAC, Opus, Vorbis, WavPack and more, with each encoder's own options as native controls.")
                feature("CD ripping with CDDB", "Rip whole discs or chosen tracks, with names from the CDDB database.")
                feature("Nothing hidden", "The exact fre:ac command is shown live at the bottom of the window — copy it into Terminal any time.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            .padding(.horizontal, 26)
            .padding(.top, 14)

            HStack(spacing: 8) {
                link("fre:ac website", "https://www.freac.org")
                link("fre:ac source", "https://github.com/enzo1982/freac")
                link("Report a fre:ac issue", "https://github.com/enzo1982/freac/issues")
            }
            .padding(.top, 16)

            Text("fre:ac © Robert Kausch and contributors, GPL-2.0. frickoss is a native front end: all conversion is done by fre:ac's own freaccmd, unchanged. Codecs are under their own licences.")
                .font(.system(size: 10.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .frame(width: 500)
        .background(StudioBackground())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 7) {
            Image(nsImage: Theme.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: Theme.coral.opacity(0.45), radius: 22, y: 6)
            (Text("frick").foregroundColor(Theme.cream) + Text("oss").foregroundColor(Theme.coral))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Capsule().fill(Theme.wave).frame(width: 96, height: 4)
            Text("powered by fre:ac")
                .font(.system(size: 11, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.sky)
            Text("Every format fre:ac speaks, in a native Mac window.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.slate)
                .padding(.top, 2)
            Text("Version \(AppInfo.version)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.coral)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(Theme.coral.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Theme.coral.opacity(0.35)))
                .padding(.top, 2)
        }
        .padding(.top, 34)
        .padding(.bottom, 20)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.cream)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.slate)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .glassPanel(radius: 10)
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.coral)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.slate).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button(title) { if let u = URL(string: url) { openURL(u) } }
            .buttonStyle(PlateButtonStyle())
    }
}

/// Settings: where fre:ac is.
struct SettingsView: View {
    @EnvironmentObject private var engine: FreacEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "fre:ac", color: Theme.coral)
            HStack(spacing: 10) {
                Image(systemName: engine.cmdPath == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(engine.cmdPath == nil ? Theme.amber : Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.cmdPath == nil ? "fre:ac not found" : "fre:ac \(engine.version ?? "")")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                    Text(engine.cmdPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Install fre:ac from freac.org, or choose it below.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.slate)
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 8) {
                Button("Choose fre:ac…") { choose() }.buttonStyle(PlateButtonStyle())
                Button("Find Automatically") { engine.resetCustom() }.buttonStyle(PlateButtonStyle())
                if engine.isLoading { ProgressView().controlSize(.small) }
            }
            Hint("frickoss finds fre:ac by itself (normally /Applications/freac.app). Choose a different copy here if you keep one elsewhere.")
        }
        .padding(22)
        .frame(width: 460)
        .background(StudioBackground())
        .preferredColorScheme(.dark)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.message = "Choose freac.app (or its freaccmd program)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { engine.useCustom(url) }
    }
}
