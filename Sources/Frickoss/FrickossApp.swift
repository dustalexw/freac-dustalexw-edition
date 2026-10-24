import SwiftUI
import AppKit

enum AppInfo {
    static let name = "frickoss"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no bundle); harmless inside the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FrickossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = FreacEngine()
    @StateObject private var store = SettingsStore()
    @StateObject private var converter = Converter()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("frickoss") {
            ContentView()
                .environmentObject(engine)
                .environmentObject(store)
                .environmentObject(converter)
                .frame(minWidth: 940, minHeight: 640)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .onDisappear { converter.stop() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About frickoss") { openWindow(id: "about", value: "about") }
            }
            CommandGroup(replacing: .help) {
                Button("fre:ac Website") { NSWorkspace.shared.open(URL(string: "https://www.freac.org")!) }
                Button("fre:ac Source on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/enzo1982/freac")!) }
            }
        }

        // A value-based group never opens on launch (a plain `Window` scene would flash up at startup).
        WindowGroup("About frickoss", id: "about", for: String.self) { _ in
            AboutView()
                .environmentObject(engine)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(engine)
                .tint(Theme.accent)
        }
    }
}
