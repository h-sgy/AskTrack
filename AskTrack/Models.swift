import Foundation

struct Question: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
}

struct QuestionList: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var questions: [Question]
}

/// 確定した文字起こしの 1 区切り。start は録音開始からの秒数。
/// セッション内の配列の添字 + 1 がセグメント ID（s1, s2, …）
struct Segment: Codable, Equatable, Sendable {
    var start: TimeInterval
    var text: String
}

/// 質問ごとのチェック状態（1 質問につき最新の 1 件）
struct Check: Codable, Equatable, Sendable {
    var questionID: UUID
    var checked: Bool       // false は「手動で外した」。そのセッションでは自動判定の対象外になる
    var at: Date
    var evidence: String?   // 自動チェックの根拠セグメントの本文
    var manual: Bool
    var evidenceIndices: [Int]? = nil   // 根拠セグメントの添字（時刻の表示と、文字起こしの強調に使う）
}

struct Session: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var listTitle: String
    var startedAt: Date
    var endedAt: Date?          // nil のまま残っていたら、録音中に落ちたセッション
    var questions: [Question]   // 開始時点のスナップショット（後でリストを編集しても壊れない）
    var segments: [Segment] = []
    var checks: [Check] = []

    /// 自動判定に回さない質問（チェック済み、または手動で外したもの）
    var blockedQuestionIDs: Set<UUID> { Set(checks.map(\.questionID)) }

    mutating func upsert(_ check: Check) {
        checks.removeAll { $0.questionID == check.questionID }
        checks.append(check)
    }
}
