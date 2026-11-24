import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension QuestionList {
    /// 1 行 1 質問。箇条書きの記号（- * ・ 1. ① - [ ] など）を取り、空行と見出し（#）は飛ばす
    static func parseQuestions(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var item = line.trimmingCharacters(in: .whitespaces)
            guard !item.hasPrefix("#") else { return nil }
            if let marker = item.range(of: #"^(?:[-*•・]\s*(?:\[[ xX]\]\s*)?|\d+[.)．）]\s*|[①-⑳]\s*)"#,
                                       options: .regularExpression) {
                item.removeSubrange(marker)
            }
            item = item.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }
}

enum MarkdownExport {
    /// 質問ごとの ✓ と根拠、続けて全文の書き起こし
    static func render(_ session: Session, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["# \(session.listTitle)", "",
                     "- 開始: \(formatter.string(from: session.startedAt))",
                     "- 終了: \(session.endedAt.map(formatter.string) ?? "（中断）")",
                     "", "## 質問", ""]
        for question in session.questions {
            let check = session.checks.first { $0.questionID == question.id }
            let checked = check?.checked == true
            lines.append("- [\(checked ? "x" : " ")] \(question.text)")
            if checked, let evidence = check?.evidence { lines.append("  - 根拠: 「\(evidence)」") }
        }
        lines += ["", "## 書き起こし", ""]
        lines += session.segments.map { "- [\(JudgeRequest.timestamp($0.start))] \($0.text)" }
        return lines.joined(separator: "\n") + "\n"
    }
}

nonisolated struct MarkdownFile: FileDocument {
    static let readableContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
