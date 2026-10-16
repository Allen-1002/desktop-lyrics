#!/bin/bash
# 编译并安装到“应用程序”文件夹，之后就像普通软件一样从启动台或聚焦搜索打开
set -euo pipefail
cd "$(dirname "$0")/.."

# 第一次安装时创建本机签名证书，这样以后更新不用重新授权
if ! security find-identity -v -p codesigning | grep -q "DesktopLyrics Local Signing"; then
    ./scripts/setup-signing.sh
fi
./scripts/build-app.sh

DEST="/Applications/桌面歌词.app"
# 先退出正在运行的桌面歌词（包括从 build 文件夹打开的那个）
pkill -x DesktopLyrics || true
sleep 1

rm -rf "${DEST}"
cp -R build/DesktopLyrics.app "${DEST}"
echo "已安装到 ${DEST}"
open "${DEST}"
