#!/bin/bash
# Создаёт Xcode-проект из project.yml и открывает его. Запуск: двойной клик.
cd "$(dirname "$0")" || exit 1
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Нужен Homebrew: https://brew.sh (одна команда установки с сайта), потом запусти этот файл снова."
    read -r -p "Нажми Enter, чтобы закрыть"; exit 1
  fi
  echo "Ставлю XcodeGen…"; brew install xcodegen || exit 1
fi
xcodegen generate || { read -r -p "Ошибка генерации. Enter, чтобы закрыть"; exit 1; }
echo "PROJECT: OK"
open CreatorStudio.xcodeproj
