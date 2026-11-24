import Foundation
import os

/// 質問リストとセッションを JSON ファイルで保存する
struct Store {
    let root: URL

    static let shared = Store(root: .applicationSupportDirectory.appending(path: "AskTrack"))

    private var listsDir: URL { root.appending(path: "lists") }
    private var sessionsDir: URL { root.appending(path: "sessions") }

    func save(_ list: QuestionList) throws {
        try write(list, to: listsDir.appending(path: "\(list.id).json"))
    }

    func loadLists() -> [QuestionList] {
        loadAll(QuestionList.self, in: listsDir).sorted { $0.title < $1.title }
    }

    func delete(_ list: QuestionList) throws {
        try FileManager.default.removeItem(at: listsDir.appending(path: "\(list.id).json"))
    }

    /// 録音中は確定セグメントやチェックが変わるたびに呼ぶ。書き込みはアトミック（途中で落ちても壊れない）
    func save(_ session: Session) throws {
        try write(session, to: sessionsDir.appending(path: Self.fileName(for: session)))
    }

    /// 新しい順
    func loadSessions() -> [Session] {
        loadAll(Session.self, in: sessionsDir).sorted { $0.startedAt > $1.startedAt }
    }

    static func fileName(for session: Session) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "\(formatter.string(from: session.startedAt))-\(session.id).json"
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// 読めないファイルは飛ばす（消さない。手で直せるように残す）
    private func loadAll<T: Decodable>(_ type: T.Type, in dir: URL) -> [T] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                return try decoder.decode(T.self, from: Data(contentsOf: url))
            } catch {
                Logger().error("読み込めないファイルを飛ばしました: \(url.lastPathComponent, privacy: .public) \(error)")
                return nil
            }
        }
    }
}
