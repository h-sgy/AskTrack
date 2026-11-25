import Foundation
import Testing
@testable import AskTrack

struct JudgeRequestTests {
    let budget = Question(text: "予算は？")
    let owner = Question(text: "決裁者は？")
    let segments = [
        Segment(start: 0, text: "よろしくお願いします"),
        Segment(start: 65, text: "予算はどのくらいですか"),
        Segment(start: 70, text: "五百万円くらいです"),
    ]
    var request: JudgeRequest { JudgeRequest(questions: [budget, owner], segments: segments, range: 1..<3) }

    @Test func formatsShortIDsAndTimestamps() {
        #expect(request.questions == [PromptQuestion(key: "q1", text: "予算は？"), PromptQuestion(key: "q2", text: "決裁者は？")])
        #expect(request.transcript == "[s2 01:05] 予算はどのくらいですか\n[s3 01:10] 五百万円くらいです")
    }

    @Test func acceptsValidMatchWithEvidence() {
        let checks = request.accept([AskedMatch(id: "q1", segments: ["s3", "s2"])], blocked: [], at: .now)
        #expect(checks.count == 1)
        #expect(checks.first?.questionID == budget.id)
        #expect(checks.first?.evidence == "予算はどのくらいですか 五百万円くらいです")
        #expect(checks.first?.evidenceIndices == [1, 2])
        #expect(checks.first?.manual == false)
    }

    @Test func appendsVolatileLineAndAcceptsItAsEvidence() {
        let request = JudgeRequest(questions: [budget, owner], segments: segments, range: 1..<3, volatile: "決裁者はどなたで")
        #expect(request.transcript.hasSuffix("[s3 01:10] 五百万円くらいです\n[s4 認識中] 決裁者はどなたで"))
        let checks = request.accept([AskedMatch(id: "q2", segments: ["s4"])], blocked: [], at: .now)
        #expect(checks.first?.evidence == "決裁者はどなたで")
        #expect(checks.first?.evidenceIndices == [3])   // 確定すると添字 3 のセグメントになる
    }

    @Test func skipsVolatileWhenRangeStopsBeforeTheLatestSegment() {
        // 上限で区切った途中の範囲には、離れた認識中の文を付けない
        let request = JudgeRequest(questions: [budget], segments: segments, range: 0..<2, volatile: "決裁者は")
        #expect(!request.transcript.contains("認識中"))
        #expect(request.accept([AskedMatch(id: "q1", segments: ["s3"])], blocked: [], at: .now).isEmpty)
    }

    @Test func dropsUnknownQuestionID() {
        #expect(request.accept([AskedMatch(id: "q9", segments: ["s2"])], blocked: [], at: .now).isEmpty)
    }

    @Test func dropsSegmentsOutsideTheSentRange() {
        // s1 は送っていない（範囲 1..<3 = s2, s3）
        #expect(request.accept([AskedMatch(id: "q1", segments: ["s1"])], blocked: [], at: .now).isEmpty)
        #expect(request.accept([AskedMatch(id: "q1", segments: ["s2", "s99"])], blocked: [], at: .now).isEmpty)
    }

    @Test func dropsMalformedOrMissingSegmentIDs() {
        #expect(request.accept([AskedMatch(id: "q1", segments: ["2"])], blocked: [], at: .now).isEmpty)
        #expect(request.accept([AskedMatch(id: "q1", segments: [])], blocked: [], at: .now).isEmpty)
    }

    @Test func dropsQuestionsBlockedAtApplyTime() {
        // 判定中にユーザーが手動で外した（または既にチェックされた）質問は付け直さない
        let checks = request.accept([AskedMatch(id: "q1", segments: ["s2"]), AskedMatch(id: "q2", segments: ["s2"])],
                                    blocked: [budget.id], at: .now)
        #expect(checks.map(\.questionID) == [owner.id])
    }

    @Test func ignoresDuplicateMatches() {
        let checks = request.accept([AskedMatch(id: "q1", segments: ["s2"]), AskedMatch(id: "q1", segments: ["s3"])],
                                    blocked: [], at: .now)
        #expect(checks.count == 1)
    }
}
