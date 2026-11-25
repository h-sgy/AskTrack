import SwiftUI

/// まだ聞いていない質問だけを、常に前面の小さなウィンドウに出す（会議中に横目で見る）
struct MiniPanelView: View {
    let app: AppModel

    var body: some View {
        Group {
            if let live = app.live {
                content(live)
            } else {
                ContentUnavailableView("録音していません", systemImage: "mic.slash",
                                       description: Text("質問リストから録音を始めると、まだ聞いていない質問がここに出ます。"))
            }
        }
        .frame(minWidth: 300, idealWidth: 340, minHeight: 360, idealHeight: 480)
        .background(WindowConfigurator(floating: true))
    }

    @ViewBuilder
    private func content(_ live: SessionModel) -> some View {
        let session = live.session
        let open = session.questions.filter { question in
            session.checks.first { $0.questionID == question.id }?.checked != true
        }
        let last = session.checks.filter(\.checked).max { $0.at < $1.at }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.listTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if live.state == .paused {
                    Text("一時停止中 \(clockText(live.recordedDuration(at: .now)))")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                } else if live.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("● 録音中 \(clockText(live.recordedDuration(at: context.date)))")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.askRed).monospacedDigit()
                    }
                } else {
                    Text("録音を終了しました").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("まだ聞いていない質問").font(.caption).foregroundStyle(.secondary)
                Text("残り \(open.count) 問").scaledFont(30, weight: .bold)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(open) { question in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "circle").scaledFont(17).foregroundStyle(.secondary)
                            Text(question.text).scaledFont(17, weight: .medium)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let last, let question = session.questions.first(where: { $0.id == last.questionID }) {
                Label {
                    Text("「\(question.text)」をチェック").lineLimit(2)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.askGreen)
                }
                .scaledFont(13)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.askGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            HStack {
                Text("判定: \(live.judgeLabel ?? "なし")")
                Spacer()
                Text("常に前面に表示")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
    }
}
