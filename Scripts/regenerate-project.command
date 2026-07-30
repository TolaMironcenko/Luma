#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen не найден. Установите его командой: brew install xcodegen"
  read -r -p "Нажмите Enter, чтобы закрыть окно…"
  exit 1
fi

xcodegen generate
open Luma.xcodeproj
