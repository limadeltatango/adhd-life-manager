import SwiftUI
import UserNotifications

@main
@MainActor
struct LifeManagerApp: App {
    @StateObject private var store = TaskStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register as early as possible for actions received after an app launch.
        UNUserNotificationCenter.current().delegate = LifeNotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            LifeManagerRootView()
                .environmentObject(store)
                .onAppear { store.bootIfNeeded() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reloadFromDisk() }
                }
        }
    }
}
