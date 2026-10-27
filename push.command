#!/bin/bash
# Отправляет код на GitHub. Запуск: двойной клик.
cd "$(dirname "$0")" || exit 1
git remote get-url origin >/dev/null 2>&1 || git remote add origin https://github.com/mathiasmichaelweiss/creator-studio-ios.git
git branch -M main
if git push -u origin main; then
  echo "PUSH: OK"
else
  echo "PUSH: ОШИБКА, пришли скриншот этого окна"
fi
read -r -p "Нажми Enter, чтобы закрыть"
