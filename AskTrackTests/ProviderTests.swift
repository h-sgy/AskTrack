import Foundation
import Testing
@testable import AskTrack

private let sample = [PromptQuestion(key: "q1", text: "予算は？")]
private let askedJSON = #"{\"asked\":[{\"id\":\"q1\",\"segments\":[\"s1\"]}]}"#
private let expected = [AskedMatch(id: "q1", segments: ["s1"])]

private func body(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

struct AnthropicLLMTests {
    @Test func opusRequestUsesStructuredOutputLowEffortAndFallbacks() throws {
        let request = try AnthropicLLM(apiKey: "k", model: "claude-opus-5-5").makeRequest(questions: sample, transcript: "[s1 00:01] 予算は")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let json = try body(request)
        #expect(json["fallbacks"] as? String == "default")
        let config = try #require(json["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "low")
        #expect((config["format"] as? [String: Any])?["type"] as? String == "json_schema")
    }

    @Test func haikuHasNoFallbacks() throws {
        // Haiku 5.5 にはサーバー側の切り替え先がない
        let request = try AnthropicLLM(apiKey: "k", model: "claude-haiku-5-5").makeRequest(questions: sample, transcript: "")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(try body(request)["fallbacks"] == nil)
    }

    @Test func parsesTextBlockAfterThinking() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"\#(askedJSON)"}],"stop_reason":"end_turn"}"#.utf8)
        #expect(try AnthropicLLM.parse(data) == expected)
    }

    @Test func refusalStopReason() {
        let data = Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)
        #expect(throws: LLMError.refusal) { try AnthropicLLM.parse(data) }
    }
}

struct OpenAILLMTests {
    @Test func requestUsesStrictSchemaAndDoesNotStore() throws {
        let request = try OpenAILLM(apiKey: "k", model: "gpt-6.2-sol").makeRequest(questions: sample, transcript: "")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer k")
        let json = try body(request)
        #expect(json["store"] as? Bool == false)
        let format = try #require((json["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        #expect((json["reasoning"] as? [String: Any])?["effort"] as? String == "low")
    }

    @Test func parsesOutputTextAfterReasoning() throws {
        let data = Data(#"{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","role":"assistant","content":[{"type":"output_text","text":"\#(askedJSON)","annotations":[]}]}]}"#.utf8)
        #expect(try OpenAILLM.parse(data) == expected)
    }

    @Test func refusalAndIncomplete() {
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"no"}]}]}"#.utf8)
        #expect(throws: LLMError.refusal) { try OpenAILLM.parse(refusal) }
        let incomplete = Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8)
        #expect(throws: LLMError.invalidResponse("途中で終わりました（max_output_tokens）")) { try OpenAILLM.parse(incomplete) }
    }
}

struct GeminiLLMTests {
    @Test func requestUsesJsonSchemaHeaderKeyAndLowThinking() throws {
        let request = try GeminiLLM(apiKey: "k", model: "gemini-3.8-flash").makeRequest(questions: sample, transcript: "")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "k")
        #expect(request.url?.query == nil, "キーを URL に載せない")
        let config = try #require(try body(request)["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["responseJsonSchema"] != nil)
        #expect((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "LOW")
    }

    @Test func noThinkingLevelBeforeGemini3() throws {
        let request = try GeminiLLM(apiKey: "k", model: "gemini-2.5-flash-lite").makeRequest(questions: sample, transcript: "")
        #expect((try body(request)["generationConfig"] as? [String: Any])?["thinkingConfig"] == nil)
    }

    @Test func skipsThoughtParts() throws {
        let data = Data(#"{"candidates":[{"content":{"parts":[{"text":"考え中…","thought":true},{"text":"\#(askedJSON)"}]},"finishReason":"STOP"}]}"#.utf8)
        #expect(try GeminiLLM.parse(data) == expected)
    }

    @Test func blockedPromptAndSafetyFinish() {
        #expect(throws: LLMError.refusal) { try GeminiLLM.parse(Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8)) }
        #expect(throws: LLMError.refusal) { try GeminiLLM.parse(Data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#.utf8)) }
    }
}

struct LLMErrorStatusTests {
    @Test func classifiesHTTPStatus() {
        #expect(LLMError(status: 200, body: Data()) == nil)
        #expect(LLMError(status: 401, body: Data()) == .unauthorized)
        #expect(LLMError(status: 403, body: Data()) == .unauthorized)
        #expect(LLMError(status: 429, body: Data(#"{"error":{"message":"slow down"}}"#.utf8)) == .transient("HTTP 429: slow down"))
        #expect(LLMError(status: 529, body: Data())?.isFatal == false)
        #expect(LLMError(status: 404, body: Data(#"{"error":{"message":"model not found"}}"#.utf8)) == .badRequest("HTTP 404: model not found"))
    }

    @Test func geminiInvalidKeyIs400() {
        let body = Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#.utf8)
        #expect(LLMError(status: 400, body: body) == .unauthorized)
    }
}

// 実際の API を呼ぶテスト。キーがあるときだけ動く（費用が少しかかる）:
//   TEST_RUNNER_ANTHROPIC_API_KEY=… TEST_RUNNER_OPENAI_API_KEY=… TEST_RUNNER_GEMINI_API_KEY=… xcodebuild test …
struct LiveLLMTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["ANTHROPIC_API_KEY"] != nil)) func anthropic() async throws {
        try await Self.check(.anthropic, key: Self.env["ANTHROPIC_API_KEY"]!)
    }

    @Test(.enabled(if: env["OPENAI_API_KEY"] != nil)) func openai() async throws {
        try await Self.check(.openai, key: Self.env["OPENAI_API_KEY"]!)
    }

    @Test(.enabled(if: env["GEMINI_API_KEY"] != nil)) func gemini() async throws {
        try await Self.check(.gemini, key: Self.env["GEMINI_API_KEY"]!)
    }

    // Apple Intelligence が有効な Mac なら常に動く（無料・オフライン）
    @Test(.enabled(if: AppleLLM.unavailableReason == nil)) func apple() async throws {
        try await Self.check(AppleLLM(), label: "Apple")
    }

    static func check(_ provider: Provider, key: String) async throws {
        try await check(provider.client(apiKey: key, model: provider.models[0].id), label: provider.displayName)
    }

    /// 聞いた質問だけが根拠付きで返ること
    static func check(_ client: any LLMClient, label: String) async throws {
        let budget = Question(text: "今年度の予算はどのくらいですか")
        let owner = Question(text: "決裁者はどなたですか")
        let segments = [Segment(start: 3, text: "本日はよろしくお願いします"),
                        Segment(start: 10, text: "では今年度の予算感を教えてもらえますか"),
                        Segment(start: 15, text: "五百万円ほどです")]
        let request = JudgeRequest(unchecked: [budget, owner], segments: segments, range: 0..<3)
        let matches = try await client.findAsked(questions: request.questions, transcript: request.transcript)
        let checks = request.accept(matches, segments: segments, blocked: [], at: .now)
        #expect(checks.map(\.questionID) == [budget.id], "\(label): \(matches)")
    }
}
