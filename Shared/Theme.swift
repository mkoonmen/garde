import SwiftUI
import UIKit

/// Garde's look, taken from the icon: deep navy + cream, serif headings.
enum Theme {
    // Brand colors (from the app icon)
    static let navy = Color(red: 21 / 255, green: 34 / 255, blue: 79 / 255)       // #15224F
    static let cream = Color(red: 242 / 255, green: 234 / 255, blue: 216 / 255)   // #F2EAD8
    static let gold = Color(red: 0.78, green: 0.62, blue: 0.33)                    // warm highlight for stars & badges

    /// Tint: navy in light mode, cream in dark mode, so it always reads.
    static let accent = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 242 / 255, green: 234 / 255, blue: 216 / 255, alpha: 1)
        : UIColor(red: 21 / 255, green: 34 / 255, blue: 79 / 255, alpha: 1) })

    /// Card / row surface: lifted navy in dark mode, warm cream in light mode.
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.18, blue: 0.33, alpha: 1)      // #212E54
        : UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1) })

    /// Page background: the icon's navy in dark mode (never pure black), soft cream in light mode.
    static let page = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 21 / 255, green: 34 / 255, blue: 79 / 255, alpha: 1)   // #15224F, same as the icon
        : UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1) })

    static func expiryColor(_ days: Int?) -> Color {
        guard let d = days else { return .secondary }
        if d < 0 { return .red }
        if d <= 2 { return .orange }
        if d <= 5 { return Color(red: 0.80, green: 0.62, blue: 0.10) }
        return .green
    }
    static func expiryText(_ days: Int?) -> String {
        guard let d = days else { return "No date" }
        switch d {
        case ..<(-1): return "Expired \(-d)d ago"
        case -1: return "Expired yesterday"
        case 0: return "Expires today"
        case 1: return "Tomorrow"
        default: return "\(d) days"
        }
    }

    /// Icon for a dish, picked from its title, used on recipe cards.
    static func dishSymbol(_ title: String) -> String {
        let t = title.lowercased()
        let map: [(String, [String])] = [
            ("fish", ["salmon", "fish", "cod", "halibut", "tuna", "bass", "shrimp", "scallop", "seafood", "clam", "mussel"]),
            ("bird", ["chicken", "turkey", "duck"]),
            ("flame", ["steak", "grill", "bbq", "beef", "burger", "ribeye", "pork", "lamb"]),
            ("leaf", ["salad", "veg", "greens", "spinach", "kale", "bowl"]),
            ("cup.and.saucer", ["soup", "stew", "chowder", "broth", "chili"]),
            ("fork.knife", ["pasta", "spaghetti", "risotto", "noodle", "linguine", "penne", "gnocchi"]),
            ("frying.pan", ["egg", "omelet", "frittata", "hash", "stir"]),
            ("birthday.cake", ["cake", "tart", "dessert", "cookie", "pie"]),
        ]
        return map.first { $0.1.contains(where: { t.contains($0) }) }?.0 ?? "fork.knife.circle"
    }
}

/// Cream/navy card used for recipe ideas and dashboard tiles.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.12)))
    }
}

/// Applies Garde's page color behind every screen and list, instead of system black/gray.
struct GardePage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { GardeBackground() }
            .containerBackground(for: .navigation) { GardeBackground() }
    }
}

extension View {
    func gardePage() -> some View { modifier(GardePage()) }
    func gardeCard() -> some View { modifier(CardStyle()) }
    /// Serif heading in the house style.
    func gardeHeading(_ style: Font = .title3) -> some View { font(style.weight(.semibold)).fontDesign(.serif) }
}

// MARK: - Living background & glass

/// Background behind every screen: a deep navy "night sky" with slow, soft aurora bands in
/// navy, indigo and teal, a thin copper rim-light along the top edge, and fine film grain.
/// No big blob: the light stays at the edges so text and glass panels always sit on dark, even color.
struct GardeBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                (dark ? Color(red: 0.05, green: 0.08, blue: 0.19) : Color(red: 0.96, green: 0.94, blue: 0.90))
                // Aurora bands drifting slowly across the top third.
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * (0.035 + Double(i) * 0.012) + Double(i) * 2.1
                    Ellipse()
                        .fill(Self.band(i, dark: dark))
                        .frame(width: 520, height: 170)
                        .rotationEffect(.degrees(-18 + Double(i) * 14 + sin(phase) * 6))
                        .offset(x: CGFloat(cos(phase) * 90), y: CGFloat(-300 + Double(i) * 70 + sin(phase * 1.3) * 25))
                        .blur(radius: 70)
                        .opacity(dark ? 0.55 : 0.35)
                }
                // Copper rim light hugging the very top.
                LinearGradient(colors: [Theme.copper.opacity(dark ? 0.35 : 0.25), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12))
                // Gentle vignette so edges fall off into deep navy.
                RadialGradient(colors: [.clear, (dark ? Color.black : Color(red: 0.85, green: 0.80, blue: 0.72)).opacity(dark ? 0.45 : 0.25)],
                               center: .center, startRadius: 200, endRadius: 650)
                GrainOverlay(opacity: dark ? 0.05 : 0.04)
            }
        }
        .ignoresSafeArea()
    }

    static func band(_ i: Int, dark: Bool) -> Color {
        let night = [Color(red: 0.16, green: 0.30, blue: 0.62), Color(red: 0.12, green: 0.45, blue: 0.55), Color(red: 0.32, green: 0.22, blue: 0.58)]
        let day = [Color(red: 0.75, green: 0.82, blue: 0.95), Color(red: 0.98, green: 0.84, blue: 0.70), Color(red: 0.86, green: 0.80, blue: 0.95)]
        return (dark ? night : day)[i % 3]
    }
}

/// Static film grain (drawn once) for a printed, premium feel.
struct GrainOverlay: View {
    var opacity: Double
    var body: some View {
        Canvas { ctx, size in
            var rng = SystemRandomNumberGenerator()
            let n = Int(size.width * size.height / 90)
            for _ in 0..<n {
                let x = CGFloat.random(in: 0..<size.width, using: &rng), y = CGFloat.random(in: 0..<size.height, using: &rng)
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(Double.random(in: 0...1, using: &rng))))
            }
        }
        .opacity(opacity)
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Frosted-glass row background so the living background shows through.
struct RowGlass: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill((scheme == .dark ? Color.white : Theme.cream).opacity(scheme == .dark ? 0.04 : 0.35)))
    }
}

/// A glowing glass card for dashboards and hero sections.
struct GlassCard<Content: View>: View {
    var tint: Color = Theme.copper
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(
                LinearGradient(colors: [tint.opacity(0.6), .white.opacity(0.08), tint.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
            .shadow(color: tint.opacity(0.25), radius: 18, y: 8)
    }
}

extension Theme {
    static let copper = Color(red: 0.86, green: 0.50, blue: 0.27)
}
