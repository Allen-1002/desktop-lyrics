#!/bin/bash
# 编译并封装成 build/桌面歌词-<版本>.dmg：打开后把“桌面歌词”拖进“应用程序”即可安装
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/桌面歌词-${VERSION}.dmg"
STAGE="build/dmg"

rm -rf "${STAGE}" && mkdir -p "${STAGE}"
cp -R build/DesktopLyrics.app "${STAGE}/桌面歌词.app"
ln -s /Applications "${STAGE}/应用程序"

hdiutil create -volname "桌面歌词" -srcfolder "${STAGE}" -format UDZO -ov "${DMG}" >/dev/null
rm -rf "${STAGE}"
echo "已生成 ${DMG}"
