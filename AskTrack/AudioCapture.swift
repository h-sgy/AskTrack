import AVFoundation
import Speech

/// マイク音声を、SpeechAnalyzer がそのまま読める形式に変換して流す。
/// 使うマイクは macOS の「サウンド > 入力」で選ばれているもの。録音中にそれが変わったり
/// （AirPods の接続・切断など）オーディオの構成が変わったりしたら、流れを閉じずにエンジンを作り直してつなぎ直す。
///
/// アプリの中でマイクを指定する（AUHAL に kAudioOutputUnitProperty_CurrentDevice を設定する）方式は、
/// 実機で内蔵マイクの音声が届かなくなったり、エンジンの起動が固まったりしたので使わない
final class AudioCapture {
    private var engine = AVAudioEngine()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var configurationObserver: NSObjectProtocol?
    private var deviceObserver: AudioDeviceObserver?
    private var paused = false
    private(set) var currentDevice: InputDevice?
    /// つなぎ直したときなどに、画面に出すメッセージ
    var onNotice: ((String) -> Void)?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// - Parameters:
    ///   - format: 変換先（`Transcriber.audioFormat`）
    ///   - onLevel: 入力レベル（0〜1）。オーディオスレッドから呼ばれる
    func start(format: AVAudioFormat, onLevel: @escaping @Sendable (Float) -> Void) throws -> AsyncStream<AnalyzerInput> {
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.format = format
        self.onLevel = onLevel
        self.continuation = continuation
        do {
            try connect()
        } catch {
            stop()
            throw error
        }
        // 構成が変わると、エンジンは自分で止まってからこの通知を出す
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let sender = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                // 作り直す前の古いエンジンからの通知や、つなぎ直し済みのものは無視する
                guard let self, sender == ObjectIdentifier(self.engine), !self.engine.isRunning, !self.paused else { return }
                self.reconnect()
            }
        }
        // 既定の入力が変わった（AVAudioEngine は動いている間、既定の入力の変更に追従しない）
        deviceObserver = AudioDeviceObserver { [weak self] in
            guard let self, AudioDevices.defaultInput()?.uid != self.currentDevice?.uid else { return }
            self.reconnect()
        }
        return stream
    }

    /// マイクを止める（ハードウェアも止まる）。流れは閉じないので、resume() で続きから流せる
    func pause() {
        paused = true
        engine.pause()
    }

    func resume() throws {
        paused = false
        if AudioDevices.defaultInput()?.uid != currentDevice?.uid {
            reconnect()   // 一時停止中にマイクが変わっていた
        } else {
            try engine.start()
        }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        deviceObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    /// 今の既定の入力で、新しいエンジンにタップを付けて動かす
    private func connect() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()   // 作り直すと、その時点の既定の入力を使う
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0 else { throw AudioCaptureError.noInput }
        guard let format, let continuation, let onLevel,
              let converter = AVAudioConverter(from: source, to: format) else {
            throw AudioCaptureError.unsupportedFormat
        }
        converter.primeMethod = .none  // 連続した入力なので、変換のたびに無音を足さない
        input.installTap(onBus: 0, bufferSize: 4096, format: source,
                         block: Self.tap(converter: converter, continuation: continuation, onLevel: onLevel))
        engine.prepare()
        if !paused { try engine.start() }
        currentDevice = AudioDevices.defaultInput()
    }

    /// 録音を続けたまま、つなぎ直す
    func reconnect() {
        guard continuation != nil else { return }   // 止めた後
        let before = currentDevice
        do {
            try connect()
            if currentDevice?.uid != before?.uid {
                onNotice?("マイクが「\(currentDevice?.name ?? "不明")」に切り替わりました。録音は続いています。")
            } else {
                onNotice?("マイクの構成が変わったため、録音をつなぎ直しました。")
            }
        } catch {
            onNotice?("マイクをつなぎ直せませんでした: \(error.localizedDescription)")
        }
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
    case noInput

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "マイクの音声形式を、音声認識の形式に変換できません。"
        case .noInput: "使えるマイクが見つかりません。マイクの接続と、システム設定のサウンド > 入力を確認してください。"
        }
    }
}
