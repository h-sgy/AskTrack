import AVFoundation
import Speech

/// マイク音声を、SpeechAnalyzer がそのまま読める形式に変換して流す
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// - Parameters:
    ///   - format: 変換先（`Transcriber.audioFormat`）
    ///   - onLevel: 入力レベル（0〜1）。オーディオスレッドから呼ばれる
    func start(format: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) throws -> AsyncStream<AnalyzerInput> {
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: format) else {
            throw AudioCaptureError.unsupportedFormat
        }
        converter.primeMethod = .none  // 連続した入力なので、変換のたびに無音を足さない
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input.installTap(onBus: 0, bufferSize: 4096, format: source,
                         block: Self.tap(converter: converter, continuation: continuation, onLevel: onLevel))
        engine.prepare()
        try engine.start()
        self.continuation = continuation
        return stream
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    // タップはオーディオスレッドで呼ばれるので、MainActor から切り離した場所で作る。
    // MainActor のメソッド内で直接書くと、Swift 6 の実行時チェックで落ちる
    nonisolated private static func tap(
        converter: AVAudioConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            onLevel(level(of: buffer))
            if let converted = convert(buffer, with: converter) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    /// 二乗平均平方根を 0〜1 に丸めた値。メーター表示用
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        // ponytail: 話し声がメーターの中ほどに来るよう 5 倍しているだけ。実機で見て調整する
        return min(1, (sum / Float(count)).squareRoot() * 5)
    }
}

enum AudioCaptureError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "マイクの音声形式を、音声認識の形式に変換できません。"
        }
    }
}
