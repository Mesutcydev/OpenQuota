import SwiftUI

/// Design tokens — "porcelain & ink".
///
/// A cool porcelain canvas with solid, quiet cards and near-black ink. Gauges are
/// monochrome: **colour only appears when something needs attention** (amber
/// from 75%, coral from 90%), so the screen stays calm and a warning actually
/// stands out. Provider identity lives in a small tinted glyph, nothing more.
enum Theme {
    // MARK: Accent

    /// App accent — formal monochrome: graphite in light, cool off-white in
    /// dark. Used for the prompt, controls and selection; the only colour
    /// left in the app is the amber/coral of a warning.
    static let brand = adaptive(light: "15171A", dark: "ECECEE")
    /// Secondary neutral accent.
    static let brandDeep = adaptive(light: "5F6670", dark: "A3A3A8")

    // MARK: Surfaces

    /// Cool porcelain off-white in light, neutral graphite in dark — never pure
    /// white or pure black, which is what made the old screen glare.
    static let canvas = adaptive(light: "F2F3F5", dark: "0E0E10", oled: "000000")
    /// Opaque content card.
    static let surface = adaptive(light: "FFFFFF", dark: "18181B", oled: "0A0A0B")
    /// Control sitting inside a card.
    static let surfaceRaised = adaptive(light: "EBEDF0", dark: "232327", oled: "141416")
    /// Row fill for system lists that sit on the canvas.
    static let rowFill = surface
    static let hairline = adaptive(light: "10182826", dark: "FFFFFF1A", oled: "FFFFFF17")
    static let divider = adaptive(light: "10182817", dark: "FFFFFF12", oled: "FFFFFF10")
    static let fillSubtle = adaptive(light: "1018280B", dark: "FFFFFF0D")
    static let track = adaptive(light: "E3E6EA", dark: "2A2A2E", oled: "1C1C1F")

    // MARK: Ink

    static let ink = adaptive(light: "15171A", dark: "F2F2F4")
    static let inkSecondary = adaptive(light: "5F6670", dark: "9E9EA4")
    static let inkTertiary = adaptive(light: "9AA0A8", dark: "66666C")
    /// Calm gauge fill: ink, slightly softened.
    static let gauge = adaptive(light: "23262B", dark: "E2E2E6")

    // MARK: Severity

    enum Level: Int, Comparable {
        case calm, watch, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    static let watchFraction = 0.75
    static let criticalFraction = 0.90

    static let watch = adaptive(light: "B86A00", dark: "EFB25A")
    static let critical = adaptive(light: "C2412F", dark: "F0907F")
    static let healthy = adaptive(light: "878C94", dark: "8C8C92")

    static func level(_ fraction: Double) -> Level {
        if fraction >= criticalFraction { return .critical }
        if fraction >= watchFraction { return .watch }
        return .calm
    }

    /// Colour for a consumed fraction: the provider's own tint while healthy,
    /// orange from 75%, red from 90%. Meaning is always repeated in text.
    static func severity(_ fraction: Double, tint: Color = brand) -> Color {
        switch level(fraction) {
        case .calm: return tint
        case .watch: return watch
        case .critical: return critical
        }
    }

    static func color(for level: Level, tint: Color = brand) -> Color {
        switch level {
        case .calm: return tint
        case .watch: return watch
        case .critical: return critical
        }
    }

    // MARK: Metrics

    /// 4-pt spacing scale. Every gap and inset in the app is one of these,
    /// so rhythm is consistent and steps are visibly distinct (each step is
    /// roughly ×1.5 the last).
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    /// Modular type scale: base 16 pt × 1.25 (major third) per step.
    /// Used for the few fixed-size figures; running text uses Dynamic Type
    /// styles, which follow Apple's own proportional ramp.
    ///   -2: 10 · -1: 13 · 0: 16 · 1: 20 · 2: 25 · 3: 31 · 4: 39 · 5: 49
    enum TypeScale {
        static let base: CGFloat = 16
        static let ratio: CGFloat = 1.25
        static func step(_ n: Int) -> CGFloat { (base * pow(ratio, CGFloat(n))).rounded() }

        static let micro = step(-2)     // 10 — glyphs inside pills
        static let small = step(-1)     // 13 — small symbols
        static let title = step(2)      // 25 — page prompt
        static let display = step(4)    // 39 — hero figure
        static let icon = step(3)       // 31 — feature icons
    }

    /// Concentric radii: an inner shape's radius is its container's radius
    /// minus the inset between them, so nested corners stay parallel.
    enum Radius {
        static let hero: CGFloat = 12
        static let card: CGFloat = 12
        static let tile: CGFloat = 12
        static let control: CGFloat = 8
        static let tag: CGFloat = 4
        static let bar: CGFloat = 2
    }

    enum Spacing {
        /// Horizontal page gutter.
        static let page: CGFloat = Space.l
        /// Inner padding of a card.
        static let card: CGFloat = Space.l
        /// Gap between stacked cards.
        static let stack: CGFloat = Space.m
        /// Gap between tiles in a row.
        static let grid: CGFloat = Space.s
        /// Row insets inside a panel.
        static let rowH: CGFloat = Space.l
        static let rowV: CGFloat = Space.m
    }

