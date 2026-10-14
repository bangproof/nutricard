import Foundation

/// A tested food from the University of Sydney GI Database / International Tables of Glycemic Index.
struct GIReferenceEntry: Decodable, Hashable {
    let food: String
    let gi: Int
    let match: [String]
    var exclude: [String]?

    var citation: String { "\(food) — \(Glycemic.sourceName)" }
}

/// Bundled subset of GI values used to suggest a GI for newly added foods.
struct GIReferenceTable {
    let entries: [GIReferenceEntry]

    static let shared = GIReferenceTable(bundle: .main)

    init(entries: [GIReferenceEntry]) {
        self.entries = entries
    }

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "GIReference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([GIReferenceEntry].self, from: data)
        else {
            self.entries = []
            return
        }
        self.entries = entries
    }

    func bestMatch(for text: String) -> GIReferenceEntry? {
        entries
            .compactMap { entry in
                TextMatcher.score(text: text, phrases: entry.match, excluding: entry.exclude ?? [])
                    .map { (entry, $0) }
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
