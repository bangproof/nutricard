import SwiftUI
import SwiftData
import PhotosUI

/// Review and edit a food before saving it to the database.
struct FoodEditorView: View {
    @Environment(\.modelContext) private var context

    @State private var draft: FoodDraft
    let existing: FoodItem?
    var notice: String?
    let onFinish: (FoodItem?) -> Void

    @State private var image: UIImage?
    @State private var isProcessingImage = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var imageMessage: String?

    init(draft: FoodDraft, existing: FoodItem? = nil, notice: String? = nil, onFinish: @escaping (FoodItem?) -> Void) {
        var draft = draft
        if existing == nil { draft.applySuggestions() }
        _draft = State(initialValue: draft)
        _image = State(initialValue: existing?.imageData.flatMap(UIImage.init(data:)))
        self.existing = existing
        self.notice = notice
        self.onFinish = onFinish
    }

    private var giSuggestion: GIReferenceEntry? {
        guard let entry = GIReferenceTable.shared.bestMatch(for: draft.matchText),
              entry.gi != draft.glycemicIndex else { return nil }
        return entry
    }

    private var bloodPressureSuggestion: BloodPressureFact? {
        guard !draft.lowersBloodPressure else { return nil }
        return BloodPressureKnowledge.match(for: draft.matchText, sodiumPerServing: draft.sodium)
    }

