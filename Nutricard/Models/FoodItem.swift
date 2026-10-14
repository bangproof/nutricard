import Foundation
import SwiftData

/// A food stored in the user's database. All nutrient values are for exactly 1 serving.
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var upc: String?
    var emoji: String = "🍽️"

    var servingDescription: String = "1 serving"
    var servingGrams: Double?

    var calories: Double = 0
    var totalFat: Double = 0
    var saturatedFat: Double?
    var transFat: Double?
    /// Milligrams.
    var cholesterol: Double?
    /// Milligrams.
    var sodium: Double = 0
    var totalCarbohydrate: Double = 0
    var dietaryFiber: Double?
    var totalSugars: Double?
    var protein: Double = 0
    /// Milligrams.
    var potassium: Double?

    /// Glycemic index (glucose = 100), as published in the University of Sydney GI Database.
    var glycemicIndex: Int?
    /// Which tested food / preparation the GI value refers to.
    var glycemicNote: String?

    var lowersBloodPressure: Bool = false
    var bloodPressureNote: String?

    @Attribute(.externalStorage) var imageData: Data?
    /// Remote image to use (e.g. an Open Food Facts product photo).
    var imageSourceURL: String?
    /// Wikipedia article title used to find a photo when no other image is available.
    var imageSearchTerm: String?

    var isSeed: Bool = false
    var dateAdded: Date = Date()

    init(name: String) {
        self.name = name
    }

    var facts: NutritionFacts {
        NutritionFacts(
            calories: calories,
            totalFat: totalFat,
            saturatedFat: saturatedFat,
            transFat: transFat,
            cholesterol: cholesterol,
            sodium: sodium,
            totalCarbohydrate: totalCarbohydrate,
            dietaryFiber: dietaryFiber,
            totalSugars: totalSugars,
            protein: protein,
            potassium: potassium
        )
    }
}
