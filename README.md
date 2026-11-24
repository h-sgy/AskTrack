# AskTrack

対面のインタビューやヒアリング中の会話をリアルタイムで文字起こしし、事前に登録した質問リストのうち「もう聞いた質問」を自動でチェックする macOS アプリです。聞き漏れを防ぎます。

> 開発中です。設計は [DESIGN.md](DESIGN.md)、タスクは [TASKS.md](TASKS.md) を参照してください。

## 動作環境

- Apple Silicon の Mac
- macOS 26 以降

## インストール

[Releases](https://github.com/h-sgy/AskTrack/releases) から最新の zip をダウンロードし、展開した `AskTrack.app` を「アプリケーション」フォルダに移動します。以後のアップデートは、アプリ内で自動的に届きます。

## 送信するデータとプライバシー

- **音声はどこにも送らず、保存もしません。** 文字起こしは Mac の中（Apple の音声認識）で行います。
- 判定に外部の LLM（Claude / OpenAI / Gemini）を選んだ場合は、**書き起こしのテキストと質問リストが、そのプロバイダに送られます。** API キーはご自身のものを使い、Mac の Keychain にだけ保存します。
  - OpenAI には、応答をサーバー側に保存しない設定（`store: false`）で送ります。
  - **Gemini の無料枠のキーを使うと、送った内容が Google の製品改善に使われます。** 機密性の高いヒアリングでは、有料枠のキーを使ってください。
- Apple のオンデバイス LLM を選んだ場合は、外部に何も送りません。
- 書き起こしと判定結果は、この Mac の `~/Library/Application Support/AskTrack/` にだけ保存します。
- アップデートの確認のため、`https://h-sgy.github.io/AskTrack/appcast.xml` にアクセスします。

## 録音について

会話を録音・文字起こしするときは、事前に相手に伝えて了承を得てください。

## ビルド

```sh
brew install xcodegen   # project.yml を変更する場合のみ必要
xcodegen generate
open AskTrack.xcodeproj
```

署名は作者の証明書を前提にしています。ご自身でビルドする場合は、`project.yml` の `DEVELOPMENT_TEAM` と `CODE_SIGN_IDENTITY` を変更してください。

## ライセンス

MIT（[LICENSE](LICENSE)）。アプリが使っている Sparkle のライセンスは、アプリの「AskTrack について」から確認できます。
