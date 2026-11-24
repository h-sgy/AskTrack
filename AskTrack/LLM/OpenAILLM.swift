import Foundation

/// OpenAI（Responses API）
struct OpenAILLM: LLMClient {
    let apiKey: String
    let model: String

    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch] {
        try Self.parse(await LLMHTTP.send(makeRequest(questions: questions, transcript: transcript)))
    }

    func makeRequest(questions: [PromptQuestion], transcript: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "instructions": JudgePrompt.system,
            "input": JudgePrompt.user(questions: questions, transcript: transcript),
            "text": ["format": ["type": "json_schema", "name": "asked_questions",
                                "schema": JudgePrompt.outputSchema, "strict": true]],
            "reasoning": ["effort": "low"],
            "store": false,   // 既定では応答が OpenAI 側に保存されるので、保存させない
        ]
        return try LLMHTTP.jsonRequest(URL(string: "https://api.openai.com/v1/responses")!,
                                       headers: ["authorization": "Bearer \(apiKey)"], body: body)
    }

    static func parse(_ data: Data) throws -> [AskedMatch] {
        struct Response: Decodable {
            struct Incomplete: Decodable { let reason: String? }
            struct Item: Decodable { let type: String; let content: [Content]? }
            struct Content: Decodable { let type: String; let text: String? }
            let status: String?
            let incompleteDetails: Incomplete?
            let output: [Item]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data) else {
            throw LLMError.invalidResponse("応答の形が想定と違います")
        }
        if response.status == "incomplete" {
            throw LLMError.invalidResponse("途中で終わりました（\(response.incompleteDetails?.reason ?? "-")）")
        }
        let contents = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if contents.contains(where: { $0.type == "refusal" }) { throw LLMError.refusal }
        guard let text = contents.first(where: { $0.type == "output_text" })?.text else {
            throw LLMError.invalidResponse("テキストがありません")
        }
        return try LLMHTTP.decodeAsked(text)
    }
}
