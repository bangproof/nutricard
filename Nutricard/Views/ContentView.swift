import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]

    @State private var searchText = ""
    @State private var selection: UUID?
    @State private var sheet: ActiveSheet?
    @State private var foodToDelete: FoodItem?

    enum ActiveSheet: Identifiable {
        case scan
        case name(String)
        case edit(FoodItem)

        var id: String {
            switch self {
            case .scan: return "scan"
            case .name(let query): return "name-\(query)"
            case .edit(let food): return "edit-\(food.id)"
            }
        }
    }

    private var filteredFoods: [FoodItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return foods }
        return foods.filter { food in
            food.name.localizedCaseInsensitiveContains(query)
                || (food.brand?.localizedCaseInsensitiveContains(query) ?? false)
                || UPC.equivalent(food.upc, query)
        }
    }

    private var currentFood: FoodItem? {
        filteredFoods.first { $0.id == selection } ?? filteredFoods.first
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("NutriCard")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search foods"
                )
                .toolbar { toolbar }
                .sheet(item: $sheet) { sheet in
                    sheetContent(sheet)
                }
                .confirmationDialog(
                    "Delete \(foodToDelete?.name ?? "food")?",
                    isPresented: Binding(get: { foodToDelete != nil }, set: { if !$0 { foodToDelete = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { deleteFood() }
                }
                .onChange(of: searchText) {
                    if !filteredFoods.contains(where: { $0.id == selection }) {
                        selection = filteredFoods.first?.id
                    }
                }
                .task {
                    SeedLoader.seedIfNeeded(context)
                    await ImageBackfill.run(context: context)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = filteredFoods
        if foods.isEmpty {
            ContentUnavailableView {
                Label("No Foods Yet", systemImage: "fork.knife")
            } description: {
                Text("Scan a UPC barcode or enter a food name to build your database.")
            } actions: {
                addButtons(query: "")
            }
        } else if list.isEmpty {
            ContentUnavailableView {
                Label("No Results for “\(searchText)”", systemImage: "magnifyingglass")
            } description: {
                Text("Add it to your database.")
            } actions: {
                addButtons(query: searchText)
            }
        } else {
            CardPager(foods: list, selection: $selection)
        }
    }

    private func addButtons(query: String) -> some View {
        VStack(spacing: 12) {
            Button {
                sheet = .name(query.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Label(query.isEmpty ? "Enter a Food Name" : "Add “\(query)”", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            Button {
                sheet = .scan
            } label: {
                Label("Scan UPC Barcode", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(.bordered)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let food = currentFood {
                Menu {
                    Button {
                        sheet = .edit(food)
                    } label: {
                        Label("Edit \(food.name)", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        foodToDelete = food
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Card options")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheet = .scan
                } label: {
                    Label("Scan UPC Barcode", systemImage: "barcode.viewfinder")
                }
                Button {
                    sheet = .name(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Label("Enter Food Name", systemImage: "character.cursor.ibeam")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Add food")
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .scan:
            ScanAddView(existingFoods: foods, onFinish: finish)
        case .name(let query):
            NameAddView(initialQuery: query, onFinish: finish)
        case .edit(let food):
            NavigationStack {
                FoodEditorView(draft: FoodDraft(food), existing: food, onFinish: finish)
            }
        }
    }

    private func finish(_ food: FoodItem?) {
        sheet = nil
        guard let food else { return }
        searchText = ""
        selection = food.id
    }

    private func deleteFood() {
        guard let food = foodToDelete else { return }
        let list = filteredFoods
        if let index = list.firstIndex(where: { $0.id == food.id }) {
            let neighbor = list.indices.contains(index + 1) ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
            selection = neighbor?.id
        }
        context.delete(food)
        try? context.save()
        foodToDelete = nil
    }
}

/// Horizontally swipeable deck of food cards.
struct CardPager: View {
    let foods: [FoodItem]
    @Binding var selection: UUID?

    private var index: Int {
        foods.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $selection) {
                ForEach(foods) { food in
                    FoodCardView(food: food)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .tag(Optional(food.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: selection)

            HStack {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous card")

                Text("\(index + 1) of \(foods.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80)

                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                }
                .disabled(index >= foods.count - 1)
                .accessibilityLabel("Next card")
            }
            .font(.title2)
            .padding(.bottom, 8)
        }
        .onAppear {
            if selection == nil || !foods.contains(where: { $0.id == selection }) {
                selection = foods.first?.id
            }
        }
    }

    private func move(by offset: Int) {
        let target = index + offset
        guard foods.indices.contains(target) else { return }
        withAnimation { selection = foods[target].id }
    }
}

/// Downloads photos for foods that don't have one yet (e.g. the starter foods on first launch).
enum ImageBackfill {
    @MainActor
    static func run(context: ModelContext) async {
        let descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        guard let foods = try? context.fetch(descriptor) else { return }
        for food in foods where food.imageData == nil {
            if Task.isCancelled { return }
            if let image = await FoodImageService.image(
                name: food.name,
                productImageURL: food.imageSourceURL,
                wikipediaTitle: food.imageSearchTerm
            ) {
                food.imageData = image.jpegData(compressionQuality: 0.85)
                try? context.save()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FoodItem.self, inMemory: true)
}
