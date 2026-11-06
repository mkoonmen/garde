import Foundation

/// What's in season around Long Island / the Northeast, month by month.
enum Seasonal {
    static let byMonth: [Int: [String]] = [
        1: ["kale", "leeks", "parsnips", "turnips", "winter squash", "citrus", "storage apples"],
        2: ["kale", "leeks", "parsnips", "cabbage", "citrus", "storage potatoes"],
        3: ["leeks", "spinach", "parsnips", "maple syrup", "citrus"],
        4: ["asparagus", "ramps", "spinach", "radishes", "scallions", "rhubarb"],
        5: ["asparagus", "peas", "strawberries", "radishes", "lettuce", "rhubarb", "ramps"],
        6: ["strawberries", "peas", "zucchini", "lettuce", "garlic scapes", "cherries", "bay scallops"],
        7: ["corn", "tomatoes", "blueberries", "zucchini", "cucumbers", "peaches", "green beans", "basil"],
        8: ["corn", "tomatoes", "peaches", "eggplant", "peppers", "melons", "blueberries", "striped bass"],
        9: ["apples", "corn", "tomatoes", "grapes", "pears", "peppers", "eggplant", "squash"],
        10: ["apples", "pumpkins", "winter squash", "brussels sprouts", "pears", "cauliflower", "sweet potatoes"],
        11: ["brussels sprouts", "winter squash", "sweet potatoes", "cranberries", "apples", "kale", "Peconic bay scallops"],
        12: ["winter squash", "kale", "cabbage", "parsnips", "citrus", "pears"],
    ]

    static func now(_ date: Date = .now) -> [String] {
        byMonth[Calendar.current.component(.month, from: date)] ?? []
    }

    static var hint: String { "In season locally right now: \(now().joined(separator: ", ")). Prefer these when it fits." }
}
