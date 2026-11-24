import AppKit
import SwiftUI

extension Color {
    static let askGreen = Color(red: 0.118, green: 0.498, blue: 0.271)   // チェック済み・根拠
    static let askRed = Color(red: 0.706, green: 0.137, blue: 0.094)     // 録音中・停止
}

/// 注意書き。色だけに頼らず、アイコンと本文で伝える
struct WarningBox: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// マイクの入力レベル（8 本のバー）
struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Float(i) < level * 8 ? Color.askGreen : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 6 + CGFloat(i) * 2.5)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("マイクの入力レベル")
        .accessibilityValue("\(Int(level * 100))%")
    }
}

/// "03:12"（1 時間を超えたら "1:03:12"）
func clockText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
}

/// SwiftUI では設定できないウィンドウの性質を設定する
struct WindowConfigurator: NSViewRepresentable {
    /// 全画面のアプリの上にも出す（ミニウィンドウ用）
    var floating = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // 画面共有に映さない（macOS 15 以降は効かないという報告がある。実機で要確認）
        window.sharingType = .none
        if floating {
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
    }
}
