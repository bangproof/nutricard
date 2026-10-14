import XCTest
@testable import Nutricard

final class GlycemicTests: XCTestCase {
    func testGlycemicLoadUsesAvailableCarbohydrate() {
        // Banana: 27 g carbohydrate, 3.1 g fiber, GI 51 → GL ≈ 12
        let facts = NutritionFacts(calories: 105, totalFat: 0.4, sodium: 1, totalCarbohydrate: 27, dietaryFiber: 3.1, protein: 1.3)
        let load = Glycemic.load(glycemicIndex: 51, availableCarbohydrate: facts.availableCarbohydrate)
        XCTAssertEqual(load, 12.19, accuracy: 0.01)
        XCTAssertEqual(Glycemic.formatLoad(load), "12")
        XCTAssertEqual(Glycemic.loadLevel(load), .medium)
    }

    func testIndexLevels() {
        XCTAssertEqual(Glycemic.indexLevel(55), .low)
        XCTAssertEqual(Glycemic.indexLevel(56), .medium)
        XCTAssertEqual(Glycemic.indexLevel(69), .medium)
        XCTAssertEqual(Glycemic.indexLevel(70), .high)
    }

    func testLoadLevels() {
        XCTAssertEqual(Glycemic.loadLevel(10.4), .low)
        XCTAssertEqual(Glycemic.loadLevel(11), .medium)
        XCTAssertEqual(Glycemic.loadLevel(19.4), .medium)
        XCTAssertEqual(Glycemic.loadLevel(20), .high)
        XCTAssertEqual(Glycemic.formatLoad(0.2), "<1")
    }

    func testScalingServings() {
        let facts = NutritionFacts(calories: 100, totalFat: 2, saturatedFat: nil, sodium: 50, totalCarbohydrate: 20, dietaryFiber: 4, protein: 3)
        let doubled = facts.scaled(by: 2)
        XCTAssertEqual(doubled.calories, 200)
        XCTAssertEqual(doubled.availableCarbohydrate, 32)
        XCTAssertNil(doubled.saturatedFat)
    }

    func testNumberFormatting() {
        XCTAssertEqual(NumberFormatting.amount(0), "0")
        XCTAssertEqual(NumberFormatting.amount(0.34), "0.3")
        XCTAssertEqual(NumberFormatting.amount(4.0), "4")
        XCTAssertEqual(NumberFormatting.amount(18.9), "19")
        XCTAssertEqual(DailyValue.percent(2300, of: DailyValue.sodium), 100)
    }
}

final class MatchingTests: XCTestCase {
    func testWordMatching() {
        XCTAssertNotNil(TextMatcher.score(text: "Rice, brown, long-grain, cooked", phrases: ["rice brown"]))
        XCTAssertNil(TextMatcher.score(text: "Licorice", phrases: ["rice"]))
        XCTAssertNil(TextMatcher.score(text: "Pistachios, salted", phrases: ["pistachios"], excluding: ["salted"]))
        XCTAssertNotNil(TextMatcher.score(text: "Pistachios, unsalted", phrases: ["pistachios"], excluding: ["salted"]))
    }

    func testBloodPressureMatches() {
        XCTAssertEqual(BloodPressureKnowledge.match(for: "Beets, boiled")?.id, "beet")
        XCTAssertEqual(BloodPressureKnowledge.match(for: "Organic Baby Spinach")?.id, "spinach")
        XCTAssertEqual(BloodPressureKnowledge.match(for: "Lentils, mature seeds, cooked")?.id, "pulses")
        XCTAssertEqual(BloodPressureKnowledge.match(for: "Sweet potato, baked")?.id, "sweet-potato")
        XCTAssertNil(BloodPressureKnowledge.match(for: "Beet sugar"))
        XCTAssertNil(BloodPressureKnowledge.match(for: "Banana chips"))
        XCTAssertNil(BloodPressureKnowledge.match(for: "Rice porridge"))
        XCTAssertNil(BloodPressureKnowledge.match(for: "White bread"))
    }

    func testHighSodiumIsNotFlagged() {
        XCTAssertNotNil(BloodPressureKnowledge.match(for: "Spinach, canned", sodiumPerServing: 300))
        XCTAssertNil(BloodPressureKnowledge.match(for: "Spinach, canned", sodiumPerServing: 700))
    }

    func testGIReferenceTable() {
        let table = GIReferenceTable(bundle: Bundle(for: FoodItem.self))
        XCTAssertFalse(table.entries.isEmpty)
        XCTAssertEqual(table.bestMatch(for: "Rice, brown, long-grain, cooked")?.gi, 68)
        XCTAssertEqual(table.bestMatch(for: "Rice, white, cooked")?.gi, 73)
        XCTAssertEqual(table.bestMatch(for: "Apple juice, unsweetened")?.gi, 41)
        XCTAssertEqual(table.bestMatch(for: "Apples, raw, with skin")?.gi, 36)
        XCTAssertEqual(table.bestMatch(for: "Sweet potato, cooked, boiled")?.gi, 63)
        XCTAssertEqual(table.bestMatch(for: "Potatoes, boiled")?.gi, 78)
        XCTAssertEqual(table.bestMatch(for: "Milk, nonfat")?.gi, 37)
        XCTAssertNil(table.bestMatch(for: "Spinach, raw"))
    }

