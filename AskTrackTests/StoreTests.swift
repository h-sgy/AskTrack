import Foundation
import Testing
@testable import AskTrack

struct StoreTests {
    let store = Store(root: FileManager.default.temporaryDirectory.appending(path: "asktrack-store-\(UUID())"))

    @Test func listRoundTrip() throws {
        let list = QuestionList(title: "顧客ヒアリング", questions: [Question(text: "予算は？"), Question(text: "決裁者は？")])
        try store.save(list)
        #expect(store.loadLists() == [list])
        try store.delete(list)
        #expect(store.loadLists().isEmpty)
    }

    @Test func sessionRoundTripAndInterruptedDetection() throws {
        let question = Question(text: "予算は？")
        var session = Session(listTitle: "顧客ヒアリング", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                              questions: [question])
        session.segments = [Segment(start: 3, text: "予算はどのくらいですか")]
        session.upsert(Check(questionID: question.id, checked: true, at: session.startedAt, evidence: "予算はどのくらいですか", manual: false))
        try store.save(session)   // 録音中の逐次保存（endedAt はまだ nil）

        let loaded = store.loadSessions()
        #expect(loaded == [session])
        #expect(loaded.first?.endedAt == nil, "endedAt が nil のまま読めれば「中断」と表示できる")

        session.endedAt = session.startedAt.addingTimeInterval(60)
        try store.save(session)   // 同じファイルが上書きされる
        #expect(store.loadSessions() == [session])
    }

    @Test func unreadableFileIsSkippedNotDeleted() throws {
        try store.save(QuestionList(title: "A", questions: []))
        let broken = store.root.appending(path: "lists/broken.json")
        try Data("{".utf8).write(to: broken)
        #expect(store.loadLists().count == 1)
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }
}
