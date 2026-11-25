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

    /// 新しい確定セグメントがないとき、認識中の文と一緒に送る文脈（最後の overlap 秒）
    func recentRange(in segments: [Segment]) -> Range<Int> {
        guard let last = segments.last else { return 0..<0 }
        return (segments.firstIndex { $0.start >= last.start - overlap } ?? segments.count)..<segments.count
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
    private let volatile: () -> String
    private var lastVolatile = ""
    private let apply: ([Check]) -> Void
    private var schedule = CheckSchedule()
    private var progress: JudgeProgress
    private var timer: Task<Void, Never>?
    private var current: Task<Void, Never>?
    private var finished = false

    /// - Parameters:
    ///   - session: 判定時点のセッションを返す
    ///   - volatile: 認識中（未確定）の文を返す。確定を待たずに判定するため
    ///   - apply: 検証を通ったチェックを書き込む
    init(client: any LLMClient, overlap: TimeInterval, limit: TimeInterval, minInterval: TimeInterval = 15,
         session: @escaping () -> Session, volatile: @escaping () -> String = { "" },
         apply: @escaping ([Check]) -> Void) {
        self.client = client
        self.session = session
        self.volatile = volatile
        self.apply = apply
        progress = JudgeProgress(overlap: overlap, limit: limit)
        schedule.minInterval = minInterval
    }

    /// 確定セグメントか認識中の文が届いた
    func transcriptChanged() {
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
        let volatile = finished ? "" : volatile()   // 止めたあとは確定セグメントだけ
        guard snapshot.questions.contains(where: { !snapshot.blockedQuestionIDs.contains($0.id) }) else { return }
        let range: Range<Int>
        if let next = progress.nextRange(in: snapshot.segments) {
            range = next
        } else if !volatile.isEmpty, volatile != lastVolatile {
            range = progress.recentRange(in: snapshot.segments)   // 新しい確定はないが、話している途中の文が伸びた
        } else {
            return
        }

        let request = JudgeRequest(questions: snapshot.questions, segments: snapshot.segments, range: range,
                                   volatile: volatile)
        do {
            let matches = try await client.findAsked(questions: request.questions, transcript: request.transcript)
            apply(request.accept(matches, blocked: session().blockedQuestionIDs, at: .now))   // 反映時点の状態で検証する
            progress.succeeded(range)
            lastVolatile = volatile
            lastError = nil
            backlog = range.upperBound < snapshot.segments.count   // 上限で区切った残りがある
        } catch {
            let llmError = error as? LLMError ?? .transient(error.localizedDescription)
            progress.failed(range, llmError)
            lastError = llmError
        }
    }
}
