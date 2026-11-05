import SwiftUI

enum Theme {
    static let accent = Color(red: 0.80, green: 0.42, blue: 0.20)   // copper
    static func expiryColor(_ days: Int?) -> Color {
        guard let d = days else { return .secondary }
        if d < 0 { return .red }
        if d <= 2 { return .orange }
        if d <= 5 { return .yellow }
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
}
