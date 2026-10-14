import SwiftUI
import AVFoundation

/// Add a food by scanning (or typing) its UPC. Looks it up in Open Food Facts, then USDA FoodData Central.
struct ScanAddView: View {
    let existingFoods: [FoodItem]
    let onFinish: (FoodItem?) -> Void

    @AppStorage("usdaAPIKey") private var usdaAPIKey = ""
    @State private var manualCode = ""
    @State private var lookingUp: String?
    @State private var errorMessage: String?
    @State private var result: LookupResult?
    @State private var scannerAvailable: Bool?
    @FocusState private var manualFieldFocused: Bool

    struct LookupResult: Hashable {
        var draft: FoodDraft
        var notice: String?
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if scannerAvailable == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if scannerAvailable == true {
                    BarcodeScannerView(isScanning: lookingUp == nil && result == nil && !manualFieldFocused) { code in
                        lookUp(code)
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "barcode.viewfinder",
                        description: Text("Allow camera access in Settings, or type the UPC below.")
                    )
                }

                controls
            }
            .navigationTitle("Scan UPC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                }
            }
            .navigationDestination(item: $result) { result in
                FoodEditorView(draft: result.draft, notice: result.notice, onFinish: onFinish)
            }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                scannerAvailable = BarcodeScannerView.isAvailable
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let lookingUp {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking up \(lookingUp)…")
                }
                .font(.subheadline)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Point the camera at a barcode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Or type the UPC", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($manualFieldFocused)
                Button("Look Up") {
                    manualFieldFocused = false
                    lookUp(manualCode)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualCode.filter(\.isNumber).count < 6 || lookingUp != nil)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private func lookUp(_ rawCode: String) {
        let code = rawCode.filter(\.isNumber)
        guard lookingUp == nil, result == nil, code.count >= 6 else { return }

        if let existing = existingFoods.first(where: { UPC.equivalent($0.upc, code) }) {
            onFinish(existing)
            return
        }

        lookingUp = code
        errorMessage = nil
        Task {
            defer { lookingUp = nil }
            do {
                if let draft = try await OpenFoodFactsClient().draft(forUPC: code) {
                    result = LookupResult(draft: draft, notice: "Found in Open Food Facts. Check the values against the package label.")
                    return
                }
                if let draft = try? await USDAClient(apiKey: usdaAPIKey).draft(forUPC: code) {
                    result = LookupResult(draft: draft, notice: "Found in USDA FoodData Central. Check the values against the package label.")
                    return
                }
                var draft = FoodDraft()
                draft.upc = code
                result = LookupResult(draft: draft, notice: "UPC \(code) wasn't found online. Enter the details from the package label.")
            } catch {
                errorMessage = "Lookup failed: \(error.localizedDescription)"
            }
        }
    }
}
