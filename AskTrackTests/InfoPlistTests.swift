import Foundation
import Testing

// マイク利用の説明文が Info.plist に無いと、マイクにアクセスした瞬間に macOS がアプリを強制終了する
@Test func microphoneUsageDescriptionExists() {
    let text = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
    #expect(text?.isEmpty == false)
}
