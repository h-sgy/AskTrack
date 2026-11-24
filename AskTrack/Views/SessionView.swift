import SwiftUI
import UniformTypeIdentifiers

/// セッション 1 回ぶん。左に質問のチェックリスト、右に文字起こし。live があれば録音操作ができる
struct SessionView: View {
    let session: Session
    let live: SessionModel?
    @State private var exporting = false

    private var remaining: Int {
        session.questions.count - session.checks.filter(\.checked).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding()
            Divider()
            HSplitView {
                ChecklistView(session: session, live: live)
                    .frame(minWidth: 260, idealWidth: 320)
                TranscriptView(session: session, volatileText: live?.volatileText ?? "")
                    .frame(minWidth: 300)
            }
        }
        .navigationTitle(session.listTitle)
        .fileExporter(isPresented: $exporting, document: MarkdownFile(text: MarkdownExport.render(session)),
                      contentType: UTType(filenameExtension: "md") ?? .plainText,
                      defaultFilename: "\(session.listTitle) \(session.startedAt.formatted(.iso8601.year().month().day())).md") { _ in }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let live {
                    recordButton(live)
                    if live.state == .recording {
                        ProgressView(value: live.level).frame(width: 100).help("マイクの入力レベル")
                    }
                    if let label = live.judgeLabel {
                        Label("判定: \(label)", systemImage: label.hasPrefix("Apple") ? "lock.fill" : "network")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("残り \(remaining) / \(session.questions.count) 問").font(.headline)
                Button("Markdown で書き出す…") { exporting = true }
            }
            if let live {
                ForEach(notes(live), id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            } else if session.endedAt == nil {
                Text("録音中にアプリが終了したため、途中までの記録です。").font(.callout).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func recordButton(_ live: SessionModel) -> some View {
        switch live.state {
        case .idle, .preparing:
            ProgressView().controlSize(.small)
        case .recording:
            Button { live.stop() } label: { Label("停止", systemImage: "stop.fill") }
                .tint(.red)
        case .finishing:
            Label("残りを判定中…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .finished:
            EmptyView()
        }
    }

    private func notes(_ live: SessionModel) -> [String] {
        var notes: [String] = []
        if let message = live.message { notes.append(message) }
        if let notice = live.judgeNotice { notes.append(notice) }
        if let error = live.judgeError, error.isFatal { notes.append("判定を止めました: \(error.localizedDescription)") }
        if !live.skipped.isEmpty {
            let ranges = live.skipped.map { "s\($0.lowerBound + 1)〜s\($0.upperBound)" }.joined(separator: "、")
            notes.append("判定できなかった範囲: \(ranges)")
        }
        if live.state == .recording, live.session.segments.isEmpty {
            notes.append("Mac を自分と相手の間に置くと、相手の声も拾いやすくなります。")
        }
        return notes
    }
}

private struct ChecklistView: View {
    let session: Session
    let live: SessionModel?

    var body: some View {
        List(session.questions) { question in
            let check = session.checks.first { $0.questionID == question.id }
            let checked = check?.checked == true
            HStack(alignment: .top) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.text)
                    if checked, let evidence = check?.evidence {
                        Text("「\(evidence)」").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else if check?.manual == true, !checked {
                        Text("手動で外しました（自動では付けません）").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if live?.isActive == true { live?.toggle(question) } }
            .help(check?.evidence ?? "")
        }
    }
}

private struct TranscriptView: View {
    let session: Session
    let volatileText: String

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(session.segments.enumerated()), id: \.offset) { _, segment in
                    Text("[\(JudgeRequest.timestamp(segment.start))] \(segment.text)")
                        .textSelection(.enabled)
                }
                if !volatileText.isEmpty {
                    Text(volatileText).foregroundStyle(.secondary)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: session.segments.count) { proxy.scrollTo("bottom") }
            .onChange(of: volatileText) { proxy.scrollTo("bottom") }
        }
    }
}
