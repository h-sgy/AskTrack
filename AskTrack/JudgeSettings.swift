import Foundation
import Observation

/// 判定の設定。API キーだけは Keychain、それ以外は UserDefaults
@Observable
final class JudgeSettings {
    var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    /// 判定の最短間隔（秒）。延ばすほど費用は下がり、チェックが付くまでの時間は延びる
    var minInterval: Double { didSet { defaults.set(minInterval, forKey: "minInterval") } }
    private var modelIDs: [Provider: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: "provider").flatMap(Provider.init) ?? .anthropic
        minInterval = defaults.object(forKey: "minInterval") as? Double ?? 15
        modelIDs = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { p in
            defaults.string(forKey: "model.\(p.rawValue)").map { (p, $0) }
        })
    }

    func model(for provider: Provider) -> ModelOption? {
        provider.models.first { $0.id == modelIDs[provider] } ?? provider.models.first
    }

    func setModel(_ id: String, for provider: Provider) {
        modelIDs[provider] = id
        defaults.set(id, forKey: "model.\(provider.rawValue)")
    }

    func apiKey(for provider: Provider) -> String? {
        Keychain.load(account: provider.keychainAccount).flatMap { $0.isEmpty ? nil : $0 }
    }

    struct Judge {
        let client: any LLMClient
        let provider: Provider
        let label: String
        let notice: String?
    }

    /// 判定に使う LLM。選んだプロバイダのキーがなければ、Apple オンデバイスに切り替える。どれも使えなければ nil
    func resolve() -> Judge? {
        if provider.needsAPIKey, let key = apiKey(for: provider), let model = model(for: provider) {
            return Judge(client: provider.client(apiKey: key, model: model.id), provider: provider, label: model.name, notice: nil)
        }
        guard AppleLLM.unavailableReason == nil else { return nil }
        let notice = provider == .apple ? nil
            : "\(provider.displayName) の API キーが未設定なので、Apple オンデバイスで判定します。キーを設定すると判定精度が上がります。"
        return Judge(client: AppleLLM(), provider: .apple, label: "Apple オンデバイス", notice: notice)
    }
}
