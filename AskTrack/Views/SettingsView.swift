import Sparkle
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: JudgeSettings
    let updater: SPUUpdater
    @State private var autoUpdate = false

    var body: some View {
        Form {
            Section("判定に使う LLM") {
                Picker("プロバイダ", selection: $settings.provider) {
                    ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.provider == .apple {
                    Text(AppleLLM.unavailableReason ?? "使えます。外部には何も送りません。精度は外部の LLM より低めです。")
                        .foregroundStyle(.secondary)
                } else {
                    CloudProviderSettings(provider: settings.provider, settings: settings)
                        .id(settings.provider)
                }
            }
            Section("判定の間隔") {
                Stepper("最短 \(Int(settings.minInterval)) 秒おき", value: $settings.minInterval, in: 15...60, step: 5)
                Text("間隔を延ばすほど費用は下がり、チェックが付くまでの時間は延びます。次の録音から反映されます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("アップデート") {
                Toggle("アップデートを自動で確認する", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { updater.automaticallyChecksForUpdates = autoUpdate }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .onAppear { autoUpdate = updater.automaticallyChecksForUpdates }
    }
}

private struct CloudProviderSettings: View {
    let provider: Provider
    let settings: JudgeSettings
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Picker("モデル", selection: Binding(get: { settings.model(for: provider)?.id ?? "" },
                                           set: { settings.setModel($0, for: provider) })) {
            ForEach(provider.models) { model in
                Text("\(model.name)（2 時間で約 $\(model.costPer2Hours, format: .number.precision(.fractionLength(1)))）")
                    .tag(model.id)
            }
        }
        HStack {
            SecureField(hasKey ? "保存済み（変更するときは入力）" : "API キー", text: $keyDraft)
            Button("保存") { saveKey() }.disabled(keyDraft.isEmpty)
            if hasKey {
                Button("削除", role: .destructive) {
                    Keychain.delete(account: provider.keychainAccount)
                    refresh()
                }
            }
        }
        HStack {
            Button("接続テスト") { Task { await test() } }.disabled(!hasKey || testing)
            if testing { ProgressView().controlSize(.small) }
            if let status { Text(status).foregroundStyle(.secondary) }
        }
        Text("API キーはこの Mac の Keychain にだけ保存します。判定のたびに、書き起こしと質問リストが \(provider.displayName) に送られます。")
            .font(.caption).foregroundStyle(.secondary)
        if provider == .gemini {
            Text("無料枠のキーだと、送った内容が Google の製品改善に使われます。機密性の高いヒアリングでは有料枠のキーを使ってください。")
                .font(.caption).foregroundStyle(.orange)
        }
        Color.clear.frame(height: 0).onAppear(perform: refresh)
    }

    private func refresh() {
        hasKey = settings.apiKey(for: provider) != nil
        keyDraft = ""
        status = nil
    }

    private func saveKey() {
        do {
            try Keychain.save(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.keychainAccount)
            refresh()
            status = "保存しました"
        } catch {
            status = error.localizedDescription
        }
    }

    /// 小さなサンプルで実際に 1 回呼ぶ（費用はごくわずか）
    private func test() async {
        guard let key = settings.apiKey(for: provider), let model = settings.model(for: provider) else { return }
        testing = true
        defer { testing = false }
        let question = Question(text: "今年度の予算はどのくらいですか")
        let request = JudgeRequest(unchecked: [question], segments: [Segment(start: 0, text: "では今年度の予算感を教えてもらえますか")],
                                   range: 0..<1)
        do {
            _ = try await provider.client(apiKey: key, model: model.id)
                .findAsked(questions: request.questions, transcript: request.transcript)
            status = "接続できました（\(model.name)）"
        } catch {
            status = error.localizedDescription
        }
    }
}
