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

    /// Card surface: warm cream in light mode, lifted navy in dark mode.
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.12, green: 0.16, blue: 0.29, alpha: 1)
        : UIColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1) })

    /// Page background behind lists.
    static let page = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1)
        : UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1) })

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

extension View {
    func gardeCard() -> some View { modifier(CardStyle()) }
    /// Serif heading in the house style.
    func gardeHeading(_ style: Font = .title3) -> some View { font(style.weight(.semibold)).fontDesign(.serif) }
}
