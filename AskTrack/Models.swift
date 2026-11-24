import Foundation

/// 確定した文字起こしの 1 区切り。start は録音開始からの秒数
struct Segment: Codable, Equatable, Sendable {
    var start: TimeInterval
    var text: String
}
