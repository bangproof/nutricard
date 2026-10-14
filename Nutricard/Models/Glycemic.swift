import SwiftUI

enum GlycemicLevel: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var color: Color {
        switch self {
        case .low: return Color(red: 0.16, green: 0.62, blue: 0.36)
        case .medium: return Color(red: 0.93, green: 0.58, blue: 0.10)
        case .high: return Color(red: 0.85, green: 0.22, blue: 0.24)
        }
    }
}

/// Glycemic index / load rules as defined by the University of Sydney GI research service.
enum Glycemic {
    static let sourceName = "University of Sydney Glycemic Index Database"
    static let sourceURL = URL(string: "https://glycemicindex.com")!
    static let searchURL = URL(string: "https://glycemicindex.com/gi-search/")!

    /// Foods with less available carbohydrate than this per serving can't be meaningfully GI-tested.
    static let minimumTestableCarbohydrate = 5.0

    /// GL = GI × available carbohydrate (g) ÷ 100
    static func load(glycemicIndex: Int, availableCarbohydrate: Double) -> Double {
        Double(glycemicIndex) * availableCarbohydrate / 100
    }

    /// Low ≤ 55, medium 56–69, high ≥ 70.
    static func indexLevel(_ gi: Int) -> GlycemicLevel {
        if gi <= 55 { return .low }
        if gi <= 69 { return .medium }
        return .high
    }

    /// Low ≤ 10, medium 11–19, high ≥ 20.
    static func loadLevel(_ gl: Double) -> GlycemicLevel {
        let rounded = gl.rounded()
        if rounded <= 10 { return .low }
        if rounded < 20 { return .medium }
        return .high
    }

    static func formatLoad(_ gl: Double) -> String {
        if gl > 0 && gl < 0.5 { return "<1" }
        return String(Int(gl.rounded()))
    }
}
