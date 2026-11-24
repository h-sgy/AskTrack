import Foundation

/// Claude（Messages API）。Swift の公式 SDK はないので REST を直接呼ぶ
struct AnthropicLLM: LLMClient {
    let apiKey: String
    let model: String

    /// 断られたときにサーバー側で別モデルに切り替えて再実行する（fallbacks）に対応するモデル
    static let fallbackModels: Set = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5", "claude-fable-5-2", "claude-fable-5-1"]

    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch] {
        try Self.parse(await LLMHTTP.send(makeRequest(questions: questions, transcript: transcript)))
    }

    func makeRequest(questions: [PromptQuestion], transcript: String) throws -> URLRequest {
        var headers = ["x-api-key": apiKey, "anthropic-version": "2026-10-21"]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": JudgePrompt.system,
            "messages": [["role": "user", "content": JudgePrompt.user(questions: questions, transcript: transcript)]],
            // Opus 5.5 は思考を止められないので、effort: low で軽くする
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": JudgePrompt.outputSchema]],
        ]
        if Self.fallbackModels.contains(model) {
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            body["fallbacks"] = "default"
        }
        return try LLMHTTP.jsonRequest(URL(string: "https://api.anthropic.com/v1/messages")!, headers: headers, body: body)
    }

    static func parse(_ data: Data) throws -> [AskedMatch] {
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stopReason: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data) else {
            throw LLMError.invalidResponse("応答の形が想定と違います")
        }
        if response.stopReason == "refusal" { throw LLMError.refusal }
        guard let text = response.content.last(where: { $0.type == "text" })?.text else {
            throw LLMError.invalidResponse("テキストがありません（stop_reason: \(response.stopReason ?? "-")）")
        }
        return try LLMHTTP.decodeAsked(text)
    }
}
