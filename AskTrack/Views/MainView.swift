import Sparkle
import SwiftUI

struct MainView: View {
    @Bindable var app: AppModel
    let updater: SPUUpdater

    var body: some View {
        NavigationSplitView {
            List(selection: $app.selection) {
                Section("質問リスト") {
                    ForEach(app.lists) { list in
                        Text(list.title.isEmpty ? "無題" : list.title)
                            .tag(AppModel.Selection.list(list.id))
                            .contextMenu {
                                Button("削除", role: .destructive) { app.delete(list) }
                            }
                    }
                }
                Section("過去のセッション") {
                    ForEach(app.sessions) { session in
                        SessionRow(session: session, status: app.live?.session.id == session.id ? app.live?.statusLabel : nil)
                            .tag(AppModel.Selection.session(session.id))
                            .contextMenu {
                                Button("削除", role: .destructive) { app.delete(session) }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button { app.addList() } label: { Label("質問リストを追加", systemImage: "plus") }
            }
        } detail: {
            switch app.selection {
            case .list(let id)?:
                if let list = app.lists.first(where: { $0.id == id }) {
                    ListEditorView(list: list, app: app).id(id)
                }
            case .session(let id)?:
                if let session = app.session(id: id) {
                    SessionView(session: session, live: app.live?.session.id == id ? app.live : nil,
                                onRestart: app.isRecording ? nil : { app.restart(from: session) })
                }
            case .settings?:
                SettingsView(settings: app.settings, updater: updater, onBack: app.closeSettings)
            case nil:
                ContentUnavailableView("質問リストを選ぶか、＋で追加してください", systemImage: "list.bullet.clipboard")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                let summary = app.settings.summary
                Button { app.showSettings() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(summary.ready ? Color.askGreen : Color.orange).frame(width: 8, height: 8)
                        Text("判定: \(summary.label)")
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("判定に使う LLM を設定する")
                Button { app.showSettings() } label: { Label("設定", systemImage: "gearshape") }
                    .labelStyle(.titleAndIcon)
                    .help("設定（⌘,）")
            }
        }
        .background(WindowConfigurator())
        .frame(minWidth: 800, minHeight: 500)
        .alert("エラー", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let status: String?   // 録音中・一時停止中など（このセッションを録音しているときだけ）

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.listTitle.isEmpty ? "無題" : session.listTitle)
            HStack(spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let status {
                    Text(status).foregroundStyle(status == "録音中" ? Color.askRed : .secondary)
                } else if session.endedAt == nil {
                    Text("中断").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
