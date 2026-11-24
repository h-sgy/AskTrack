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

    @Test func readsSessionsSavedBeforeNewFieldsExisted() throws {
        // pausedSeconds と evidenceIndices がない、以前の形式のファイル
        let old = #"""
        {"id":"33333333-3333-3333-3333-333333333333","listTitle":"旧形式","startedAt":"2026-11-24T00:00:00Z",
         "questions":[{"id":"44444444-4444-4444-4444-444444444444","text":"予算は？"}],
         "segments":[{"start":3,"text":"予算は"}],
         "checks":[{"questionID":"44444444-4444-4444-4444-444444444444","checked":true,"at":"2026-11-24T00:01:00Z","evidence":"予算は","manual":false}]}
        """#
        let dir = store.root.appending(path: "sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(old.utf8).write(to: dir.appending(path: "old.json"))
        let session = try #require(store.loadSessions().first)
        #expect(session.pausedSeconds == nil)
        #expect(session.checks.first?.evidenceIndices == nil)
        #expect(session.recordedDuration(until: session.startedAt.addingTimeInterval(90)) == 90)
    }

    @Test func recordedDurationExcludesPauses() {
        var session = Session(listTitle: "t", startedAt: Date(timeIntervalSince1970: 0), questions: [])
        session.pausedSeconds = 30
        #expect(session.recordedDuration(until: Date(timeIntervalSince1970: 100)) == 70)
    }

    @Test func unreadableFileIsSkippedNotDeleted() throws {
        try store.save(QuestionList(title: "A", questions: []))
        let broken = store.root.appending(path: "lists/broken.json")
        try Data("{".utf8).write(to: broken)
        #expect(store.loadLists().count == 1)
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }
}
