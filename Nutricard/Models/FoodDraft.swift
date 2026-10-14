import Foundation

/// Editable value-type copy of a food, used by the add / edit screens.
struct FoodDraft: Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var brand = ""
    var upc = ""
    var emoji = "🍽️"
    var servingDescription = "1 serving"
    var servingGrams: Double?

    var calories: Double?
    var totalFat: Double?
    var saturatedFat: Double?
    var transFat: Double?
    var cholesterol: Double?
    var sodium: Double?
    var totalCarbohydrate: Double?
    var dietaryFiber: Double?
    var totalSugars: Double?
    var protein: Double?
    var potassium: Double?

    var glycemicIndex: Int?
    var glycemicNote = ""
    var lowersBloodPressure = false
    var bloodPressureNote = ""

    var imageURL: String?

    init(name: String = "") {
        self.name = name
    }

    init(_ item: FoodItem) {
        name = item.name
        brand = item.brand ?? ""
        upc = item.upc ?? ""
        emoji = item.emoji
        servingDescription = item.servingDescription
        servingGrams = item.servingGrams
        calories = item.calories
        totalFat = item.totalFat
        saturatedFat = item.saturatedFat
        transFat = item.transFat
        cholesterol = item.cholesterol
        sodium = item.sodium
        totalCarbohydrate = item.totalCarbohydrate
        dietaryFiber = item.dietaryFiber
        totalSugars = item.totalSugars
        protein = item.protein
        potassium = item.potassium
        glycemicIndex = item.glycemicIndex
        glycemicNote = item.glycemicNote ?? ""
        lowersBloodPressure = item.lowersBloodPressure
        bloodPressureNote = item.bloodPressureNote ?? ""
        imageURL = item.imageSourceURL
    }

    var facts: NutritionFacts {
        NutritionFacts(
            calories: calories ?? 0,
            totalFat: totalFat ?? 0,
            saturatedFat: saturatedFat,
            transFat: transFat,
            cholesterol: cholesterol,
            sodium: sodium ?? 0,
            totalCarbohydrate: totalCarbohydrate ?? 0,
            dietaryFiber: dietaryFiber,
            totalSugars: totalSugars,
            protein: protein ?? 0,
            potassium: potassium
        )
    }

    /// Text used to match against the GI table and blood-pressure knowledge base.
    var matchText: String { "\(name) \(brand)" }

    /// Fills the GI and blood-pressure fields from the built-in references when they are still empty.
    mutating func applySuggestions(
        giTable: GIReferenceTable = .shared,
        bloodPressure: BloodPressureKnowledge.Type = BloodPressureKnowledge.self
    ) {
        if glycemicIndex == nil, let entry = giTable.bestMatch(for: matchText) {
            glycemicIndex = entry.gi
            glycemicNote = entry.citation
        }
        if !lowersBloodPressure, let fact = bloodPressure.match(for: matchText, sodiumPerServing: sodium) {
            lowersBloodPressure = true
            bloodPressureNote = fact.description
        }
    }

    func apply(to item: FoodItem) {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.brand = brand.nilIfBlank
        item.upc = upc.filter(\.isNumber).nilIfBlank
        item.emoji = emoji
        item.servingDescription = servingDescription.nilIfBlank ?? "1 serving"
        item.servingGrams = servingGrams
        item.calories = calories ?? 0
        item.totalFat = totalFat ?? 0
        item.saturatedFat = saturatedFat
        item.transFat = transFat
        item.cholesterol = cholesterol
        item.sodium = sodium ?? 0
        item.totalCarbohydrate = totalCarbohydrate ?? 0
        item.dietaryFiber = dietaryFiber
        item.totalSugars = totalSugars
        item.protein = protein ?? 0
        item.potassium = potassium
        item.glycemicIndex = glycemicIndex
        item.glycemicNote = glycemicNote.nilIfBlank
        item.lowersBloodPressure = lowersBloodPressure
        item.bloodPressureNote = lowersBloodPressure ? bloodPressureNote.nilIfBlank : nil
        item.imageSourceURL = imageURL
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
