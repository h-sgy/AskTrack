import Foundation

/// 判定に使う LLM。プロバイダごとに実装する（Apple / Anthropic / …）
protocol LLMClient: Sendable {
    /// 書き起こしの中で尋ねられた質問を返す
    func findAsked(questions: [PromptQuestion], transcript: String) async throws -> [AskedMatch]
}

struct PromptQuestion: Equatable, Sendable {
    let key: String   // "q1", "q2", …
    let text: String
}

/// 5.3 の出力スキーマと同じ形
struct AskedMatch: Codable, Equatable, Sendable {
    let id: String
    let segments: [String]
}

struct AskedResponse: Codable, Sendable {
    let asked: [AskedMatch]
}

enum LLMError: Error, Equatable {
    case transient(String)        // 429 / 5xx / 通信エラー。次のきっかけで再試行する
    case refusal                  // 安全分類器に断られた
    case invalidResponse(String)  // 応答を解析できない
    case unauthorized             // API キーが無効。判定を止める
    case badRequest(String)       // 400 / 404 など設定の問題（モデル名・パラメータ）。判定を止める

    /// 続けても同じ結果になるので、判定を止めてユーザーに知らせるもの
    var isFatal: Bool {
        switch self {
        case .unauthorized, .badRequest: true
        case .transient, .refusal, .invalidResponse: false
        }
    }

    /// HTTP ステータスと本文から分類する。2xx なら nil
    init?(status: Int, body: Data) {
        guard !(200..<300).contains(status) else { return nil }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error.message
            ?? String(decoding: body.prefix(300), as: UTF8.self)
        switch status {
        case 401, 403:
            self = .unauthorized
        case 400 where message.contains("API_KEY_INVALID") || message.contains("API key not valid"):
            self = .unauthorized   // Gemini は無効なキーを 400 で返すことがある
        case 408, 409, 429, 500...:
            self = .transient("HTTP \(status): \(message)")
        default:
            self = .badRequest("HTTP \(status): \(message)")
        }
    }

    /// 3 社とも {"error": {"message": ...}} の形
    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

extension LLMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .transient(let detail): "一時的なエラーです。次の判定で再試行します（\(detail)）"
        case .refusal: "LLM に判定を断られました。"
        case .invalidResponse(let detail): "LLM の応答を読めませんでした（\(detail)）"
        case .unauthorized: "API キーが無効です。設定を確認してください。"
        case .badRequest(let detail): "リクエストが拒否されました。設定（モデルなど）を確認してください（\(detail)）"
        }
    }
}

enum LLMHTTP {
    static func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.transient(error.localizedDescription)
        }
        if let error = LLMError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data) { throw error }
        return data
    }

    static func jsonRequest(_ url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// モデルが返した JSON 文字列（5.3 のスキーマ）を読む
    static func decodeAsked(_ text: String) throws -> [AskedMatch] {
        do {
            return try JSONDecoder().decode(AskedResponse.self, from: Data(text.utf8)).asked
        } catch {
            throw LLMError.invalidResponse("JSON を読めません: \(text.prefix(200))")
        }
    }
}

enum JudgePrompt {
    static let system = """
    あなたはインタビュー進行のアシスタントです。
    <questions> に質問リスト、<transcript> に会話の書き起こしが与えられます。
    書き起こしは音声認識の結果で、誤認識を多く含みます（同音異義語、固有名詞やカタカナ語の崩れ、句読点の欠落、文の途中での分断など）。
    文字面ではなく、音の近さと前後の文脈から、本来話された内容を推測して読んでください。
    また、書き起こしには質問者と回答者の両方の発言が、話者の区別なしに混ざっています。
    そのうえで、各質問が質問者によって「実質的に同じ意図で」既に尋ねられているかを判定してください。
    - 言い回しが違っても、同じことを聞いていれば「尋ねた」とみなす
    - 一部しか聞いていない、話題に触れただけ、という場合は含めない
    - 回答者が自分から話題にしただけの場合や、回答者からの逆質問は含めない
    - 確信が持てない場合は含めない
    - 最後の「認識中」の行は、まだ話している途中の文です。途中まででも質問の意図がはっきりしていれば根拠にしてよい
    尋ねた質問だけを返し、segments には根拠となる行のセグメント ID（[s12 …] の s12）を入れてください。
    """

    /// 5.3 の出力スキーマ（JSON Schema）
    static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "asked": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "質問ID (q1..qN)"],
                        "segments": ["type": "array", "items": ["type": "string"],
                                     "description": "根拠となるセグメントID (s1..)"],
                    ],
                    "required": ["id", "segments"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["asked"],
        "additionalProperties": false,
    ]

    static func user(questions: [PromptQuestion], transcript: String) -> String {
        let list = questions.map { "\($0.key): \($0.text)" }.joined(separator: "\n")
        return "<questions>\n\(list)\n</questions>\n<transcript>\n\(transcript)\n</transcript>"
    }
}

/// 1 回の判定で送る内容と、返ってきた結果の検証（設計書 5.2・5.5）
struct JudgeRequest {
    let questions: [PromptQuestion]
    let transcript: String
    let range: Range<Int>                 // 送った確定セグメントの添字
    private let questionIDs: [String: UUID]
    private let sentTexts: [Int: String]  // 送った行（認識中の行を含む）。根拠はここから取る

    /// - Parameters:
    ///   - questions: チェック済みも含めて全部送る。済みの質問に当たる発言を、似た別の質問に回させないため
    ///   - volatile: 認識中（未確定）の文。range が最新の確定セグメントまで届いているときだけ最後の行に付ける
    init(questions: [Question], segments: [Segment], range: Range<Int>, volatile: String = "") {
        let keyed = questions.enumerated().map { ("q\($0.offset + 1)", $0.element) }
        self.questions = keyed.map { PromptQuestion(key: $0.0, text: $0.1.text) }
        questionIDs = Dictionary(uniqueKeysWithValues: keyed.map { ($0.0, $0.1.id) })
        self.range = range
        var lines = range.map { "[s\($0 + 1) \(Self.timestamp(segments[$0].start))] \(segments[$0].text)" }
        var texts = Dictionary(uniqueKeysWithValues: range.map { ($0, segments[$0].text) })
        if !volatile.isEmpty, range.upperBound == segments.count {
            lines.append("[s\(segments.count + 1) 認識中] \(volatile)")
            texts[segments.count] = volatile
        }
        transcript = lines.joined(separator: "\n")
        sentTexts = texts
    }

    /// 検証を通った結果だけをチェックにする。
    /// blocked は「反映する時点で」チェック済みか手動で外された質問（判定中に手動で外したものを付け直さない）
    func accept(_ matches: [AskedMatch], blocked: Set<UUID>, at now: Date) -> [Check] {
        var result: [Check] = []
        for match in matches {
            guard let questionID = questionIDs[match.id],
                  !blocked.contains(questionID),
                  !result.contains(where: { $0.questionID == questionID }) else { continue }
            let indices = match.segments.compactMap(Self.segmentIndex)
            guard !indices.isEmpty, indices.count == match.segments.count,
                  indices.allSatisfy({ sentTexts[$0] != nil }) else { continue }
            let sorted = Array(Set(indices)).sorted()
            let evidence = sorted.compactMap { sentTexts[$0] }.joined(separator: " ")
            result.append(Check(questionID: questionID, checked: true, at: now, evidence: evidence, manual: false,
                                evidenceIndices: sorted))
        }
        return result
    }

    /// "s12" → 11
    static func segmentIndex(_ id: String) -> Int? {
        guard id.first == "s", let n = Int(id.dropFirst()), n >= 1 else { return nil }
        return n - 1
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
