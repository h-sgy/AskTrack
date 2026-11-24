import Sparkle
import SwiftUI

@main
struct AskTrackApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            SessionView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { updaterController.checkForUpdates(nil) }
            }
        }
    }
}