    func testDraftSuggestions() {
        var draft = FoodDraft(name: "Beets, cooked")
        draft.sodium = 80
        draft.applySuggestions(giTable: GIReferenceTable(bundle: Bundle(for: FoodItem.self)))
        XCTAssertEqual(draft.glycemicIndex, 64)
        XCTAssertTrue(draft.lowersBloodPressure)
        XCTAssertFalse(draft.bloodPressureNote.isEmpty)
    }
}

final class SeedDataTests: XCTestCase {
    func testSeedsLoadAndAreConsistent() {
        let seeds = SeedLoader.loadSeeds(bundle: Bundle(for: FoodItem.self))
        XCTAssertGreaterThanOrEqual(seeds.count, 20)
        for seed in seeds {
            if let id = seed.bloodPressureID {
                XCTAssertNotNil(BloodPressureKnowledge.fact(id: id), "Unknown blood pressure id \(id)")
            }
            if seed.glycemicIndex == nil {
                let available = seed.totalCarbohydrate - (seed.dietaryFiber ?? 0)
                XCTAssertLessThan(available, Glycemic.minimumTestableCarbohydrate, "\(seed.name) needs a GI value")
            }
        }
        XCTAssertTrue(seeds.contains { $0.name.hasPrefix("Beets") && $0.bloodPressureID == "beet" })
    }
}

final class APIParsingTests: XCTestCase {
    func testOpenFoodFactsPerServing() throws {
        let json = """
        {"status":1,"product":{"product_name":"Oat Crunch","brands":"Acme, Acme Foods","serving_size":"1 cup (40 g)","serving_quantity":"40",
        "nutriments":{"energy-kcal_serving":150,"fat_serving":2.5,"sodium_serving":0.19,"carbohydrates_serving":30,"fiber_serving":4,
        "sugars_serving":"6","proteins_serving":5,"energy-kcal_unit":"kcal"},"image_front_url":"https://example.com/a.jpg"}}
        """
        let draft = try XCTUnwrap(OpenFoodFactsClient.draft(from: Data(json.utf8), upc: "0123456789012"))
        XCTAssertEqual(draft.name, "Oat Crunch")
        XCTAssertEqual(draft.brand, "Acme")
        XCTAssertEqual(draft.servingDescription, "1 cup (40 g)")
        XCTAssertEqual(draft.calories, 150)
        XCTAssertEqual(try XCTUnwrap(draft.sodium), 190, accuracy: 0.001)
        XCTAssertEqual(draft.totalSugars, 6)
        XCTAssertEqual(draft.imageURL, "https://example.com/a.jpg")
    }

    func testOpenFoodFactsPer100gScaledToServing() throws {
        let json = """
        {"status":1,"product":{"product_name":"Beet Chips","serving_quantity":28,"serving_size":"28 g",
        "nutriments":{"energy-kcal_100g":500,"carbohydrates_100g":50,"salt_100g":1}}}
        """
        let draft = try XCTUnwrap(OpenFoodFactsClient.draft(from: Data(json.utf8), upc: "1"))
        XCTAssertEqual(try XCTUnwrap(draft.calories), 140, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.totalCarbohydrate), 14, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.sodium), 112, accuracy: 0.001)
    }

    func testOpenFoodFactsNotFound() throws {
        XCTAssertNil(try OpenFoodFactsClient.draft(from: Data(#"{"status":0}"#.utf8), upc: "1"))
    }

    func testUSDAPortionScaling() throws {
        let json = """
        {"fdcId":1,"description":"BEETS, COOKED, BOILED, DRAINED","dataType":"SR Legacy",
        "foodNutrients":[{"nutrient":{"id":1008,"unitName":"kcal"},"amount":44},{"nutrient":{"id":1005,"unitName":"g"},"amount":10},
        {"nutrient":{"id":1093,"unitName":"mg"},"amount":77}],
        "foodPortions":[{"amount":1,"gramWeight":170,"modifier":"cup, slices","measureUnit":{"name":"undetermined"}}]}
        """
        let detail = try JSONDecoder().decode(USDAClient.FoodDetail.self, from: Data(json.utf8))
        let draft = USDAClient.draft(from: detail)
        XCTAssertEqual(draft.name, "Beets, cooked, boiled, drained")
        XCTAssertEqual(draft.servingDescription, "1 cup, slices (170 g)")
        XCTAssertEqual(try XCTUnwrap(draft.calories), 74.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.sodium), 130.9, accuracy: 0.001)
    }

    func testUPCEquivalence() {
        XCTAssertTrue(UPC.equivalent("0012345678905", "012345678905"))
        XCTAssertFalse(UPC.equivalent("123", "124"))
        XCTAssertEqual(UPC.lookupVariants("0012345678905"), ["0012345678905", "012345678905"])
    }
}
