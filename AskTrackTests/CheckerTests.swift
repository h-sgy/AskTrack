import Foundation
import Testing
@testable import AskTrack

struct CheckScheduleTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func firstRunWaitsForDebounce() {
        var schedule = CheckSchedule()
        #expect(schedule.segmentArrived(at: t0) == t0 + 5)
    }

    @Test func keepsMinimumIntervalBetweenRuns() {
        var schedule = CheckSchedule()
        schedule.started(at: t0)
        #expect(schedule.finished(at: t0 + 2, backlog: false) == nil)
        #expect(schedule.segmentArrived(at: t0 + 3) == t0 + 15)
    }

    @Test func doesNotPostponeWhenAlreadyScheduled() {
        // 話し続けてセグメントが次々来ても、判定が先送りされ続けない
        var schedule = CheckSchedule()
        #expect(schedule.segmentArrived(at: t0) == t0 + 5)
        #expect(schedule.segmentArrived(at: t0 + 3) == nil)
        #expect(schedule.scheduledAt == t0 + 5)
    }

    @Test func segmentsDuringRunTriggerExactlyOneRerun() {
        var schedule = CheckSchedule()
        schedule.started(at: t0)
        #expect(schedule.segmentArrived(at: t0 + 1) == nil)   // 並列にしない
        #expect(schedule.segmentArrived(at: t0 + 2) == nil)
        #expect(schedule.finished(at: t0 + 4, backlog: false) == t0 + 15)
        schedule.started(at: t0 + 15)
        #expect(schedule.finished(at: t0 + 18, backlog: false) == nil)
    }

    @Test func backlogRunsImmediately() {
        var schedule = CheckSchedule()
        schedule.started(at: t0)
        #expect(schedule.finished(at: t0 + 4, backlog: true) == t0 + 4)
    }
}

struct JudgeProgressTests {
    /// 10 秒おきのセグメント
    let segments = (0..<60).map { Segment(start: TimeInterval($0 * 10), text: "s\($0 + 1)") }

    @Test func firstRangeStartsAtZeroAndIsCappedByLimit() {
        let progress = JudgeProgress(overlap: 60, limit: 180)
        #expect(progress.nextRange(in: segments) == 0..<18)   // 0〜170 秒
    }

    @Test func nextRangeOverlapsPreviousAndOnlySucceedsAdvance() {
        var progress = JudgeProgress(overlap: 60, limit: 180)
        progress.succeeded(0..<18)
        #expect(progress.nextRange(in: segments) == 12..<30)  // 180 秒の 60 秒前（120 秒 = 添字 12）から
        progress.failed(12..<30, .transient("503"))
        #expect(progress.judgedUntil == 18, "失敗したら進めない（その間の発言は次の判定で見る）")
    }

    @Test func noRangeWhenEverythingIsJudged() {
        var progress = JudgeProgress(overlap: 60, limit: 600)
        progress.succeeded(0..<60)
        #expect(progress.nextRange(in: segments) == nil)
    }

    @Test func skipsRangeAfterTwoRefusalsInARow() {
        var progress = JudgeProgress(overlap: 60, limit: 180)
        progress.failed(0..<18, .refusal)
        #expect(progress.judgedUntil == 0)
        progress.failed(0..<18, .invalidResponse("not json"))
        #expect(progress.judgedUntil == 18)
        #expect(progress.skipped == [0..<18])
    }

    @Test func successResetsFailureCount() {
        var progress = JudgeProgress(overlap: 60, limit: 180)
        progress.failed(0..<18, .refusal)
        progress.succeeded(0..<18)
        progress.failed(12..<30, .refusal)
        #expect(progress.judgedUntil == 18)
        #expect(progress.skipped.isEmpty)
    }
}

struct FakeLLM: LLMClient {
    let result: Result<[AskedMatch], LLMError>
    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch] {
        try result.get()
    }
}

@Test func finishJudgesRemainingSegmentsAndAppliesChecks() async {
    let question = Question(text: "予算は？")
    var session = Session(listTitle: "t", startedAt: .now, questions: [question])
    session.segments = [Segment(start: 1, text: "予算はどのくらいですか")]
    let checker = QuestionChecker(client: FakeLLM(result: .success([AskedMatch(id: "q1", segments: ["s1"])])),
                                  overlap: 60, limit: 180,
                                  session: { session }, apply: { $0.forEach { session.upsert($0) } })
    await checker.finish()
    #expect(session.checks.map(\.questionID) == [question.id])
    #expect(session.checks.first?.evidence == "予算はどのくらいですか")
}

@Test func unauthorizedStopsJudging() async {
    var session = Session(listTitle: "t", startedAt: .now, questions: [Question(text: "予算は？")])
    session.segments = [Segment(start: 1, text: "予算は")]
    let checker = QuestionChecker(client: FakeLLM(result: .failure(.unauthorized)), overlap: 60, limit: 180,
                                  session: { session }, apply: { _ in })
    await checker.finish()
    #expect(checker.lastError == .unauthorized)
}
