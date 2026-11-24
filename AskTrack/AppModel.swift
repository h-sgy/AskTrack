import Foundation
import Observation

/// 質問リスト・過去のセッション・録音中のセッションを持つ
@Observable
final class AppModel {
    enum Selection: Hashable {
        case list(UUID)
        case session(UUID)
        case settings
    }

    private var beforeSettings: Selection?

    /// 同じウィンドウの中で設定画面を開く（⌘, もここに来る）
    func showSettings() {
        if selection != .settings { beforeSettings = selection }
        selection = .settings
    }

    func closeSettings() {
        selection = beforeSettings ?? lists.first.map { .list($0.id) }
    }

    let settings = JudgeSettings()
    private(set) var lists: [QuestionList]
    private(set) var sessions: [Session]
    var selection: Selection?
    /// 直近に録音したセッション（終わった後も、メッセージを見せるために残す）
    private(set) var live: SessionModel?
    var errorMessage: String?

    private let store: Store

    init(store: Store = .shared) {
        self.store = store
        lists = store.loadLists()
        sessions = store.loadSessions()
        selection = lists.first.map { .list($0.id) }
    }

    var isRecording: Bool { live?.isActive == true }

    func addList() {
        let list = QuestionList(title: "新しい質問リスト", questions: [])
        lists.append(list)
        save(list)
        selection = .list(list.id)
    }

    func save(_ list: QuestionList) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) { lists[index] = list }
        do { try store.save(list) } catch { errorMessage = "質問リストを保存できませんでした: \(error.localizedDescription)" }
    }

    func delete(_ list: QuestionList) {
        do { try store.delete(list) } catch { errorMessage = error.localizedDescription }
        lists.removeAll { $0.id == list.id }
        if selection == .list(list.id) { selection = nil }
    }

    func delete(_ session: Session) {
        guard live?.session.id != session.id || !isRecording else { return }
        do { try store.delete(session) } catch { errorMessage = error.localizedDescription }
        sessions.removeAll { $0.id == session.id }
        if selection == .session(session.id) { selection = nil }
    }

    func startSession(with list: QuestionList) {
        let questions = list.questions.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !isRecording, !questions.isEmpty else { return }
        let session = Session(listTitle: list.title, startedAt: .now, questions: questions)
        let model = SessionModel(session: session, settings: settings, store: store) { [weak self] finished in
            self?.update(finished)
        }
        live = model
        sessions.insert(session, at: 0)
        selection = .session(session.id)
        model.start()
    }

    /// 表示用。録音中のセッションは最新の状態を返す
    func session(id: UUID) -> Session? {
        if let live, live.session.id == id { return live.session }
        return sessions.first { $0.id == id }
    }

    private func update(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
    }
}
