import Foundation

/// Searches USDA FoodData Central (https://fdc.nal.usda.gov) by food name.
struct USDAClient {
    /// `DEMO_KEY` works out of the box but is rate limited; a free personal key can be set in the app.
    var apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey.nilIfBlank ?? "DEMO_KEY"
    }

    struct SearchResponse: Decodable {
        let foods: [FoodSummary]?
    }

    struct FoodSummary: Decodable, Identifiable, Hashable {
        let fdcId: Int
        let description: String
        let dataType: String?
        let brandOwner: String?
        let brandName: String?
        let gtinUpc: String?
        let householdServingFullText: String?

        var id: Int { fdcId }

        var displayName: String { USDAClient.prettify(description) }

        var subtitle: String {
            [brandName ?? brandOwner, dataType].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
        }
    }

    struct FoodDetail: Decodable {
        let fdcId: Int
        let description: String
        let dataType: String?
        let brandOwner: String?
        let brandName: String?
        let gtinUpc: String?
        let servingSize: Double?
        let servingSizeUnit: String?
        let householdServingFullText: String?
        let foodNutrients: [DetailNutrient]?
        let foodPortions: [Portion]?
    }

    struct DetailNutrient: Decodable {
        let nutrient: NutrientInfo?
        let amount: Double?
    }

    struct NutrientInfo: Decodable {
        let id: Int?
        let number: String?
        let unitName: String?
    }

    struct Portion: Decodable {
        let amount: Double?
        let gramWeight: Double?
        let modifier: String?
        let portionDescription: String?
        let measureUnit: MeasureUnit?
    }

    struct MeasureUnit: Decodable {
        let name: String?
    }

    func search(_ query: String) async throws -> [FoodSummary] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        let data = try await HTTP.get(components.url!)
        return try JSONDecoder().decode(SearchResponse.self, from: data).foods ?? []
    }

    func detail(fdcId: Int) async throws -> FoodDetail {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(fdcId)")!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        let data = try await HTTP.get(components.url!)
        return try JSONDecoder().decode(FoodDetail.self, from: data)
    }

    func draft(fdcId: Int) async throws -> FoodDraft {
        Self.draft(from: try await detail(fdcId: fdcId))
    }

    /// Finds a branded product by its barcode (used when Open Food Facts doesn't know it).
    func draft(forUPC code: String) async throws -> FoodDraft? {
        let results = try await search(code)
        guard let hit = results.first(where: { UPC.equivalent($0.gtinUpc, code) }) else { return nil }
        var draft = try await draft(fdcId: hit.fdcId)
        draft.upc = code
        return draft
    }

    // MARK: - Conversion

    enum NutrientID {
        static let energyKcal = [1008, 2047, 2048]
        static let protein = 1003
        static let totalFat = 1004
        static let carbohydrate = 1005
        static let fiber = 1079
        static let sugars = [2000, 1063]
        static let sodium = 1093
        static let potassium = 1092
        static let cholesterol = 1253
        static let saturatedFat = 1258
        static let transFat = 1257
    }

    /// FoodData Central reports nutrients per 100 g; scale them to one serving.
    static func draft(from detail: FoodDetail) -> FoodDraft {
        var per100: [Int: Double] = [:]
        for entry in detail.foodNutrients ?? [] {
            guard let id = entry.nutrient?.id, let amount = entry.amount else { continue }
            if id == 1008 || id == 2047 || id == 2048, entry.nutrient?.unitName?.uppercased() == "KJ" { continue }
            per100[id] = amount
        }

        let (servingDescription, grams) = serving(for: detail)
        let factor = grams / 100
        func value(_ id: Int) -> Double? { per100[id].map { $0 * factor } }
        func first(_ ids: [Int]) -> Double? { ids.lazy.compactMap { value($0) }.first }

        var draft = FoodDraft(name: prettify(detail.description))
        draft.brand = (detail.brandName ?? detail.brandOwner).map(prettify) ?? ""
        draft.upc = detail.gtinUpc ?? ""
        draft.servingDescription = servingDescription
        draft.servingGrams = grams
        draft.calories = first(NutrientID.energyKcal)
        draft.totalFat = value(NutrientID.totalFat)
        draft.saturatedFat = value(NutrientID.saturatedFat)
        draft.transFat = value(NutrientID.transFat)
        draft.cholesterol = value(NutrientID.cholesterol)
        draft.sodium = value(NutrientID.sodium)
        draft.totalCarbohydrate = value(NutrientID.carbohydrate)
        draft.dietaryFiber = value(NutrientID.fiber)
        draft.totalSugars = first(NutrientID.sugars)
        draft.protein = value(NutrientID.protein)
        draft.potassium = value(NutrientID.potassium)
        return draft
    }

    /// Picks the food's labelled serving (branded) or its first household portion; falls back to 100 g.
    static func serving(for detail: FoodDetail) -> (String, Double) {
        if let size = detail.servingSize, size > 0,
           let unit = detail.servingSizeUnit?.lowercased(), ["g", "grm", "ml", "mlt"].contains(unit) {
            let metric = "\(NumberFormatting.plain(size)) \(unit.hasPrefix("m") ? "ml" : "g")"
            if let household = detail.householdServingFullText?.nilIfBlank {
                return ("\(household) (\(metric))", size)
            }
            return (metric, size)
        }
        if let portion = detail.foodPortions?.first(where: { ($0.gramWeight ?? 0) > 0 }),
           let grams = portion.gramWeight {
            var words: [String] = []
            if let amount = portion.amount, amount > 0 { words.append(NumberFormatting.plain(amount)) }
            if let unit = portion.measureUnit?.name?.nilIfBlank, unit.lowercased() != "undetermined" {
                words.append(unit)
            }
            if let text = (portion.modifier ?? portion.portionDescription)?.nilIfBlank,
               !text.allSatisfy(\.isNumber) {
                words.append(text)
            }
            let label = words.isEmpty ? "1 serving" : words.joined(separator: " ")
            return ("\(label) (\(NumberFormatting.plain(grams.rounded())) g)", grams)
        }
        return ("100 g", 100)
    }

    /// "BANANAS, RAW" → "Bananas, raw"
    static func prettify(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == trimmed.uppercased(), trimmed.contains(where: \.isLetter) else { return trimmed }
        let lower = trimmed.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
