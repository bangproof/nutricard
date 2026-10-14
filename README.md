# NutriCard

A native SwiftUI app for iPhone 15 Pro (iOS 17+) that shows foods as swipeable nutrition cards.

## Features

- **Swipeable cards.** Swipe left and right through your foods, or use the arrows under the card.
- **Search.** The search bar filters cards by name, brand or UPC. If nothing matches, you can add the food from there.
- **Photo on a white background.** Each card shows a photo of the food. Vision's foreground segmentation (iOS 17) cuts the food out and centers it on a white square. Photos come from the product's Open Food Facts image, a Wikipedia lead image, or your own camera or photo library.
- **Nutrition facts for 1 serving.** A label in FDA style shows calories, fats, cholesterol, sodium, carbohydrate, fiber, sugars, protein and potassium, with % Daily Value. Every card opens at **1 serving**. A stepper lets you look at other amounts, and it goes back to 1 when you leave the card.
- **Glycemic index and glycemic load.** GI values come from the [University of Sydney Glycemic Index Database](https://glycemicindex.com) (the International Tables of Glycemic Index). The app calculates GL for the serving shown as `GI × available carbohydrate ÷ 100`. Low, medium and high use the University of Sydney cut-offs: GI ≤55 / 56–69 / ≥70 and GL ≤10 / 11–19 / ≥20. Each card links to the source.
- **Blood pressure ❤️.** Foods with good evidence of helping lower blood pressure get a small red heart next to their name. The bottom of the card explains why (for example, nitrates in beets, spinach, kale and collard greens, potassium in bananas, omega-3s in salmon).
- **Add foods.**
  - *Scan a UPC.* VisionKit's live barcode scanner (UPC-A/E, EAN-8/13) looks the code up in [Open Food Facts](https://world.openfoodfacts.org), then in USDA FoodData Central. You can also type the code.
  - *Enter a name.* The app searches [USDA FoodData Central](https://fdc.nal.usda.gov) and scales the result to one serving. You can also enter everything by hand.
  - New foods get a GI suggestion from a bundled University of Sydney reference table, and a blood-pressure suggestion from a built-in knowledge base. Foods with ≥460 mg sodium per serving are never flagged automatically. You review and edit everything before you save.
- **Starter database.** 30 common foods are included, with USDA nutrition values and University of Sydney GI values.

## Building

1. Open `Nutricard.xcodeproj` in **Xcode 16 or later**. The project uses folder-synchronized groups, so new files in `Nutricard/` are picked up automatically.
2. Choose your development team under *Signing & Capabilities*, and change the bundle ID (`com.bangproof.nutricard`) if needed.
3. Run on an iPhone 15 Pro. Barcode scanning and subject cut-out need a real device. In the Simulator, type UPCs by hand, and photos are centered on white without the cut-out.

Unit tests (`⌘U`) cover the GI/GL math, the GI and blood-pressure matching, Open Food Facts and USDA parsing, and the seed data.

### USDA API key

Name search works without setup through the shared `DEMO_KEY`, which allows only a few requests per hour. You can get a free personal key at <https://fdc.nal.usda.gov/api-key-signup> and paste it under **Add by Name → USDA API key**.

## Web app (GitHub Pages)

`docs/` is a version of NutriCard that runs in the browser. It needs no build step and has the same features: swipeable cards, search, 1-serving nutrition labels, GI and GL with the University of Sydney source, heart indicators with blood-pressure notes, adding foods by UPC (camera scanner or typed) or by name, and photos on white backgrounds. Foods are saved on the device in IndexedDB.

**Publish:** go to the repo's *Settings → Pages*. Under *Build and deployment*, choose *Deploy from a branch*, pick the branch, select the `/docs` folder and click *Save*. The site appears at `https://<owner>.github.io/<repo>/`. GitHub Pages on a private repo needs a paid GitHub plan.

**Install on iPhone:** open the site in Safari, tap *Share → Add to Home Screen*, and it opens full screen like an app. The camera needs HTTPS, which GitHub Pages provides.

**Run locally:** `cd docs && python3 -m http.server 8000`, then open <http://localhost:8000>. Logic tests: `node --test tests-web/logic.test.mjs`.

**Web version differences:** barcodes are read by the browser's built-in `BarcodeDetector` or by ZXing (on iPhone Safari). Backgrounds are made white with a canvas flood-fill, not Apple's Vision cut-out, so photos with busy backgrounds are centered on white without being cut out. The app looks for online photos that were already shot on white (Wikimedia Commons) and prefers those.

## Project layout

```
Nutricard/
  App/          App entry point (SwiftData container)
  Models/       FoodItem (SwiftData), NutritionFacts, FoodDraft, glycemic rules
  Services/     Open Food Facts, USDA, Wikipedia images + white-background compositing,
                GI reference table, blood-pressure knowledge base, seeding
  Views/        Card pager, food card, editor, barcode scanner, name search
  Resources/    SeedFoods.json, GIReference.json
NutricardTests/ XCTest unit tests
```

## Data sources and disclaimer

- Glycemic index: University of Sydney, Glycemic Index Research and GI Database, glycemicindex.com. Also Atkinson, Foster-Powell & Brand-Miller, *International Tables of Glycemic Index and Glycemic Load Values: 2008*, Diabetes Care 31(12).
- Nutrition: USDA FoodData Central and Open Food Facts (ODbL).
- Photos: Open Food Facts, Wikipedia/Wikimedia Commons (under each image's own license), or the user's own photos.

NutriCard gives general nutrition information. It is not medical advice.
