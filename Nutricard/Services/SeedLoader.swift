import Foundation
import SwiftData

struct FoodSeed: Decodable {
    let name: String
    let emoji: String
    let wikiTitle: String?
    let servingDescription: String
    let servingGrams: Double?
    let calories: Double
    let totalFat: Double
    let saturatedFat: Double?
    let transFat: Double?
    let cholesterol: Double?
    let sodium: Double
    let totalCarbohydrate: Double
    let dietaryFiber: Double?
    let totalSugars: Double?
    let protein: Double
    let potassium: Double?
    let glycemicIndex: Int?
    let glycemicNote: String?
    let bloodPressureID: String?

    func makeItem() -> FoodItem {
        let item = FoodItem(name: name)
        item.emoji = emoji
        item.imageSearchTerm = wikiTitle
        item.servingDescription = servingDescription
        item.servingGrams = servingGrams
        item.calories = calories
        item.totalFat = totalFat
        item.saturatedFat = saturatedFat
        item.transFat = transFat
        item.cholesterol = cholesterol
        item.sodium = sodium
        item.totalCarbohydrate = totalCarbohydrate
        item.dietaryFiber = dietaryFiber
        item.totalSugars = totalSugars
        item.protein = protein
        item.potassium = potassium
        item.glycemicIndex = glycemicIndex
        item.glycemicNote = glycemicNote
        if let bloodPressureID, let fact = BloodPressureKnowledge.fact(id: bloodPressureID) {
            item.lowersBloodPressure = true
            item.bloodPressureNote = fact.description
        }
        item.isSeed = true
        return item
    }
}

enum SeedLoader {
    private static let seededKey = "didSeedFoods.v1"

    static func loadSeeds(bundle: Bundle = .main) -> [FoodSeed] {
        guard let url = bundle.url(forResource: "SeedFoods", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([FoodSeed].self, from: data)) ?? []
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        for seed in loadSeeds() {
            context.insert(seed.makeItem())
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}
