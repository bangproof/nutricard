import SwiftUI
import SwiftData

@main
struct NutricardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FoodItem.self)
    }
}
