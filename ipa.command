#!/bin/bash
# Двойной щелчок: собирает «Студию» для AltStore и кладёт Studio.ipa на рабочий стол.
# Подпись не нужна: AltStore сам подписывает приложение твоим Apple ID.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
LOG="$HOME/Desktop/studio-ipa.log"
xcodegen generate >/dev/null || { echo "IPA: FAIL (xcodegen)"; read -r -p "Enter, чтобы закрыть"; exit 1; }
echo "Собираю 1–3 минуты…"
rm -rf build/ipa
if ! xcodebuild -project CreatorStudio.xcodeproj -scheme CreatorStudio -configuration Release \
     -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath build/dd \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -20
  echo "IPA: FAIL (лог: $LOG)"; read -r -p "Enter, чтобы закрыть"; exit 1
fi
APP=$(find build/dd/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -1)
mkdir -p build/ipa/Payload && cp -R "$APP" build/ipa/Payload/
rm -f "$HOME/Desktop/Studio.ipa"
(cd build/ipa && zip -qry "$HOME/Desktop/Studio.ipa" Payload)
echo "IPA: OK → $HOME/Desktop/Studio.ipa"
read -r -p "Enter, чтобы закрыть"
