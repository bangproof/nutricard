import Foundation

/// Looks up packaged foods by barcode in Open Food Facts (https://world.openfoodfacts.org).
struct OpenFoodFactsClient {
    struct Response: Decodable {
        let status: Int?
        let product: Product?
    }

    struct Product: Decodable {
        let productName: String?
        let brands: String?
        let servingSize: String?
        let servingQuantity: FlexibleDouble?
        let nutriments: [String: FlexibleDouble]?
        let imageFrontURL: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands
            case servingSize = "serving_size"
            case servingQuantity = "serving_quantity"
            case nutriments
            case imageFrontURL = "image_front_url"
            case imageURL = "image_url"
        }
    }

    func draft(forUPC code: String) async throws -> FoodDraft? {
        for variant in UPC.lookupVariants(code) {
            let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(variant).json?fields=product_name,brands,serving_size,serving_quantity,nutriments,image_front_url,image_url")!
            let data: Data
            do {
                data = try await HTTP.get(url)
            } catch HTTPError.status(404) {
                continue
            }
            if let draft = try Self.draft(from: data, upc: code) {
                return draft
            }
        }
        return nil
    }

    /// Converts an Open Food Facts response into a 1-serving draft.
    static func draft(from data: Data, upc: String) throws -> FoodDraft? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == 1, let product = response.product else { return nil }

        let nutriments = product.nutriments ?? [:]
        let servingGrams = product.servingQuantity?.value.flatMap { $0 > 0 ? $0 : nil }
        let hasServingValues = nutriments["energy-kcal_serving"]?.value != nil
            || nutriments["carbohydrates_serving"]?.value != nil
            || nutriments["proteins_serving"]?.value != nil

        func amount(_ key: String) -> Double? {
            if hasServingValues {
                return nutriments["\(key)_serving"]?.value
            }
            guard let per100 = nutriments["\(key)_100g"]?.value else { return nil }
            return per100 * (servingGrams ?? 100) / 100
        }

        var draft = FoodDraft(name: product.productName?.nilIfBlank ?? "Product \(upc)")
        draft.brand = product.brands?
            .split(separator: ",").first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        draft.upc = upc
        draft.emoji = "🛒"
        if hasServingValues || servingGrams != nil {
            draft.servingDescription = product.servingSize?.nilIfBlank
                ?? servingGrams.map { "\(NumberFormatting.plain($0)) g" }
                ?? "1 serving"
            draft.servingGrams = servingGrams
        } else {
            draft.servingDescription = "100 g"
            draft.servingGrams = 100
        }

        draft.calories = amount("energy-kcal") ?? amount("energy").map { $0 / 4.184 }
        draft.totalFat = amount("fat")
        draft.saturatedFat = amount("saturated-fat")
        draft.transFat = amount("trans-fat")
        draft.cholesterol = amount("cholesterol").map { $0 * 1000 }
        draft.sodium = amount("sodium").map { $0 * 1000 } ?? amount("salt").map { $0 * 400 }
        draft.totalCarbohydrate = amount("carbohydrates")
        draft.dietaryFiber = amount("fiber")
        draft.totalSugars = amount("sugars")
        draft.protein = amount("proteins")
        draft.potassium = amount("potassium").map { $0 * 1000 }
        draft.imageURL = product.imageFrontURL ?? product.imageURL
        return draft
    }
}
