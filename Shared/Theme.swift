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

/// The kitchen wall behind every screen: navy (or cream) subway-tile backsplash with a warm pendant-light glow.
/// Static drawing, so it costs nothing while scrolling.
struct GardeBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.13, green: 0.20, blue: 0.42), Color(red: 0.07, green: 0.11, blue: 0.27)]
                                        : [Color(red: 0.97, green: 0.94, blue: 0.88), Color(red: 0.91, green: 0.86, blue: 0.78)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let tw: CGFloat = 34, th: CGFloat = 17
                var row = 0
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = row.isMultiple(of: 2) ? 0 : -tw / 2
                    while x < size.width {
                        ctx.fill(Path(roundedRect: CGRect(x: x + 1, y: y + 1, width: tw - 2, height: th - 2), cornerRadius: 3),
                                 with: .color(dark ? .white.opacity(0.045) : .white.opacity(0.55)))
                        x += tw
                    }
                    y += th; row += 1
                }
            }
            RadialGradient(colors: [Color(red: 1, green: 0.8, blue: 0.5).opacity(dark ? 0.28 : 0.35), .clear],
                           center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 280)
        }
        .ignoresSafeArea()
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
