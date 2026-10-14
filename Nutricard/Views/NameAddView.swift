import SwiftUI

/// Add a food by name: search USDA FoodData Central, or enter the details manually.
struct NameAddView: View {
    let onFinish: (FoodItem?) -> Void

    @AppStorage("usdaAPIKey") private var usdaAPIKey = ""
    @State private var query: String
    @State private var results: [USDAClient.FoodSummary] = []
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var loadingID: Int?
    @State private var errorMessage: String?
    @State private var draftToEdit: FoodDraft?

    init(initialQuery: String, onFinish: @escaping (FoodItem?) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onFinish = onFinish
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        draftToEdit = FoodDraft(name: trimmedQuery)
                    } label: {
                        Label(
                            trimmedQuery.isEmpty ? "Enter a food manually" : "Enter “\(trimmedQuery)” manually",
                            systemImage: "square.and.pencil"
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if hasSearched && results.isEmpty {
                        Text("No matches. Try a simpler name, or enter it manually.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { food in
                        Button {
                            select(food)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.displayName)
                                        .foregroundStyle(.primary)
                                    if !food.subtitle.isEmpty {
                                        Text(food.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if loadingID == food.fdcId {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(loadingID != nil)
                    }
                } header: {
                    Text("USDA FoodData Central")
                }

                Section {
                    SecureField("Personal API key (optional)", text: $usdaAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a free key at api.data.gov", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                } header: {
                    Text("USDA API key")
                } footer: {
                    Text("Without a key the shared DEMO_KEY is used, which allows only a few searches per hour.")
                }
            }
            .navigationTitle("Add by Name")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Food name, e.g. beets")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                }
            }
            .navigationDestination(item: $draftToEdit) { draft in
                FoodEditorView(draft: draft, onFinish: onFinish)
            }
            .task {
                if !trimmedQuery.isEmpty && !hasSearched { await search() }
            }
        }
    }

    private func search() async {
        guard !trimmedQuery.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            results = try await USDAClient(apiKey: usdaAPIKey).search(trimmedQuery)
        } catch {
            results = []
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    private func select(_ food: USDAClient.FoodSummary) {
        loadingID = food.fdcId
        errorMessage = nil
        Task {
            defer { loadingID = nil }
            do {
                draftToEdit = try await USDAClient(apiKey: usdaAPIKey).draft(fdcId: food.fdcId)
            } catch {
                errorMessage = "Couldn't load \(food.displayName): \(error.localizedDescription)"
            }
        }
    }
}
