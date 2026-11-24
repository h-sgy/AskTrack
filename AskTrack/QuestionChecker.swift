import Foundation
import Observation

/// いつ判定を走らせるか（設計書 5.1）。時刻を引数で受け取る純粋な状態機械
struct CheckSchedule {
    var debounce: TimeInterval = 5
    var minInterval: TimeInterval = 15
    private(set) var scheduledAt: Date?
    private(set) var running = false
    private var lastRun: Date?
    private var pending = false

    /// 確定セグメントが来た。新たに予約した実行時刻を返す（予約済み・実行中なら nil）
    mutating func segmentArrived(at now: Date) -> Date? {
        if running {
            pending = true   // 実行中は並列にせず、終わってから 1 回だけ再実行
            return nil
        }
        guard scheduledAt == nil else { return nil }   // 予約済みなら延ばさない（話し続けても判定が止まらない）
        let at = max(now + debounce, (lastRun ?? .distantPast) + minInterval)
        scheduledAt = at
        return at
    }

    mutating func started(at now: Date) {
        scheduledAt = nil
        running = true
        lastRun = now
        pending = false
    }

    /// 判定が終わった。backlog は「上限で区切った残りがある」。次の実行時刻を返す
    mutating func finished(at now: Date, backlog: Bool) -> Date? {
        running = false
        guard backlog || pending else { return nil }
        pending = false
        let at = backlog ? now : max(now, (lastRun ?? now) + minInterval)
        scheduledAt = at
        return at
    }
}

/// どこまで判定したか（設計書 5.2）
struct JudgeProgress {
    var overlap: TimeInterval
    var limit: TimeInterval
    private(set) var judgedUntil = 0          // この添字より前のセグメントは判定済み
    private(set) var skipped: [Range<Int>] = []
    private var failure: (lower: Int, count: Int)?

    init(overlap: TimeInterval, limit: TimeInterval) {
        self.overlap = overlap
        self.limit = limit
    }

    /// 次に送る範囲。未判定のセグメントがなければ nil
    func nextRange(in segments: [Segment]) -> Range<Int>? {
        guard judgedUntil < segments.count else { return nil }
        let firstNew = segments[judgedUntil].start
        let lower = segments[..<judgedUntil].firstIndex { $0.start >= firstNew - overlap } ?? judgedUntil
        var upper = lower
        while upper < segments.count, segments[upper].start < segments[lower].start + limit { upper += 1 }
        return lower..<max(upper, judgedUntil + 1)
    }

    mutating func succeeded(_ range: Range<Int>) {
        judgedUntil = max(judgedUntil, range.upperBound)
        failure = nil
    }

    /// 失敗したら進めない。ただし同じ範囲で拒否・解析失敗が 2 回続いたら飛ばす（永久に詰まらないように）
    mutating func failed(_ range: Range<Int>, _ error: LLMError) {
        switch error {
        case .transient, .unauthorized, .badRequest:
            return
        case .refusal, .invalidResponse:
            let count = (failure?.lower == range.lowerBound ? failure?.count ?? 0 : 0) + 1
            if count >= 2 {
                skipped.append(range)
                judgedUntil = max(judgedUntil, range.upperBound)
                failure = nil
            } else {
                failure = (range.lowerBound, count)
            }
        }
    }
}

/// 確定セグメントを見て、LLM で質問チェックを走らせる
@Observable
final class QuestionChecker {
    private(set) var skipped: [Range<Int>] = []
    private(set) var lastError: LLMError?

    private let client: any LLMClient
    private let session: () -> Session
    private let apply: ([Check]) -> Void
    private var schedule = CheckSchedule()
    private var progress: JudgeProgress
    private var timer: Task<Void, Never>?
    private var current: Task<Void, Never>?
    private var finished = false

    /// - Parameters:
    ///   - session: 判定時点のセッションを返す
    ///   - apply: 検証を通ったチェックを書き込む
    init(client: any LLMClient, overlap: TimeInterval, limit: TimeInterval,
         session: @escaping () -> Session, apply: @escaping ([Check]) -> Void) {
        self.client = client
        self.session = session
        self.apply = apply
        progress = JudgeProgress(overlap: overlap, limit: limit)
    }

    func segmentArrived() {
        guard !finished, lastError?.isFatal != true else { return }   // キーや設定が無効なら呼び続けない
        if let at = schedule.segmentArrived(at: .now) { fire(at: at) }
    }

    /// 録音を止めたとき。予約を取り消し、未判定の残りを判定し切ってから終わる（失敗したらそこで諦める）
    func finish() async {
        finished = true
        timer?.cancel()
        await current?.value
        while lastError?.isFatal != true, progress.nextRange(in: session().segments) != nil {
            let before = progress.judgedUntil
            await run()
            if progress.judgedUntil == before { break }
        }
    }

    private func fire(at date: Date) {
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            let run = Task { await self.run() }
            current = run
            await run.value
        }
    }

    private func run() async {
        schedule.started(at: .now)
        var backlog = false
        defer {
            skipped = progress.skipped
            if let at = schedule.finished(at: .now, backlog: backlog), !finished { fire(at: at) }
        }
        let snapshot = session()
        let unchecked = snapshot.questions.filter { !snapshot.blockedQuestionIDs.contains($0.id) }
        guard !unchecked.isEmpty, let range = progress.nextRange(in: snapshot.segments) else { return }

        let request = JudgeRequest(unchecked: unchecked, segments: snapshot.segments, range: range)
        do {
            let matches = try await client.findAsked(questions: request.questions, transcript: request.transcript)
            let now = session()   // 反映時点の状態で検証する
            apply(request.accept(matches, segments: now.segments, blocked: now.blockedQuestionIDs, at: .now))
            progress.succeeded(range)
            lastError = nil
            backlog = range.upperBound < snapshot.segments.count   // 上限で区切った残りがある
        } catch {
            let llmError = error as? LLMError ?? .transient(error.localizedDescription)
            progress.failed(range, llmError)
            lastError = llmError
        }
    }
}
