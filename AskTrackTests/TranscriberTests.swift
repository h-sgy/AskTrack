import AVFoundation
import Foundation
import Speech
import Testing
@testable import AskTrack

// 読み上げ音声（say コマンド）を、マイクと同じ変換処理を通して文字起こしする。
// 初回は日本語の音声認識モデルのダウンロードが走るので時間がかかる
@Test(.timeLimit(.minutes(5)))
func transcribesJapaneseSpeechThroughCaptureConversion() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "asktrack-tts-\(UUID()).aiff")
    defer { try? FileManager.default.removeItem(at: file) }
    let say = try Process.run(URL(filePath: "/usr/bin/say"),
                              arguments: ["-v", "Kyoko", "-o", file.path,
                                          "では最初に、現在の業務フローを教えていただけますか。次に、今年度の予算はどのくらいですか。"])
    say.waitUntilExit()
    #expect(say.terminationStatus == 0)

    let transcriber = try await Transcriber.make()
    let input = try fileInput(file, format: transcriber.audioFormat)

    var finals: [Segment] = []
    for try await event in transcriber.transcribe(input) {
        if case .final(let segment) = event { finals.append(segment) }
    }

    let text = finals.map(\.text).joined()
    #expect(text.contains("業務"), "認識結果: \(text)")
    #expect(text.contains("予算"), "認識結果: \(text)")
    #expect(finals.map(\.start) == finals.map(\.start).sorted(), "時刻が順に並んでいない")
}

/// 音声ファイルを 4096 フレームずつ読み、AudioCapture.convert で変換して流す
private func fileInput(_ url: URL, format: AVAudioFormat) throws -> AsyncStream<AnalyzerInput> {
    let file = try AVAudioFile(forReading: url)
    let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))
    converter.primeMethod = .none
    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    while let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
          (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 {
        if let converted = AudioCapture.convert(buffer, with: converter) {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
    continuation.finish()
    return stream
}
