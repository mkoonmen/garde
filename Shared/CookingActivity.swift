import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity shown on the Lock Screen and Dynamic Island while Cook mode is open:
/// the current step and a countdown for the nearest timer.
struct CookingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var step: Int
        var total: Int
        var text: String
        var timerEnds: Date?
    }
    var title: String
}

#if !GARDE_EXTENSION
/// Starts, updates and ends the cooking Live Activity (app side only).
@MainActor
enum CookActivity {
    private static var current: Activity<CookingAttributes>?

    static func update(title: String, step: Int, total: Int, text: String, timerEnds: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = CookingAttributes.ContentState(step: step, total: total, text: String(text.prefix(140)), timerEnds: timerEnds)
        let content = ActivityContent(state: state, staleDate: nil)
        if let a = current, a.attributes.title == title {
            Task { await a.update(content) }
        } else {
            end()
            current = try? Activity.request(attributes: CookingAttributes(title: title), content: content)
        }
    }

    static func end() {
        guard let a = current else { return }
        current = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
#endif
