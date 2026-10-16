#!/bin/bash
# 编译并打包成 build/DesktopLyrics.app（只需要命令行工具，不需要 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product DesktopLyrics
swift build -c release --product NowPlayingHelper
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/DesktopLyrics.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DesktopLyrics" "$APP/Contents/MacOS/DesktopLyrics"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 读取系统“正在播放”信息的组件（QQ音乐、浏览器等），由 /usr/bin/perl 加载
cp "$BIN_DIR/libNowPlayingHelper.dylib" "$APP/Contents/Resources/"
cp Resources/now-playing.pl "$APP/Contents/Resources/"
# 有本机证书（见 scripts/setup-signing.sh）就用它签名，系统授权在重新编译后仍然有效；
# 没有就用临时签名，每次重新编译后可能需要重新授权。
IDENTITY="DesktopLyrics Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libNowPlayingHelper.dylib"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "提示：没有找到本机签名证书，使用临时签名。运行一次 ./scripts/setup-signing.sh 可以避免每次重新授权。"
    codesign --force --sign - "$APP/Contents/Resources/libNowPlayingHelper.dylib"
    codesign --force --sign - "$APP"
fi

echo "已生成 $APP"
echo "运行：open $APP"
