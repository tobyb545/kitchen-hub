import SwiftUI
import SwiftData
import UserNotifications

@main
struct KitchenHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var hub: HubModel
    @State private var timers = TimerStore()
    @State private var sceneRunner = SceneRunner()

    init() {
        let container: ModelContainer
        do {
            // Keep the database in the app's own container. Once an app has an App Group (ours is
            // for the Share extension's inbox), SwiftData's default silently moves to a new, empty
            // store in the group container, which would make existing recipes vanish.
            let config = ModelConfiguration(groupContainer: .none)
            container = try ModelContainer(for: Recipe.self, ShoppingItem.self, MoodScene.self, configurations: config)
        } catch {
            fatalError("Could not open the recipe database: \(error)")
        }
        self.container = container
        _hub = State(initialValue: HubModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hub)
                .environment(timers)
                .environment(sceneRunner)
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    /// While the app is open the in-app alarm is already ringing, so show the banner silently.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
