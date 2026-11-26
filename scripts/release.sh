#!/bin/bash
# AskTrack をビルド・公証して GitHub Releases で公開し、Sparkle の appcast を更新する。
# 最初のダウンロード用に dmg、自動更新（Sparkle）用に zip を作る。
#
# 使い方: NOTARY_PROFILE=<notarytool のプロファイル名> scripts/release.sh <version>
#         DRY_RUN=1 を付けると、公開（Release 作成・appcast 更新）の直前で止まる
#
# 前提: Developer ID Application 証明書、`xcrun notarytool store-credentials` で作ったプロファイル、
#       Keychain にある Sparkle の秘密鍵（account: AskTrack）、gh の認証
set -euo pipefail

VERSION="${1:?使い方: NOTARY_PROFILE=<プロファイル名> scripts/release.sh <version>}"
: "${NOTARY_PROFILE:?環境変数 NOTARY_PROFILE に notarytool のプロファイル名を指定してください}"

cd "$(dirname "$0")/.."

# 公開するビルドとタグが、push 済みの main と一致するようにする
[ -z "$(git status --porcelain)" ] || { echo "commit していない変更があります" >&2; exit 1; }
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main を push してから実行してください" >&2; exit 1; }

BUILD=$(git rev-list --count HEAD)   # Sparkle は CFBundleVersion で新旧を比べるので、必ず増える値にする
OUT=build/release/$VERSION
ZIP=AskTrack-$VERSION.zip
DMG=AskTrack-$VERSION.dmg
APP=$OUT/AskTrack.app
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
rm -rf "$OUT" && mkdir -p "$OUT"

echo "==> archive ($VERSION, build $BUILD)"
xcodebuild -quiet -project AskTrack.xcodeproj -scheme AskTrack -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData -archivePath "$OUT/AskTrack.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive

echo "==> export (Developer ID)"
xcodebuild -quiet -exportArchive -archivePath "$OUT/AskTrack.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$OUT"

echo "==> notarize"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP"
ditto -c -k --keepParent "$APP" "$OUT/$ZIP"

echo "==> dmg"
# 開くと「アプリケーション」フォルダへドラッグする画面になる。移さずに起動すると自動更新できないため
mkdir "$OUT/dmg"
ditto "$APP" "$OUT/dmg/AskTrack.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname AskTrack -srcfolder "$OUT/dmg" -format UDZO "$OUT/$DMG"
codesign --sign "Developer ID Application" --timestamp "$OUT/$DMG"
xcrun notarytool submit "$OUT/$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUT/$DMG"
spctl --assess --type open --context context:primary-signature -vv "$OUT/$DMG"

echo "==> sign for Sparkle"
SIG=$("$SPARKLE_BIN/sign_update" --account AskTrack "$OUT/$ZIP")
export ITEM="    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url=\"https://github.com/h-sgy/AskTrack/releases/download/v$VERSION/$ZIP\" $SIG type=\"application/octet-stream\"/>
    </item>"
echo "$ITEM"

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "==> DRY_RUN: 公開せずに終了（成果物: ${OUT}/${DMG}, ${OUT}/${ZIP}）"
  exit 0
fi

echo "==> GitHub Release"
gh release create "v$VERSION" "$OUT/$DMG" "$OUT/$ZIP" --title "AskTrack $VERSION" --generate-notes

echo "==> appcast (gh-pages)"
WT=$(mktemp -d)
git worktree add -q --detach "$WT" origin/gh-pages
awk '/<\/channel>/ { print ENVIRON["ITEM"] } { print }' "$WT/appcast.xml" > "$WT/appcast.new"
mv "$WT/appcast.new" "$WT/appcast.xml"
git -C "$WT" commit -q -am "Release $VERSION"
git -C "$WT" push -q origin HEAD:gh-pages
git worktree remove "$WT"

echo "==> done: https://github.com/h-sgy/AskTrack/releases/tag/v$VERSION"
