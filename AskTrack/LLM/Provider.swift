import Foundation

/// 判定に使える外部 LLM のプロバイダ
enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic, openai, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Claude（Anthropic）"
        case .openai: "OpenAI"
        case .gemini: "Gemini（Google）"
        }
    }

    /// Keychain の account 名
    var keychainAccount: String { rawValue }

    /// 選べるモデル。API の一覧をそのまま出すと、パラメータ（構造化出力・思考の量）に
    /// 対応していないモデルも選べてしまい 400 になるので、確認済みのものだけを並べる。
    /// 単価は 2026-11 時点（Gemini 4 Argon と 3.8 Flash は値上げ後の価格）。先頭が既定
    var models: [ModelOption] {
        switch self {
        case .anthropic: [
            ModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", input: 4, output: 20),
            ModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", input: 2, output: 10),
            ModelOption(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", input: 0.10, output: 0.50),
        ]
        case .openai: [
            ModelOption(id: "gpt-6.2-sol", name: "GPT-6.2 sol", input: 2, output: 10),
            ModelOption(id: "gpt-6.2-astra", name: "GPT-6.2 astra", input: 8, output: 40),
            ModelOption(id: "gpt-6.1-terra", name: "GPT-6.1 terra", input: 1, output: 5),
            ModelOption(id: "gpt-6-luna", name: "GPT-6 luna", input: 0.10, output: 0.50),
        ]
        case .gemini: [
            ModelOption(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", input: 1.50, output: 7.50),
            ModelOption(id: "gemini-4-argon", name: "Gemini 4 Argon", input: 4, output: 20),
            ModelOption(id: "gemini-4-hydrogen", name: "Gemini 4 Hydrogen", input: 1.50, output: 7.50),
            ModelOption(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", input: 0.30, output: 2.50),
        ]
        }
    }

    func client(apiKey: String, model: String) -> any LLMClient {
        switch self {
        case .anthropic: AnthropicLLM(apiKey: apiKey, model: model)
        case .openai: OpenAILLM(apiKey: apiKey, model: model)
        case .gemini: GeminiLLM(apiKey: apiKey, model: model)
        }
    }
}

struct ModelOption: Identifiable, Sendable {
    let id: String
    let name: String
    let input: Double    // $ / 100 万トークン
    let output: Double   // $ / 100 万トークン（思考トークンを含む）

    /// 2 時間の対面セッションでの概算（判定 480 回、1 回あたり入力 2,000・出力 450 トークン。設計書 5.7）
    var costPer2Hours: Double { 480 * (2_000 * input + 450 * output) / 1_000_000 }
}
