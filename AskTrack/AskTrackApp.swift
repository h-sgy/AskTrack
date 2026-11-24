import Sparkle
import SwiftUI

@main
struct AskTrackApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(app: app)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { updaterController.checkForUpdates(nil) }
            }
        }
        Settings {
            SettingsView(settings: app.settings, updater: updaterController.updater)
        }
    }
}
