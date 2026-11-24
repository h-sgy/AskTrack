import Foundation
import Observation

/// 録音 1 回ぶんの状態。マイク → 文字起こしをつなぐ
@Observable
final class SessionModel {
    enum State { case idle, preparing, recording }

    private(set) var state = State.idle
    private(set) var level: Float = 0
    private(set) var volatileText = ""
    private(set) var segments: [Segment] = []
    private(set) var message: String?

    private var capture: AudioCapture?

    func start() {
        guard state == .idle else { return }
        state = .preparing
        Task {
            defer { state = .idle; level = 0 }
            guard await AudioCapture.requestPermission() else {
                message = "マイクの使用が許可されていません。システム設定 > プライバシーとセキュリティ > マイク で AskTrack を許可してください。"
                return
            }
            do {
                message = "音声認識を準備中…"
                let transcriber = try await Transcriber.make { _ in self.message = "音声認識モデルをダウンロード中…（初回のみ）" }
                let capture = AudioCapture()
                let input = try capture.start(format: transcriber.audioFormat) { level in
                    Task { @MainActor in self.level = level }
                }
                self.capture = capture
                state = .recording
                message = nil
                for try await event in transcriber.transcribe(input) {
                    switch event {
                    case .volatile(let text):
                        volatileText = text
                    case .final(let segment):
                        segments.append(segment)
                        volatileText = ""
                    }
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// マイクを止める。認識途中の音声は確定させてから終わる
    func stop() {
        capture?.stop()
        capture = nil
    }
}
