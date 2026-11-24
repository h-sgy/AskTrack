import SwiftUI
import UniformTypeIdentifiers

/// セッション 1 回ぶん。上に録音の操作、左に質問のチェックリスト、右に文字起こし
struct SessionView: View {
    let session: Session
    let live: SessionModel?
    @State private var exporting = false
    @Environment(\.openWindow) private var openWindow

    private var remaining: Int {
        session.questions.count - session.checks.filter(\.checked).count
    }

    /// チェックの根拠になったセグメント（文字起こしで緑にする）
    private var evidenceIndices: Set<Int> {
        Set(session.checks.filter(\.checked).flatMap { $0.evidenceIndices ?? [] })
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes, id: \.self) { WarningBox($0) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                Divider()
            }
            HSplitView {
                ChecklistView(session: session, live: live)
                    .frame(minWidth: 300, idealWidth: 380)
                TranscriptView(session: session, highlighted: evidenceIndices,
                               volatileText: live?.state == .recording ? live?.volatileText ?? "" : "")
                    .frame(minWidth: 360)
            }
        }
        .navigationTitle(session.listTitle)
        .fileExporter(isPresented: $exporting, document: MarkdownFile(text: MarkdownExport.render(session)),
                      contentType: UTType(filenameExtension: "md") ?? .plainText,
                      defaultFilename: "\(session.listTitle) \(session.startedAt.formatted(.iso8601.year().month().day())).md") { _ in }
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            recordingControls
            Spacer(minLength: 16)
            Text("残り \(remaining) / \(session.questions.count) 問")
                .font(.title3.bold())
                .monospacedDigit()
            if live?.isActive == true {
                Button { openWindow(id: "mini") } label: { Label("ミニウィンドウ", systemImage: "pip") }
                    .help("まだ聞いていない質問を、常に前面の小さなウィンドウに出す")
            }
            Button { exporting = true } label: { Label("Markdown で書き出す…", systemImage: "square.and.arrow.down") }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch live?.state {
        case .recording?:
            Button { live?.pause() } label: { Label("一時停止", systemImage: "pause.fill") }
            Button { live?.stop() } label: { Label("停止", systemImage: "stop.fill").fontWeight(.semibold) }
                .buttonStyle(.borderedProminent)
                .tint(Color.askRed)
            LevelMeter(level: live?.level ?? 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("● \(clockText(live?.recordedDuration(at: context.date) ?? 0))")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.askRed)
                    .monospacedDigit()
            }
            if session.segments.isEmpty {
                Text("Mac を自分と相手の間に置くと、相手の声も拾いやすくなります。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .paused?:
            Button { live?.resume() } label: { Label("再開", systemImage: "mic.fill").fontWeight(.semibold) }
                .buttonStyle(.borderedProminent)
            Button { live?.stop() } label: { Label("停止", systemImage: "stop.fill") }
                .tint(Color.askRed)
            Text("一時停止中 \(clockText(live?.recordedDuration(at: .now) ?? 0))")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("マイクは止まっています。").font(.callout).foregroundStyle(.secondary)
        case .idle?, .preparing?:
            ProgressView().controlSize(.small)
            Text(live?.message ?? "準備中…").foregroundStyle(.secondary)
        case .finishing?:
            ProgressView().controlSize(.small)
            Text("残りを判定中…").foregroundStyle(.secondary)
        case .finished?, nil:
            if let endedAt = session.endedAt {
                Label("録音を終了しました（\(clockText(session.recordedDuration(until: endedAt)))）", systemImage: "checkmark.circle")
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("録音中にアプリが終了したため、途中までの記録です。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 画面上部に出す注意（判定できない理由、止まった理由、判定できなかった範囲）
    private var notes: [String] {
        guard let live else { return [] }
        var notes: [String] = []
        if let message = live.message, live.state != .preparing, live.state != .idle { notes.append(message) }
        if let notice = live.judgeNotice { notes.append(notice) }
        if let error = live.judgeError, error.isFatal { notes.append("判定を止めました: \(error.localizedDescription)") }
        if !live.skipped.isEmpty {
            let ranges = live.skipped.map { "s\($0.lowerBound + 1)〜s\($0.upperBound)" }.joined(separator: "、")
            notes.append("判定できなかった範囲があります: \(ranges)")
        }
        return notes
    }
}

private struct ChecklistView: View {
    let session: Session
    let live: SessionModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("質問").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 12)
                ForEach(session.questions) { row($0) }
                if live?.isActive == true {
                    Text("クリックすると、手動でチェックを付け外しできます。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 12).padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(.background)
    }

    private func row(_ question: Question) -> some View {
        let check = session.checks.first { $0.questionID == question.id }
        let checked = check?.checked == true
        return Button {
            if live?.isActive == true { live?.toggle(question) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Color.askGreen : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.text).fontWeight(.medium)
                    if let detail = detail(check) {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(checked ? Color.askGreen.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(checked ? "聞いた" : "まだ")
    }

    private func detail(_ check: Check?) -> String? {
        guard let check else { return nil }
        if check.checked, let evidence = check.evidence {
            let start = check.evidenceIndices?.min().flatMap { session.segments.indices.contains($0) ? session.segments[$0].start : nil }
            return (start.map(JudgeRequest.timestamp) ?? "") + "「\(evidence)」"
        }
        if check.manual { return check.checked ? "手動でチェックしました" : "手動で外しました（自動では付けません）" }
        return nil
    }
}

private struct TranscriptView: View {
    let session: Session
    let highlighted: Set<Int>
    let volatileText: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Text("文字起こし").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 10)
                    ForEach(Array(session.segments.enumerated()), id: \.offset) { index, segment in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(JudgeRequest.timestamp(segment.start))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(segment.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(highlighted.contains(index) ? Color.askGreen.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !volatileText.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("認識中").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                            Text(volatileText).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                    if !highlighted.isEmpty {
                        Text("緑の行は、チェックの根拠になった発言です。")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 10).padding(.top, 8)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: session.segments.count) { proxy.scrollTo("bottom") }
            .onChange(of: volatileText) { proxy.scrollTo("bottom") }
        }
    }
}
