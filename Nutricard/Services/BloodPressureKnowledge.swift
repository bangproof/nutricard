import Foundation

/// A food (or food group) with good evidence of helping lower blood pressure.
struct BloodPressureFact: Hashable, Identifiable {
    let id: String
    let match: [String]
    var exclude: [String] = []
    let description: String
}

enum BloodPressureKnowledge {
    /// Foods at or above 20% of the sodium Daily Value per serving are not flagged automatically,
    /// because the sodium works against any blood-pressure benefit.
    static let maxSodiumPerServing = 460.0

    /// Words that usually describe a processed form that loses the benefit.
    static let commonExclusions = [
        "chips", "chip", "fried", "cake", "cookie", "cookies", "pie", "candy", "pudding",
        "salted", "pickled", "sweetened", "frosted", "sugar", "syrup", "cream", "creamed", "muffin", "bread",
    ]

    static let facts: [BloodPressureFact] = [
        BloodPressureFact(
            id: "beet",
            match: ["beet", "beets", "beetroot", "beetroots"],
            description: "Beets are one of the richest sources of dietary nitrate. Your body converts nitrate into nitric oxide, which helps widen and relax blood vessels. Clinical trials show beetroot juice and whole beets can lower systolic blood pressure within hours, and the effect holds with regular intake."
        ),
        BloodPressureFact(
            id: "spinach",
            match: ["spinach"],
            description: "Spinach is rich in dietary nitrates that your body converts to nitric oxide, which helps widen and relax blood vessels. It also supplies potassium and magnesium, both of which support healthy blood pressure."
        ),
        BloodPressureFact(
            id: "kale",
            match: ["kale"],
            description: "Kale provides dietary nitrates, potassium and magnesium. Nitrates are converted to nitric oxide, which relaxes and widens blood vessels, while potassium helps your body excrete excess sodium."
        ),
        BloodPressureFact(
            id: "collard",
            match: ["collard", "collards", "collard greens"],
            description: "Collard greens are a nitrate-rich leafy green. Dietary nitrate is converted to nitric oxide, helping blood vessels relax and widen. Collards also add potassium, calcium and fiber."
        ),
        BloodPressureFact(
            id: "arugula",
            match: ["arugula", "rocket", "roquette"],
            description: "Arugula (rocket) is among the most nitrate-dense vegetables. Your body turns that nitrate into nitric oxide, which helps blood vessels relax and can lower blood pressure."
        ),
        BloodPressureFact(
            id: "chard",
            match: ["chard", "swiss chard"],
            description: "Swiss chard provides dietary nitrates plus potassium and magnesium — a combination that helps blood vessels relax and offsets the effects of sodium."
        ),
        BloodPressureFact(
            id: "celery",
            match: ["celery"],
            description: "Celery contains dietary nitrates and potassium. Nitrates are converted to nitric oxide, which helps relax blood vessel walls."
        ),
        BloodPressureFact(
            id: "banana",
            match: ["banana", "bananas"],
            exclude: ["split"],
            description: "Bananas are a good source of potassium, which helps your kidneys flush out excess sodium and eases tension in blood vessel walls. Potassium-rich diets are linked to lower blood pressure."
        ),
        BloodPressureFact(
            id: "sweet-potato",
            match: ["sweet potato", "sweet potatoes", "potatoes sweet", "potato sweet", "yam", "yams"],
            exclude: ["fries", "casserole"],
            description: "Sweet potatoes are rich in potassium and fiber. Potassium counterbalances sodium and helps relax blood vessel walls, supporting lower blood pressure."
        ),
        BloodPressureFact(
            id: "pulses",
            match: ["lentil", "lentils", "chickpea", "chickpeas", "garbanzo", "beans kidney", "kidney beans", "black beans", "beans black", "pinto beans", "beans pinto", "navy beans", "white beans"],
            exclude: ["baked beans", "refried", "hummus"],
            description: "Pulses such as lentils, chickpeas and beans deliver potassium, magnesium and fiber. Clinical trials show that eating pulses regularly modestly lowers blood pressure, and they are a staple of the DASH eating plan."
        ),
        BloodPressureFact(
            id: "oats",
            match: ["oat", "oats", "oatmeal", "oat porridge", "porridge oats", "rolled oats", "steel cut oats"],
            exclude: ["bar", "granola", "instant flavored", "milk"],
            description: "Whole-grain oats contain beta-glucan, a soluble fiber linked to modest reductions in blood pressure, and are a core part of the DASH eating plan."
        ),
        BloodPressureFact(
            id: "berries",
            match: ["blueberry", "blueberries", "strawberries", "strawberry", "raspberries", "blackberries", "berries"],
            exclude: ["jam", "jelly", "preserves", "yogurt"],
            description: "Blueberries and other berries are rich in anthocyanins, flavonoids that support nitric oxide production and help keep arteries flexible. Regular intake is associated with lower blood pressure."
        ),
        BloodPressureFact(
            id: "oily-fish",
            match: ["salmon", "mackerel", "sardine", "sardines", "herring", "trout"],
            exclude: ["smoked", "lox"],
            description: "Salmon and other oily fish provide the omega-3 fats EPA and DHA, which can lower blood pressure, reduce inflammation and help keep blood vessels flexible."
        ),
        BloodPressureFact(
            id: "pistachio",
            match: ["pistachio", "pistachios"],
            description: "Pistachios provide potassium, magnesium and unsaturated fats. Clinical trials suggest eating unsalted pistachios regularly can lower blood pressure."
        ),
        BloodPressureFact(
            id: "garlic",
            match: ["garlic"],
            exclude: ["salt", "butter"],
            description: "Garlic contains allicin and other sulfur compounds that boost nitric oxide production and help relax blood vessels. Studies show modest blood pressure reductions, especially in people with hypertension."
        ),
        BloodPressureFact(
            id: "low-fat-dairy",
            match: ["skim milk", "milk skim", "nonfat milk", "milk nonfat", "low fat milk", "lowfat milk", "milk lowfat", "plain yogurt", "yogurt plain", "greek yogurt", "yogurt greek"],
            exclude: ["chocolate", "flavored", "vanilla", "strawberry"],
            description: "Low-fat dairy supplies calcium, potassium and magnesium and is part of the DASH eating plan, which is proven to lower blood pressure."
        ),
        BloodPressureFact(
            id: "pomegranate",
            match: ["pomegranate", "pomegranates"],
            description: "Pomegranate is rich in polyphenol antioxidants. Trials of pomegranate juice show it can reduce systolic blood pressure."
        ),
    ]

    static func fact(id: String) -> BloodPressureFact? {
        facts.first { $0.id == id }
    }

    static func match(for text: String, sodiumPerServing: Double? = nil) -> BloodPressureFact? {
        if let sodiumPerServing, sodiumPerServing >= maxSodiumPerServing { return nil }
        return facts
            .compactMap { fact in
                TextMatcher.score(text: text, phrases: fact.match, excluding: fact.exclude + commonExclusions)
                    .map { (fact, $0) }
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
