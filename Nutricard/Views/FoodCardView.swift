import SwiftUI

/// One food's card: photo on white, 1-serving nutrition facts, glycemic index/load and blood-pressure note.
struct FoodCardView: View {
    let food: FoodItem
    @State private var servings: Double = 1

    private var facts: NutritionFacts { food.facts.scaled(by: servings) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FoodPhotoView(imageData: food.imageData, emoji: food.emoji)

                header

                ServingControl(servings: $servings, servingDescription: food.servingDescription)

                NutritionLabelView(
                    facts: facts,
                    servingDescription: food.servingDescription,
                    servings: servings
                )

                GlycemicSectionView(
                    glycemicIndex: food.glycemicIndex,
                    note: food.glycemicNote,
                    availableCarbohydrate: facts.availableCarbohydrate,
                    servings: servings
                )

                if food.lowersBloodPressure {
                    BloodPressureSectionView(note: food.bloodPressureNote)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        // The card is designed as a printed-style white label in both light and dark mode.
        .environment(\.colorScheme, .light)
        .onDisappear { servings = 1 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(food.name)
                    .font(.title.bold())
                    .foregroundStyle(.black)
                if food.lowersBloodPressure {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityLabel("May help lower blood pressure")
                }
            }
            if let brand = food.brand {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let upc = food.upc {
                Label(upc, systemImage: "barcode")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FoodPhotoView: View {
    let imageData: Data?
    let emoji: String

    var body: some View {
        ZStack {
            Color.white
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Text(emoji)
                        .font(.system(size: 110))
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct ServingControl: View {
    @Binding var servings: Double
    let servingDescription: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(servings == 1 ? "1 serving" : "\(NumberFormatting.plain(servings)) servings")
                    .font(.headline)
                    .foregroundStyle(.black)
                Text("1 serving = \(servingDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("Servings", value: $servings, in: 0.5...10, step: 0.5)
                .labelsHidden()
            if servings != 1 {
                Button("Reset") { servings = 1 }
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Nutrition Facts

struct NutritionLabelView: View {
    let facts: NutritionFacts
    let servingDescription: String
    let servings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.system(size: 30, weight: .black))
            Rule(height: 1).padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline) {
                Text("Serving size").font(.subheadline.bold())
                Spacer()
                Text(servings == 1 ? servingDescription : "\(NumberFormatting.plain(servings)) × \(servingDescription)")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.trailing)
            }
            Rule(height: 9).padding(.vertical, 4)

            Text(servings == 1 ? "Amount per serving" : "Amount for \(NumberFormatting.plain(servings)) servings")
                .font(.caption.bold())
            HStack(alignment: .lastTextBaseline) {
                Text("Calories").font(.system(size: 26, weight: .black))
                Spacer()
                Text(String(Int(facts.calories.rounded()))).font(.system(size: 34, weight: .black))
            }
            Rule(height: 5).padding(.vertical, 3)

            HStack {
                Spacer()
                Text("% Daily Value*").font(.caption.bold())
            }
            .padding(.bottom, 2)

            NutrientRow(name: "Total Fat", amount: facts.totalFat, unit: "g", dailyValue: DailyValue.totalFat, bold: true)
            NutrientRow(name: "Saturated Fat", amount: facts.saturatedFat, unit: "g", dailyValue: DailyValue.saturatedFat, indent: true)
            NutrientRow(name: "Trans Fat", amount: facts.transFat, unit: "g", indent: true)
            NutrientRow(name: "Cholesterol", amount: facts.cholesterol, unit: "mg", dailyValue: DailyValue.cholesterol, bold: true)
            NutrientRow(name: "Sodium", amount: facts.sodium, unit: "mg", dailyValue: DailyValue.sodium, bold: true)
            NutrientRow(name: "Total Carbohydrate", amount: facts.totalCarbohydrate, unit: "g", dailyValue: DailyValue.totalCarbohydrate, bold: true)
            NutrientRow(name: "Dietary Fiber", amount: facts.dietaryFiber, unit: "g", dailyValue: DailyValue.dietaryFiber, indent: true)
            NutrientRow(name: "Total Sugars", amount: facts.totalSugars, unit: "g", indent: true)
            NutrientRow(name: "Protein", amount: facts.protein, unit: "g", bold: true, showDivider: false)

            Rule(height: 9).padding(.vertical, 4)
            NutrientRow(name: "Potassium", amount: facts.potassium, unit: "mg", dailyValue: DailyValue.potassium, showDivider: false)
            Rule(height: 5).padding(.vertical, 4)

            Text("* The % Daily Value tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
        .padding(10)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
    }
}

private struct Rule: View {
    let height: CGFloat
    var body: some View {
        Rectangle().fill(Color.black).frame(height: height)
    }
}

private struct NutrientRow: View {
    let name: String
    let amount: Double?
    let unit: String
    var dailyValue: Double?
    var bold = false
    var indent = false
    var showDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name).fontWeight(bold ? .bold : .regular)
                Text(amount.map { NumberFormatting.amount($0) + unit } ?? "—")
                Spacer()
                if let dailyValue, let percent = DailyValue.percent(amount, of: dailyValue) {
                    Text("\(percent)%").fontWeight(.bold)
                }
            }
            .font(.subheadline)
            .padding(.leading, indent ? 16 : 0)
            .padding(.vertical, 3)
            if showDivider {
                Rectangle().fill(Color.black.opacity(0.6)).frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Glycemic index / load

struct GlycemicSectionView: View {
    let glycemicIndex: Int?
    let note: String?
    let availableCarbohydrate: Double
    let servings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glycemic Index & Load")
                .font(.headline)
                .foregroundStyle(.black)

            if let gi = glycemicIndex {
                let load = Glycemic.load(glycemicIndex: gi, availableCarbohydrate: availableCarbohydrate)
                HStack(spacing: 12) {
                    GlycemicTile(
                        title: "Glycemic Index",
                        value: String(gi),
                        level: Glycemic.indexLevel(gi),
                        caption: "Glucose = 100"
                    )
                    GlycemicTile(
                        title: "Glycemic Load",
                        value: Glycemic.formatLoad(load),
                        level: Glycemic.loadLevel(load),
                        caption: servings == 1 ? "Per 1 serving" : "Per \(NumberFormatting.plain(servings)) servings"
                    )
                }
                Text("GL = GI × \(NumberFormatting.amount(availableCarbohydrate)) g available carbohydrate ÷ 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if availableCarbohydrate < Glycemic.minimumTestableCarbohydrate {
                HStack(spacing: 12) {
                    GlycemicTile(title: "Glycemic Index", value: "N/A", level: nil, caption: "Too little carbohydrate")
                    GlycemicTile(title: "Glycemic Load", value: "≈ 0", level: .low, caption: "Negligible effect")
                }
            } else {
                Text("No GI value recorded for this food yet. Look it up in the University of Sydney GI Database and add it with Edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Link(destination: glycemicIndex == nil ? Glycemic.searchURL : Glycemic.sourceURL) {
                Label("Source: \(Glycemic.sourceName) — glycemicindex.com", systemImage: "building.columns")
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }

            Text("GI: low ≤ 55 · medium 56–69 · high ≥ 70.  GL: low ≤ 10 · medium 11–19 · high ≥ 20.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct GlycemicTile: View {
    let title: String
    let value: String
    let level: GlycemicLevel?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                if let level {
                    Text(level.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(level.color, in: Capsule())
                }
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Blood pressure

struct BloodPressureSectionView: View {
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("May help lower blood pressure")
                    .font(.headline)
                    .foregroundStyle(.black)
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.2))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("General nutrition information, not medical advice. Talk to your doctor about managing blood pressure.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
