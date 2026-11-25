import Foundation
import Testing
@testable import AskTrack

@Test func parsesPastedBulletLists() {
    let text = """
    # 顧客ヒアリング
    - 現在の業務フローは？
    * 予算は？
    ・決裁者は？
    1. 導入時期は？
    2) 競合は？
    ① 課題は？
    - [ ] 体制は？
    - [x] 期限は？

       そのまま書いた質問
    """
    #expect(QuestionList.parseQuestions(text) == [
        "現在の業務フローは？", "予算は？", "決裁者は？", "導入時期は？", "競合は？", "課題は？", "体制は？", "期限は？", "そのまま書いた質問",
    ])
}

@Test func skipsBoldHeadingsAndStripsTimestampLinks() {
    // 動画の要約メモをそのまま貼ったときの形
    let text = """
    * **自己紹介について**
    * 簡単な自己紹介をしてもらえるか [[03:07](https://example.com/watch?v=x&t=187)]

    **料金について**
    * いくらくらいかかるのか [12:34]
    * 詳細は[公式サイト](https://example.com)にあるのか
    """
    #expect(QuestionList.parseQuestions(text) == ["簡単な自己紹介をしてもらえるか", "いくらくらいかかるのか", "詳細は公式サイトにあるのか"])
}

@Test func allBoldItemsAreQuestionsNotHeadings() {
    // 全部が太字なら、見出しではなく質問そのもの
    let text = """
    1. **自己紹介と全体像について**
    2. **一番伸びた記事の具体例について**
    """
    #expect(QuestionList.parseQuestions(text) == ["自己紹介と全体像について", "一番伸びた記事の具体例について"])
}

@Test func doesNotStripHyphenatedWords() {
    #expect(QuestionList.parseQuestions("B-to-B の比率は？") == ["B-to-B の比率は？"])
}

@Test func rendersMarkdownExport() {
    let budget = Question(text: "予算は？")
    let owner = Question(text: "決裁者は？")
    let start = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
    var session = Session(listTitle: "顧客ヒアリング", startedAt: start, endedAt: start.addingTimeInterval(3600),
                          questions: [budget, owner])
    session.segments = [Segment(start: 65, text: "予算はどのくらいですか")]
    session.upsert(Check(questionID: budget.id, checked: true, at: start, evidence: "予算はどのくらいですか", manual: false))

    #expect(MarkdownExport.render(session, timeZone: TimeZone(identifier: "UTC")!) == """
    # 顧客ヒアリング

    - 開始: 2027-01-15 08:00
    - 終了: 2027-01-15 09:00

    ## 質問

    - [x] 予算は？
      - 根拠: 「予算はどのくらいですか」
    - [ ] 決裁者は？

    ## 書き起こし

    - [01:05] 予算はどのくらいですか

    """)
}
