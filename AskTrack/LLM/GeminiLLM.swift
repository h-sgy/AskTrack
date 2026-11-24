import Foundation

/// Gemini（generateContent）
struct GeminiLLM: LLMClient {
    let apiKey: String
    let model: String

    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch] {
        try Self.parse(await LLMHTTP.send(makeRequest(questions: questions, transcript: transcript)))
    }

    func makeRequest(questions: [PromptQuestion], transcript: String) throws -> URLRequest {
        var config: [String: Any] = [
            "responseMimeType": "application/json",
            "responseJsonSchema": JudgePrompt.outputSchema,
        ]
        // thinkingLevel は Gemini 3 以降のみ。それより前のモデルに送るとエラーになる
        if model.hasPrefix("gemini-3") || model.hasPrefix("gemini-4") {
            config["thinkingConfig"] = ["thinkingLevel": "LOW"]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": JudgePrompt.system]]],
            "contents": [["role": "user", "parts": [["text": JudgePrompt.user(questions: questions, transcript: transcript)]]]],
            "generationConfig": config,
        ]
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        // キーは URL ではなくヘッダーで送る（URL はログに残りやすい）
        return try LLMHTTP.jsonRequest(url, headers: ["x-goog-api-key": apiKey], body: body)
    }

    static let refusalReasons: Set = ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION"]

    static func parse(_ data: Data) throws -> [AskedMatch] {
        struct Response: Decodable {
            struct Feedback: Decodable { let blockReason: String? }
            struct Candidate: Decodable { let content: Content?; let finishReason: String? }
            struct Content: Decodable { let parts: [Part]? }
            struct Part: Decodable { let text: String?; let thought: Bool? }
            let candidates: [Candidate]?
            let promptFeedback: Feedback?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LLMError.invalidResponse("応答の形が想定と違います")
        }
        if response.promptFeedback?.blockReason != nil { throw LLMError.refusal }
        guard let candidate = response.candidates?.first else { throw LLMError.invalidResponse("候補がありません") }
        if let reason = candidate.finishReason, refusalReasons.contains(reason) { throw LLMError.refusal }
        if candidate.finishReason == "MAX_TOKENS" { throw LLMError.invalidResponse("途中で終わりました（MAX_TOKENS）") }
        let text = (candidate.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw LLMError.invalidResponse("テキストがありません") }
        return try LLMHTTP.decodeAsked(text)
    }
}