    var body: some View {
        Form {
            if let notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }

            photoSection

            Section("Food") {
                TextField("Name (required)", text: $draft.name)
                    .textInputAutocapitalization(.words)
                TextField("Brand (optional)", text: $draft.brand)
                TextField("UPC (optional)", text: $draft.upc)
                    .keyboardType(.numberPad)
            }

            Section {
                TextField("Serving size, e.g. 1 cup (240 g)", text: $draft.servingDescription)
                NumberField("Serving weight", unit: "g", value: $draft.servingGrams)
            } header: {
                Text("Serving")
            } footer: {
                Text("Cards always open at 1 serving. Enter all nutrition values below for exactly 1 serving.")
            }

            Section("Nutrition per 1 serving") {
                NumberField("Calories", unit: "kcal", value: $draft.calories)
                NumberField("Total fat", unit: "g", value: $draft.totalFat)
                NumberField("Saturated fat", unit: "g", value: $draft.saturatedFat)
                NumberField("Trans fat", unit: "g", value: $draft.transFat)
                NumberField("Cholesterol", unit: "mg", value: $draft.cholesterol)
                NumberField("Sodium", unit: "mg", value: $draft.sodium)
                NumberField("Total carbohydrate", unit: "g", value: $draft.totalCarbohydrate)
                NumberField("Dietary fiber", unit: "g", value: $draft.dietaryFiber)
                NumberField("Total sugars", unit: "g", value: $draft.totalSugars)
                NumberField("Protein", unit: "g", value: $draft.protein)
                NumberField("Potassium", unit: "mg", value: $draft.potassium)
            }

            glycemicSection
            bloodPressureSection
        }
        .navigationTitle(existing == nil ? "New Food" : "Edit Food")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onFinish(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .bold()
                    .disabled(draft.name.nilIfBlank == nil || isProcessingImage)
            }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    await process(picked)
                }
                self.photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo in
                Task { await process(photo) }
            }
            .ignoresSafeArea()
        }
        .task {
            if image == nil { await findOnlinePhoto() }
        }
    }

    // MARK: Sections

    private var photoSection: some View {
        Section {
            ZStack {
                Color.white
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(draft.emoji).font(.system(size: 80))
                }
                if isProcessingImage {
                    ProgressView("Preparing photo…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets())

            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    Spacer()
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                Spacer()
                Button {
                    Task { await findOnlinePhoto() }
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .disabled(draft.name.nilIfBlank == nil && draft.imageURL == nil)
            }
            .buttonStyle(.borderless)
            .disabled(isProcessingImage)
        } header: {
            Text("Photo")
        } footer: {
            Text(imageMessage ?? "Photos are cut out and placed on a white background automatically.")
        }
    }

    private var glycemicSection: some View {
        Section {
            NumberField(
                "Glycemic index",
                unit: "",
                value: Binding(
                    get: { draft.glycemicIndex.map { Double($0) } },
                    set: { draft.glycemicIndex = $0.map { Int($0.rounded()) } }
                )
            )
            if let gi = draft.glycemicIndex {
                let load = Glycemic.load(glycemicIndex: gi, availableCarbohydrate: draft.facts.availableCarbohydrate)
                LabeledContent("Glycemic load (1 serving)") {
                    Text("\(Glycemic.formatLoad(load)) · \(Glycemic.loadLevel(load).rawValue)")
                }
            }
            if let suggestion = giSuggestion {
                Button {
                    draft.glycemicIndex = suggestion.gi
                    draft.glycemicNote = suggestion.citation
                } label: {
                    Label("Use GI \(suggestion.gi) — \(suggestion.food)", systemImage: "wand.and.stars")
                }
            }
            TextField("Tested food / source note", text: $draft.glycemicNote, axis: .vertical)
                .font(.subheadline)
            Link(destination: Glycemic.searchURL) {
                Label("Search the University of Sydney GI Database", systemImage: "safari")
            }
        } header: {
            Text("Glycemic index")
        } footer: {
            Text("Glycemic load is calculated as GI × available carbohydrate (carbohydrate − fiber) per serving ÷ 100. Leave GI empty for foods with little or no carbohydrate.")
        }
    }

    private var bloodPressureSection: some View {
        Section {
            Toggle(isOn: $draft.lowersBloodPressure.animation()) {
                Label {
                    Text("May help lower blood pressure")
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                }
            }
            if draft.lowersBloodPressure {
                TextField("Why? (shown at the bottom of the card)", text: $draft.bloodPressureNote, axis: .vertical)
                    .lineLimit(3...10)
                    .font(.subheadline)
            }
            if let suggestion = bloodPressureSuggestion {
                Button {
                    withAnimation {
                        draft.lowersBloodPressure = true
                        draft.bloodPressureNote = suggestion.description
                    }
                } label: {
                    Label("Suggested: this food is known to support healthy blood pressure", systemImage: "wand.and.stars")
                }
            }
        } header: {
            Text("Blood pressure")
        } footer: {
            Text("Foods with 460 mg of sodium or more per serving aren't suggested automatically.")
        }
    }

    // MARK: Actions

    private func process(_ photo: UIImage) async {
        isProcessingImage = true
        image = await FoodImageService.onWhite(photo)
        draft.imageURL = nil
        imageMessage = nil
        isProcessingImage = false
    }

    private func findOnlinePhoto() async {
        guard draft.imageURL != nil || draft.name.nilIfBlank != nil else { return }
        isProcessingImage = true
        defer { isProcessingImage = false }
        if let found = await FoodImageService.image(
            name: draft.name,
            productImageURL: draft.imageURL,
            wikipediaTitle: nil
        ) {
            image = found
            imageMessage = nil
        } else {
            imageMessage = "No photo found online. Take a photo or choose one from your library."
        }
    }

    private func save() {
        let food = existing ?? FoodItem(name: draft.name)
        draft.apply(to: food)
        if let image {
            food.imageData = image.jpegData(compressionQuality: 0.85)
        }
        if existing == nil {
            food.dateAdded = Date()
            context.insert(food)
        }
        try? context.save()
        onFinish(food)
    }
}

/// Decimal text field bound to an optional number (empty = unknown).
struct NumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    @State private var text = ""

    init(_ title: String, unit: String, value: Binding<Double?>) {
        self.title = title
        self.unit = unit
        _value = value
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) {
            let parsed = Self.parse(text)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) {
            if Self.parse(text) != value { text = Self.format(value) }
        }
    }

    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        let rounded = (value * 10).rounded() / 10
        return NumberFormatting.plain(rounded)
    }
}

/// Wraps UIImagePickerController for taking a photo with the camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let photo = info[.originalImage] as? UIImage {
                parent.onCapture(photo)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
