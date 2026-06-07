import SwiftUI

@main
struct HabitTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(environment)
                .task {
                    await environment.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        environment.retryPendingHabitSyncIfNeeded()
                        environment.retryPendingBucketSyncIfNeeded()
                    }
                }
        }
    }
}
