import SwiftUI
import AppKit

/// Visual language taken from the app icon: graphite, a "record light" coral and a sky-blue waveform.
enum Theme {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }

    static let inkTop = hex(0x20242E)
    static let inkBottom = hex(0x0B0D12)
    static let bar = hex(0x0E1015)
    static let coral = hex(0xFF5A4E)
    static let coralDeep = hex(0xD63A40)
    static let sky = hex(0x5CC8FF)
    static let cream = hex(0xF5F1EA)
    static let slate = hex(0x96A0B0)
    static let dim = hex(0x6B7484)
    static let amber = hex(0xF5B03C)
    static let success = hex(0x7ED6B8)

    static let accent = coral

    static let wave = LinearGradient(colors: [coral, sky], startPoint: .leading, endPoint: .trailing)
    static let waveDiagonal = LinearGradient(colors: [coral, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let record = LinearGradient(colors: [coral, coralDeep], startPoint: .top, endPoint: .bottom)

    static let panelFill = Color.white.opacity(0.035)
    static let cardFill = Color.white.opacity(0.045)
    static let fieldFill = Color.black.opacity(0.28)
    static let chipFill = Color.white.opacity(0.06)
    static let hoverFill = Color.white.opacity(0.12)
    static let hairline = Color.white.opacity(0.09)
    static let track = Color.white.opacity(0.08)

    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) { return img }
        return NSApp?.applicationIconImage ?? NSImage()
    }()
}

/// Graphite backdrop with a soft coral glow top-left and a sky glow bottom-right, like the icon.
struct StudioBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.inkTop, Theme.inkBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.coral.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Theme.sky.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 640)
        }
        .ignoresSafeArea()
    }
}

/// Frosted panel with a faint coral-to-sky rim.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.panelFill))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.coral.opacity(0.28), Theme.hairline, Theme.sky.opacity(0.26)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 14) -> some View { modifier(GlassPanel(radius: radius)) }
}

/// Uppercase, tracked section label — the "FROM · …" kickers used across the dustalexw apps.
struct Kicker: View {
    let text: String
    var color: Color = Theme.sky
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A rounded card with a kicker, an optional icon tile and content.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    var colors: [Color] = [Theme.coral, Theme.sky]
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol, colors: colors, size: 20)
                Kicker(text: title, color: Theme.cream.opacity(0.85))
                Spacer()
                if let trailing { trailing }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Small rounded-square icon tile filled with a gradient, like System Settings.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: 3, y: 1)
    }
}

/// Muted helper text.
struct Hint: View {
    let text: String
    var color: Color = Theme.slate
    init(_ text: String, color: Color = Theme.slate) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

/// The big call-to-action: a glowing coral "record" button.
struct GlowButtonStyle: ButtonStyle {
    var colors: [Color] = [Theme.coral, Theme.coralDeep]
    func makeBody(configuration: Configuration) -> some View { GlowBody(configuration: configuration, colors: colors) }

    private struct GlowBody: View {
        let configuration: Configuration
        let colors: [Color]
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: (colors.first ?? .clear).opacity(isEnabled ? (hovering ? 0.65 : 0.45) : 0), radius: hovering ? 12 : 8, y: 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .saturation(isEnabled ? 1 : 0.3)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// Secondary rounded buttons ("Add Files…", "Browse…").
struct PlateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PlateBody(configuration: configuration) }

    private struct PlateBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Theme.hoverFill : Theme.chipFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(hovering ? Theme.coral.opacity(0.6) : Theme.hairline))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Uniform circular icon button used for inline actions.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 26
    func makeBody(configuration: Configuration) -> some View { IconBody(configuration: configuration, diameter: diameter) }

    private struct IconBody: View {
        let configuration: Configuration
        let diameter: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: diameter * 0.46, weight: .semibold))
                .foregroundStyle(hovering ? Theme.cream : Theme.slate)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? Theme.hoverFill : Theme.chipFill))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .contentShape(Circle())
                .onHover { hovering = $0 }
        }
    }
}

/// A small capsule label.
struct Chip: View {
    let text: String
    var color: Color = Theme.slate
    var fill: Color = Theme.chipFill
    var mono = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// Brand mark: the app icon and "freac" — "fre" in cream, "ac" in coral, as in the README header.
struct BrandMark: View {
    var size: CGFloat = 19
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: Theme.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.9, height: size * 1.9)
            (Text("fre").foregroundColor(Theme.cream) + Text("ac").foregroundColor(Theme.coral))
                .font(.system(size: size, weight: .heavy, design: .rounded))
            Text("dustalexw edition")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.sky)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.sky.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Theme.sky.opacity(0.35)))
        }
        .fixedSize()
    }
}

/// Puts the window's traffic lights inside the brand bar: transparent title bar, full-size content and a
/// unified (taller) title strip, so the lights sit centred in the bar like the other dustalexw apps.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // SwiftUI's .hiddenTitleBar style gives a transparent title bar over full-size content; an empty
        // unified toolbar makes that strip as tall as the brand bar, so the lights sit centred in it.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "freac-edition.chrome")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(Theme.inkBottom)
    }
}
