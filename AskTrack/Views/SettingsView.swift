import AppKit
import Sparkle
import SwiftUI

/// 同じウィンドウの中に出す設定画面。「戻る」か esc で元の画面に戻る
struct SettingsView: View {
    @Bindable var settings: JudgeSettings
    let updater: SPUUpdater
    let onBack: () -> Void
    @State private var autoUpdate = false
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.large

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("設定").font(.system(size: 26, weight: .bold))
                SettingsCard(title: "表示", caption: "質問リスト・文字起こし・ミニウィンドウの文字の大きさです。") {
                    Picker("文字サイズ", selection: $textSize) {
                        ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("決裁者はどなたですか").font(.system(size: 15 * textSize.scale, weight: .medium))
                        Text("02:40「最終的に決めるのはどなたになりますか」")
                            .font(.system(size: 12 * textSize.scale)).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("見本")
                }
                SettingsCard(title: "マイク", caption: "macOS の「サウンド > 入力」で選んでいるマイクで録音します。録音中に変えても、そのまま切り替わります。") {
                    MicrophoneInfo()
                }
                SettingsCard(title: "判定に使う LLM", caption: "質問を聞いたかどうかの判定に使います。文字起こしは Mac の中で行います。") {
                    ProviderPicker(settings: settings)
                    if settings.provider == .apple {
                        WarningBox(AppleLLM.unavailableReason
                                   ?? "無料で、外部には何も送りません。ただし精度が低く、誤ってチェックが付くことがあります。試験用です。")
                    } else {
                        ProviderDetail(provider: settings.provider, settings: settings)
                            .id(settings.provider)
                    }
                }
                SettingsCard(title: "判定の間隔") { intervalControls }
                SettingsCard(title: "アップデート") { updateControls }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("設定")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) { Label("戻る", systemImage: "chevron.left") }
                    .labelStyle(.titleAndIcon)
                    .help("戻る（esc）")
            }
        }
        .onExitCommand(perform: onBack)
        .onAppear { autoUpdate = updater.automaticallyChecksForUpdates }
    }

    private var intervalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { settings.minInterval = max(5, settings.minInterval - 5) } label: {
                    Image(systemName: "minus").frame(width: 20)
                }
                .accessibilityLabel("間隔を短くする")
                .disabled(settings.minInterval <= 5)
                Text("最短 \(Int(settings.minInterval)) 秒おき")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 150)
                Button { settings.minInterval = min(60, settings.minInterval + 5) } label: {
                    Image(systemName: "plus").frame(width: 20)
                }
                .accessibilityLabel("間隔を長くする")
                .disabled(settings.minInterval >= 60)
            }
            .controlSize(.large)
            Text("間隔を延ばすほど費用は下がり、チェックが付くまでの時間は延びます。次の録音から反映されます。")
                .font(.callout).foregroundStyle(.secondary)
            if settings.provider.needsAPIKey, let model = settings.model(for: settings.provider) {
                Text("この設定だと、2 時間で約 **$\(String(format: "%.1f", model.costPer2Hours * 15 / settings.minInterval))**（\(model.name)）")
            }
        }
    }

    private var updateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("アップデートを自動で確認する", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { updater.automaticallyChecksForUpdates = autoUpdate }
                Spacer()
                Button("今すぐ確認") { updater.checkForUpdates() }
                    .controlSize(.large)
            }
            Text("AskTrack \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let caption: String?
    let content: Content

    init(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .bold))
                if let caption { Text(caption).font(.callout).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

/// 今使っているマイク。macOS の入力を変えると、その場で表示も変わる
private struct MicrophoneInfo: View {
    @State private var name = ""
    @State private var observer: AudioDeviceObserver?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label(name, systemImage: "mic").font(.body.weight(.medium))
                Spacer()
                Button("サウンド設定を開く…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                .controlSize(.large)
            }
            Text("AirPods などの Bluetooth マイクは、会議アプリと同時に使うと音質が下がり、認識精度が落ちます。対面では Mac 内蔵のマイクか有線のマイクを使い、Mac を自分と相手の間に置いてください。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            refresh()
            observer = AudioDeviceObserver { refresh() }
        }
        .onDisappear { observer = nil }
    }

    private func refresh() {
        name = AudioDevices.defaultInput()?.name ?? "マイクが見つかりません"
    }
}

/// 4 社から 1 つを選ぶタイル
private struct ProviderPicker: View {
    @Bindable var settings: JudgeSettings

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Provider.allCases) { provider in
                let selected = settings.provider == provider
                Button { settings.provider = provider } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.tileName).fontWeight(.semibold)
                        Text(provider.note).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// モデル・API キー・接続テスト
private struct ProviderDetail: View {
    let provider: Provider
    @Bindable var settings: JudgeSettings
    @State private var keyDraft = ""
    @State private var status: (text: String, ok: Bool)?
    @State private var testing = false

    var body: some View {
        let hasKey = settings.hasKey(for: provider)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("モデル").font(.callout.weight(.semibold))
                ForEach(provider.models) { model in
                    ModelRow(model: model, selected: settings.model(for: provider)?.id == model.id,
                             cost: model.costPer2Hours * 15 / settings.minInterval) {
                        settings.setModel(model.id, for: provider)
                        status = nil
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API キー").font(.callout.weight(.semibold))
                HStack(spacing: 8) {
                    SecureField(hasKey ? "保存済み（変更するときは入力）" : "API キーを貼り付け", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("保存", action: save).disabled(keyDraft.isEmpty)
                    if hasKey {
                        Button("削除", role: .destructive) {
                            settings.deleteKey(for: provider)
                            status = nil
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button("接続テスト") { Task { await test() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasKey || testing)
                if testing { ProgressView().controlSize(.small) }
                if let status {
                    Label(status.text, systemImage: status.ok ? "checkmark" : "exclamationmark.triangle")
                        .foregroundStyle(status.ok ? Color.askGreen : Color.primary)
                        .fontWeight(status.ok ? .semibold : .regular)
                }
            }
            Text("API キーはこの Mac の Keychain にだけ保存します。判定のたびに、書き起こしと質問リストが \(provider.displayName) に送られます。")
                .font(.caption).foregroundStyle(.secondary)
            if provider == .gemini {
                WarningBox("無料枠のキーだと、送った内容が Google の製品改善に使われます。機密性の高いヒアリングでは、有料枠のキーを使ってください。")
            }
        }
        .controlSize(.large)
    }

    private func save() {
        do {
            try settings.saveKey(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
            keyDraft = ""
            status = ("保存しました", true)
        } catch {
            status = (error.localizedDescription, false)
        }
    }

    /// 小さなサンプルで実際に 1 回呼ぶ（費用はごくわずか）
    private func test() async {
        guard let key = settings.apiKey(for: provider), let model = settings.model(for: provider) else { return }
        testing = true
        defer { testing = false }
        let request = JudgeRequest(questions: [Question(text: "今年度の予算はどのくらいですか")],
                                   segments: [Segment(start: 0, text: "では今年度の予算感を教えてもらえますか")], range: 0..<1)
        do {
            _ = try await provider.client(apiKey: key, model: model.id)
                .findAsked(questions: request.questions, transcript: request.transcript)
            status = ("接続できました（\(model.name)）", true)
        } catch {
            status = (error.localizedDescription, false)
        }
    }
}

private struct ModelRow: View {
    let model: ModelOption
    let selected: Bool
    let cost: Double
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(model.name).fontWeight(.medium)
                Spacer()
                Text("2 時間で約 $\(cost, format: .number.precision(.fractionLength(1)))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
