import Foundation
import Observation

/// 録音 1 回ぶん。マイク → 文字起こし → 判定 → 逐次保存をつなぐ
@Observable
final class SessionModel {
    enum State { case idle, preparing, recording, finishing, finished }

    private(set) var state = State.idle
    private(set) var session: Session
    private(set) var level: Float = 0
    private(set) var volatileText = ""
    private(set) var message: String?
    private(set) var judgeLabel: String?
    private(set) var judgeNotice: String?
    private(set) var skipped: [Range<Int>] = []
    private(set) var judgeError: LLMError?

    var isActive: Bool { state != .idle && state != .finished }

    private var capture: AudioCapture?
    private var checker: QuestionChecker?
    private let settings: JudgeSettings
    private let store: Store
    private let onFinish: (Session) -> Void

    init(session: Session, settings: JudgeSettings, store: Store, onFinish: @escaping (Session) -> Void) {
        self.session = session
        self.settings = settings
        self.store = store
        self.onFinish = onFinish
    }

    func start() {
        guard state == .idle else { return }
        state = .preparing
        Task { await run() }
    }

    /// マイクを止める。認識途中の音声を確定させ、未判定の残りを判定してから終わる
    func stop() {
        capture?.stop()
        capture = nil
    }

    /// 手動でチェックを付ける / 外す。外した質問は、このセッションでは自動判定の対象外になる
    func toggle(_ question: Question) {
        let checked = session.checks.first { $0.questionID == question.id }?.checked == true
        session.upsert(Check(questionID: question.id, checked: !checked, at: .now, evidence: nil, manual: true))
        save()
    }

    private func run() async {
        guard await AudioCapture.requestPermission() else {
            message = "マイクの使用が許可されていません。システム設定 > プライバシーとセキュリティ > マイク で AskTrack を許可してください。"
            return end()
        }
        if let judge = settings.resolve() {
            judgeLabel = judge.label
            judgeNotice = judge.notice
            // 判定が終わるまで互いを参照する。end() で checker を外して循環を切る
            checker = QuestionChecker(client: judge.client, overlap: judge.provider.overlap, limit: judge.provider.limit,
                                      minInterval: settings.minInterval,
                                      session: { self.session }, apply: { self.apply($0) })
        } else {
            judgeNotice = "判定に使える LLM がありません。設定で API キーを入れるか、Apple Intelligence を有効にしてください。文字起こしだけ行います。"
        }
        do {
            message = "音声認識を準備中…"
            let transcriber = try await Transcriber.make { _ in self.message = "音声認識モデルをダウンロード中…（初回のみ）" }
            try? await transcriber.setHints(session.questions.map(\.text))   // 効かなくても文字起こしは続ける
            let capture = AudioCapture()
            let input = try capture.start(format: transcriber.audioFormat) { level in
                Task { @MainActor in self.level = level }
            }
            self.capture = capture
            state = .recording
            message = nil
            save()
            for try await event in transcriber.transcribe(input) {
                switch event {
                case .volatile(let text):
                    volatileText = text
                case .final(let segment):
                    session.segments.append(segment)
                    volatileText = ""
                    save()
                    checker?.segmentArrived()
                    refreshJudgeStatus()
                }
            }
        } catch {
            message = error.localizedDescription
        }
        state = .finishing
        await checker?.finish()
        refreshJudgeStatus()
        end()
    }

    private func end() {
        capture?.stop()
        capture = nil
        checker = nil
        level = 0
        session.endedAt = .now
        save()
        state = .finished
        onFinish(session)
    }

    private func apply(_ checks: [Check]) {
        guard !checks.isEmpty else { return }
        checks.forEach { session.upsert($0) }
        save()
        refreshJudgeStatus()
    }

    private func refreshJudgeStatus() {
        guard let checker else { return }
        skipped = checker.skipped
        judgeError = checker.lastError
    }

    private func save() {
        do {
            try store.save(session)
        } catch {
            message = "セッションを保存できませんでした: \(error.localizedDescription)"
        }
    }
}