    /// Provider glyph sizes on the 8-pt grid.
    enum Glyph {
        static let row: CGFloat = 40
        static let hero: CGFloat = 48
    }

    /// Tint wash strengths, shared so every tinted chip reads as one family.
    enum Wash {
        static let light: Double = 0.10
        static let dark: Double = 0.14
        static func opacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? dark : light }
    }

    // MARK: Resolution

    /// Builds a colour that resolves to `light` or `dark` from the current
    /// appearance, and to `oled` (when given) in dark mode with the pure-black
    /// trait on. Hex accepts `RRGGBB` or `RRGGBBAA`.
    static func adaptive(light: String, dark: String, oled: String? = nil) -> Color {
        Color(UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return UIColor(hex: light) }
            if let oled, traits.isOLED { return UIColor(hex: oled) }
            return UIColor(hex: dark)
        })
    }
}

extension UIColor {
    /// Parses `RRGGBB` or `RRGGBBAA`. Malformed input yields clear, so a typo
    /// shows up as a visible hole rather than a silently wrong colour.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard cleaned.count == 6 || cleaned.count == 8,
              Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(red: 0, green: 0, blue: 0, alpha: 0)
            return
        }
        let hasAlpha = cleaned.count == 8
        let red = hasAlpha ? (value >> 24) & 0xFF : (value >> 16) & 0xFF
        let green = hasAlpha ? (value >> 16) & 0xFF : (value >> 8) & 0xFF
        let blue = hasAlpha ? (value >> 8) & 0xFF : value & 0xFF
        let alpha = hasAlpha ? value & 0xFF : 0xFF
        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: Double(alpha) / 255)
    }
}

extension Color {
    /// Hex colour through the same parser as the theme, so 8-digit values
    /// carry alpha correctly everywhere.
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

// MARK: - Surfaces

/// Content card: a solid surface with a hairline edge plus one level of
/// elevation — a soft shadow on porcelain, a lit top edge on graphite (shadows
/// vanish on dark, so depth comes from light instead).
struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.Spacing.card
    var radius: CGFloat = Theme.Radius.card
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background(Theme.surface, in: shape)
            .overlay { GlassRim(shape: shape) }
            .elevated()
    }
}

/// Hairline edge so a card holds its shape on the canvas. In dark mode the
/// top of the rim catches light, which reads as the card sitting above.
struct GlassRim<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            shape.strokeBorder(Theme.hairline, lineWidth: 1)
            if scheme == .dark {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One elevation level: ambient + key shadow on light, none on dark (the
/// rim highlight does that job).
struct Elevation: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 1, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 12, y: 4)
    }
}

/// Staggered entrance: fade and rise by one spacing step, each item a beat
/// after the last. Skipped under Reduce Motion.
struct Entrance: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Theme.Space.s)
            .onAppear {
                guard !shown else { return }
                withAnimation(.settle.delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func elevated() -> some View { modifier(Elevation()) }

    /// Staggered fade-and-rise on first appearance.
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }

    func card(padding: CGFloat = Theme.Spacing.card, radius: CGFloat = Theme.Radius.card,
              interactive: Bool = false) -> some View {
        modifier(CardSurface(padding: padding, radius: radius, interactive: interactive))
    }

    /// Hero panel — now the same solid card, slightly roomier.
    func glassPanel(padding: CGFloat = Theme.Space.xl, radius: CGFloat = Theme.Radius.hero, tint: Color? = nil) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }

    /// Small uppercase monospaced section label, e.g. "PROVIDERS".
    func eyebrow() -> some View {
        self
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// Page backdrop: porcelain.
struct CanvasBackground: View {
    var body: some View {
        Theme.canvas
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Type

extension Font {
    /// Monospaced type for the terminal look.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Motion

extension Animation {
    /// Motion tokens. Durations follow the same ×1.5 rhythm as spacing:
    /// press feedback 0.2 s, state changes 0.3 s, layout settles 0.45 s.
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.84)
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.88)
}

// MARK: - OLED

/// "Pure black" trait. Lives in the UIKit trait collection so the dynamic
/// colours above can read it, and is bridged to SwiftUI's environment so the
/// root view can switch it with `.environment(\.oledBlack, true)`.
struct OLEDTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
    static let name = "OLEDBlack"
}

extension UITraitCollection {
    var isOLED: Bool { self[OLEDTrait.self] }
}

extension UIMutableTraits {
    var isOLED: Bool {
        get { self[OLEDTrait.self] }
        set { self[OLEDTrait.self] = newValue }
    }
}

private struct OLEDKey: EnvironmentKey {
    static let defaultValue = false
}

extension OLEDKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection.isOLED }
    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) { mutableTraits.isOLED = value }
}

extension EnvironmentValues {
    /// Pure-black surfaces in dark mode. No effect in light mode.
    var oledBlack: Bool {
        get { self[OLEDKey.self] }
        set { self[OLEDKey.self] = newValue }
    }
}
