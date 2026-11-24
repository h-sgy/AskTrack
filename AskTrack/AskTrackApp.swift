import Sparkle
import SwiftUI

@main
struct AskTrackApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            Text("AskTrack")
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { updaterController.checkForUpdates(nil) }
            }
        }
    }
}
