#!/bin/bash
# Двойной щелчок: собирает проект и прогоняет все тесты на симуляторе iPhone.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
xcodegen generate >/dev/null || { echo "TESTS: FAIL (xcodegen)"; read -r -p "Enter, чтобы закрыть"; exit 1; }
SIM=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$SIM" ]; then echo "TESTS: FAIL (нет симулятора iPhone: Xcode → Settings → Components)"; read -r -p "Enter, чтобы закрыть"; exit 1; fi
LOG="$HOME/Desktop/creator-studio-tests.log"
echo "Тесты идут 1–3 минуты…"
if xcodebuild test -project CreatorStudio.xcodeproj -scheme CreatorStudio -destination "id=$SIM" > "$LOG" 2>&1; then
  grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
  echo "TESTS: OK"
else
  grep -E "error:|failed|FAILED" "$LOG" | head -30
  echo "TESTS: FAIL (полный лог: $LOG)"
fi
read -r -p "Enter, чтобы закрыть"
