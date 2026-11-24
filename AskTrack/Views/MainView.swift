import SwiftUI

struct MainView: View {
    @Bindable var app: AppModel

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
                        SessionRow(session: session, recording: app.isRecording && app.live?.session.id == session.id)
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
                    SessionView(session: session, live: app.live?.session.id == id ? app.live : nil)
                }
            case nil:
                ContentUnavailableView("質問リストを選ぶか、＋で追加してください", systemImage: "list.bullet.clipboard")
            }
        }
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
    let recording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.listTitle.isEmpty ? "無題" : session.listTitle)
            HStack(spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if recording {
                    Text("録音中").foregroundStyle(.red)
                } else if session.endedAt == nil {
                    Text("中断").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
