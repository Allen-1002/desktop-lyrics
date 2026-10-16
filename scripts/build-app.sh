#!/bin/bash
# 编译并打包成 build/DesktopLyrics.app（只需要命令行工具，不需要 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/DesktopLyrics.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/DesktopLyrics" "$APP/Contents/MacOS/DesktopLyrics"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "已生成 $APP"
echo "运行：open $APP"
