import Sparkle
import SwiftUI

@main
struct AskTrackApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(app: app, updater: updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { updaterController.checkForUpdates(nil) }
            }
            // 設定は別ウィンドウではなく、同じウィンドウの中の画面として開く
            CommandGroup(replacing: .appSettings) {
                Button("設定…") { app.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        Window("ミニウィンドウ", id: "mini") {
            MiniPanelView(app: app)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 340, height: 480)
        .windowLevel(.floating)
    }
}
