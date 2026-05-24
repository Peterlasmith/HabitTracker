import SwiftUI

@main
struct HabitTrackerApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(environment)
                .task {
                    await environment.bootstrap()
                }
        }
    }
}
