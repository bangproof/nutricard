import Foundation

/// Nutrient amounts for one serving (grams unless noted).
struct NutritionFacts: Equatable, Hashable, Codable {
    var calories: Double
    var totalFat: Double
    var saturatedFat: Double?
    var transFat: Double?
    /// Milligrams.
    var cholesterol: Double?
    /// Milligrams.
    var sodium: Double
    var totalCarbohydrate: Double
    var dietaryFiber: Double?
    var totalSugars: Double?
    var protein: Double
    /// Milligrams.
    var potassium: Double?

    /// Carbohydrate that raises blood glucose (total carbohydrate minus fiber).
    /// GI testing and glycemic load are based on available carbohydrate.
    var availableCarbohydrate: Double {
        max(0, totalCarbohydrate - (dietaryFiber ?? 0))
    }

    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            totalFat: totalFat * factor,
            saturatedFat: saturatedFat.map { $0 * factor },
            transFat: transFat.map { $0 * factor },
            cholesterol: cholesterol.map { $0 * factor },
            sodium: sodium * factor,
            totalCarbohydrate: totalCarbohydrate * factor,
            dietaryFiber: dietaryFiber.map { $0 * factor },
            totalSugars: totalSugars.map { $0 * factor },
            protein: protein * factor,
            potassium: potassium.map { $0 * factor }
        )
    }
}

/// FDA Daily Values (2,000 calorie diet) used for %DV on the label.
enum DailyValue {
    static let totalFat = 78.0
    static let saturatedFat = 20.0
    static let cholesterol = 300.0
    static let sodium = 2300.0
    static let totalCarbohydrate = 275.0
    static let dietaryFiber = 28.0
    static let protein = 50.0
    static let potassium = 4700.0

    static func percent(_ amount: Double?, of dailyValue: Double) -> Int? {
        guard let amount else { return nil }
        return Int((amount / dailyValue * 100).rounded())
    }
}

enum NumberFormatting {
    /// Label-style amount: one decimal below 10, whole numbers above.
    static func amount(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded == 0 { return "<0.1" }
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        }
        return String(Int(value.rounded()))
    }

    /// Plain editable representation for text fields.
    static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}
