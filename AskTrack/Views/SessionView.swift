import SwiftUI

struct SessionView: View {
    @State private var model = SessionModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(model.state == .recording ? "停止" : "録音開始") {
                    model.state == .recording ? model.stop() : model.start()
                }
                .disabled(model.state == .preparing)
                ProgressView(value: model.level)
                    .frame(width: 120)
                    .help("マイクの入力レベル")
                if let message = model.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(model.segments.enumerated()), id: \.offset) { _, segment in
                        Text("[\(Self.timestamp(segment.start))] \(segment.text)")
                    }
                    if !model.volatileText.isEmpty {
                        Text(model.volatileText).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: model.segments.count) { proxy.scrollTo("bottom") }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
