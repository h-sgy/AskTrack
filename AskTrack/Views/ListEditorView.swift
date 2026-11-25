import SwiftUI

/// タスクアプリのように 1 問ずつ行を追加・並べ替えする
struct ListEditorView: View {
    let app: AppModel
    @State private var list: QuestionList
    @State private var newText = ""
    @State private var bulkAdding = false
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case question(UUID)
        case new
    }

    init(list: QuestionList, app: AppModel) {
        self.app = app
        var list = list
        list.questions.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        _list = State(initialValue: list)
    }

    private var count: Int {
        list.questions.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("タイトル", text: $list.title)
                .font(.title2)
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top)
            List {
                ForEach($list.questions) { $question in
                    QuestionRow(question: $question, focus: $focus,
                                onSubmit: { insert(after: question.id) },
                                onDelete: { remove(question.id) })
                }
                .onMove { list.questions.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Image(systemName: "plus.circle").scaledFont(15).foregroundStyle(.secondary)
                    TextField("質問を追加（Return で次へ）", text: $newText)
                        .scaledFont(15)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .new)
                        .onSubmit(addNew)
                }
            }
            HStack {
                Button("まとめて追加…") { bulkAdding = true }
                Spacer()
                Text("\(count) 問").foregroundStyle(.secondary)
                Button("このリストで録音を始める") { app.startSession(with: list) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0 || app.isRecording)
            }
            .padding([.horizontal, .bottom])
        }
        .onChange(of: list) { app.save(list) }
        .onChange(of: focus) { old, _ in removeIfEmpty(old) }
        .onAppear { focus = .new }   // 開いたらすぐ質問を打ち込める（タイトルの上書きを防ぐ）
        .sheet(isPresented: $bulkAdding) {
            BulkAddSheet { append(QuestionList.parseQuestions($0)) }
        }
    }

    private func addNew() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        list.questions.append(Question(text: text))
        newText = ""
        focus = .new   // 続けて入力できるように
    }

    private func insert(after id: UUID) {
        guard let index = list.questions.firstIndex(where: { $0.id == id }) else { return }
        let question = Question(text: "")
        list.questions.insert(question, at: index + 1)
        focus = .question(question.id)
    }

    private func remove(_ id: UUID) {
        list.questions.removeAll { $0.id == id }
    }

    /// 空のまま別の行に移ったら、その行を消す
    private func removeIfEmpty(_ field: Field?) {
        guard case .question(let id)? = field,
              list.questions.first(where: { $0.id == id })?.text.trimmingCharacters(in: .whitespaces).isEmpty == true
        else { return }
        remove(id)
    }

    private func append(_ texts: [String]) {
        list.questions.append(contentsOf: texts.map { Question(text: $0) })
    }
}

private struct QuestionRow: View {
    @Binding var question: Question
    var focus: FocusState<ListEditorView.Field?>.Binding
    let onSubmit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Image(systemName: "circle").scaledFont(15).foregroundStyle(.secondary)
            TextField("質問", text: $question.text)
                .scaledFont(15)
                .textFieldStyle(.plain)
                .focused(focus, equals: .question(question.id))
                .onSubmit(onSubmit)
            Button(action: onDelete) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("削除")
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("削除", role: .destructive, action: onDelete) }
    }
}

/// 箇条書きをまとめて貼り付ける
private struct BulkAddSheet: View {
    let onAdd: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("まとめて追加").font(.headline)
            Text("1 行に 1 つの質問。箇条書き（- ・ 1. など）のまま貼り付けて構いません。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 220)
                .border(.separator)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加") {
                    onAdd(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(QuestionList.parseQuestions(text).isEmpty)
            }
        }
        .padding()
        .frame(width: 480)
    }
}
