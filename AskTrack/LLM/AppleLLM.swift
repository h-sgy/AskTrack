import Foundation
import FoundationModels

/// Apple のオンデバイス LLM。外部に何も送らない（コンテキストは約 4K トークン）
struct AppleLLM: LLMClient {
    /// 使えない理由。使えるなら nil
    nonisolated static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "この Mac は Apple Intelligence に対応していません。"
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence がオフです。システム設定 > Apple Intelligence と Siri で有効にしてください。"
        case .unavailable(.modelNotReady): "Apple Intelligence のモデルを準備中です。しばらくしてから試してください。"
        case .unavailable: "Apple Intelligence を利用できません。"
        }
    }

    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch] {
        if let reason = Self.unavailableReason { throw LLMError.badRequest(reason) }
        // 会話がたまってコンテキストを超えないよう、判定のたびに新しく作る
        let session = LanguageModelSession(instructions: JudgePrompt.system)
        do {
            let response = try await session.respond(to: JudgePrompt.user(questions: questions, transcript: transcript),
                                                     generating: AppleAskedResponse.self)
            return response.content.asked.map { AskedMatch(id: $0.id, segments: $0.segments) }
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            if #available(macOS 27, *), let error = error as? LanguageModelError { throw Self.map(error) }
            throw LLMError.transient(error.localizedDescription)
        }
    }

    // macOS 26 のエラー（27 で非推奨）
    private static func map(_ error: LanguageModelSession.GenerationError) -> LLMError {
        switch error {
        case .guardrailViolation, .refusal: .refusal
        case .exceededContextWindowSize, .decodingFailure: .invalidResponse(error.localizedDescription)
        case .unsupportedGuide, .unsupportedLanguageOrLocale: .badRequest(error.localizedDescription)
        default: .transient(error.localizedDescription)   // rateLimited / concurrentRequests / assetsUnavailable
        }
    }

    // macOS 27 以降のエラー
    @available(macOS 27, *)
    private static func map(_ error: LanguageModelError) -> LLMError {
        switch error {
        case .guardrailViolation, .refusal: .refusal
        case .contextSizeExceeded: .invalidResponse(error.localizedDescription)
        case .unsupportedCapability, .unsupportedGenerationGuide, .unsupportedLanguageOrLocale, .unsupportedTranscriptContent:
            .badRequest(error.localizedDescription)
        default: .transient(error.localizedDescription)   // rateLimited / timeout
        }
    }
}

/// 5.3 のスキーマと同じ形を、ガイド付き生成で出させる
@Generable
nonisolated struct AppleAskedResponse {
    @Guide(description: "尋ねられた質問だけ。なければ空")
    var asked: [AppleAskedMatch]
}

@Generable
nonisolated struct AppleAskedMatch {
    @Guide(description: "質問ID (q1..qN)")
    var id: String
    @Guide(description: "根拠となるセグメントID (s1..)")
    var segments: [String]
}
