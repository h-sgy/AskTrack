import Foundation
import Testing
@testable import AskTrack

@Test func keychainSaveLoadDelete() throws {
    let account = "test-\(UUID())"
    defer { Keychain.delete(account: account) }
    try Keychain.save("dummy-key-1", account: account)
    #expect(Keychain.load(account: account) == "dummy-key-1")
    try Keychain.save("dummy-key-2", account: account)   // 上書き
    #expect(Keychain.load(account: account) == "dummy-key-2")
    #expect(Keychain.delete(account: account))
    #expect(Keychain.load(account: account) == nil)
    #expect(UserDefaults.standard.dictionaryRepresentation().values.contains { $0 as? String == "dummy-key-2" } == false)
}
