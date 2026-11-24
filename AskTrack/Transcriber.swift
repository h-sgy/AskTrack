import AVFoundation
import Speech

enum TranscriptEvent: Sendable, Equatable {
    case volatile(String)   // 認識中（あとで書き換わる）
    case final(Segment)     // 確定
}

/// SpeechAnalyzer + SpeechTranscriber のラッパー。録音 1 回ごとに作り直す
final class Transcriber {
    /// 入力音声はこの形式に変換して渡す
    let audioFormat: AVAudioFormat
    private let module: SpeechTranscriber
    private let analyzer: SpeechAnalyzer

    private init(module: SpeechTranscriber, audioFormat: AVAudioFormat) {
        self.module = module
        self.audioFormat = audioFormat
        analyzer = SpeechAnalyzer(modules: [module])
    }

    /// 音声認識モデルが未インストールならダウンロードしてから作る
    static func make(locale: Locale = Locale(identifier: "ja-JP"),
                     onDownload: (Progress) -> Void = { _ in }) async throws -> Transcriber {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriberError.unsupportedLocale(locale)
        }
        let module = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                       reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            onDownload(request.progress)
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriberError.noAudioFormat
        }
        return Transcriber(module: module, audioFormat: format)
    }

    /// 固有名詞や専門用語を渡して、認識されやすくする
    func setHints(_ words: [String]) async throws {
        let context = AnalysisContext()
        context.contextualStrings[.general] = words
        try await analyzer.setContext(context)
    }

    /// ここまでの音声を確定させる（一時停止したとき、話しかけの途中を判定に回すため）
    func finalizeNow() async {
        try? await analyzer.finalize(through: nil)
    }

    /// 入力を流し、暫定・確定の結果を返す。入力が終わると、残りを確定させてから終わる
    func transcribe<Input: AsyncSequence & Sendable>(_ input: Input) -> AsyncThrowingStream<TranscriptEvent, Error>
    where Input.Element == AnalyzerInput {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let feed = Task {
                        if let end = try await analyzer.analyzeSequence(input) {
                            try await analyzer.finalizeAndFinish(through: end)
                        } else {
                            await analyzer.cancelAndFinishNow()
                        }
                    }
                    for try await result in module.results {
                        let text = String(result.text.characters)
                        continuation.yield(result.isFinal
                            ? .final(Segment(start: result.range.start.seconds, text: text))
                            : .volatile(text))
                    }
                    try await feed.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum TranscriberError: LocalizedError {
    case unsupportedLocale(Locale)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "この Mac は \(locale.identifier) の音声認識に対応していません。"
        case .noAudioFormat: "音声認識で使える音声形式が見つかりません。"
        }
    }
}
