#!/usr/bin/env bash
# 下载「便携 Python」到 runtime/（免安装、只写本目录、不需要管理员权限）。
#
#   ./fetch_runtime.sh                    # 自动选当前平台
#   ./fetch_runtime.sh windows-amd64      # 也可以下别的平台，方便打包发给别人
#
# 支持的平台名：macos-arm64 macos-x86_64 linux-x86_64 linux-arm64 windows-amd64 windows-arm64
# 产物位置：runtime/<平台名>/（get_hrefstr.sh 与 get_hrefstr.command 会自动优先使用）
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${RUNTIME_DIR:-$DIR/runtime}"

# 便携运行时版本（python-build-standalone 的 release tag）
PB_TAG="20261110"
PB_VER="3.12.16"
# Windows 用官方 embeddable 包（更小）
EMBED_VER="3.13.9"

asset_for() {
    case "$1" in
        macos-arm64)    echo "cpython-$PB_VER+$PB_TAG-aarch64-apple-darwin-install_only.tar.gz" ;;
        macos-x86_64)   echo "cpython-$PB_VER+$PB_TAG-x86_64-apple-darwin-install_only.tar.gz" ;;
        linux-x86_64)   echo "cpython-$PB_VER+$PB_TAG-x86_64-unknown-linux-gnu-install_only.tar.gz" ;;
        linux-arm64)    echo "cpython-$PB_VER+$PB_TAG-aarch64-unknown-linux-gnu-install_only.tar.gz" ;;
        *)              echo "" ;;
    esac
}

detect_platform() {
    case "$(uname -s)/$(uname -m)" in
        Darwin/arm64)            echo macos-arm64 ;;
        Darwin/x86_64)           echo macos-x86_64 ;;
        Linux/x86_64)            echo linux-x86_64 ;;
        Linux/aarch64|Linux/arm64) echo linux-arm64 ;;
        *)                       echo "" ;;
    esac
}

TARGET="${1:-$(detect_platform)}"
if [ -z "$TARGET" ]; then
    echo "无法判断当前平台（$(uname -s) $(uname -m)），请显式指定，例如：./fetch_runtime.sh linux-x86_64" >&2
    exit 2
fi

DEST="$OUT_ROOT/$TARGET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT_ROOT"

fetch() {  # fetch <url> <outfile>
    # GitHub / npmmirror 的 HTTP/2 偶尔抽风，强制 HTTP/1.1 更稳。
    curl -fsSL --http1.1 --retry 3 --retry-delay 2 -m 600 -o "$2" "$1"
}

case "$TARGET" in
    windows-*)
        case "$TARGET" in
            windows-amd64) WIN_ARCH="amd64" ;;
            windows-arm64) WIN_ARCH="arm64" ;;
            *) echo "未知的 Windows 平台名：$TARGET" >&2; exit 2 ;;
        esac
        ZIP="$TMP/python.zip"
        echo "下载 Python ${EMBED_VER} (${WIN_ARCH}) …"
        fetch "https://registry.npmmirror.com/-/binary/python/$EMBED_VER/python-$EMBED_VER-embed-$WIN_ARCH.zip" "$ZIP" \
            || fetch "https://www.python.org/ftp/python/$EMBED_VER/python-$EMBED_VER-embed-$WIN_ARCH.zip" "$ZIP"
        rm -rf "$DEST"; mkdir -p "$DEST"
        if command -v unzip >/dev/null 2>&1; then
            unzip -q "$ZIP" -d "$DEST"
        else
            python3 -m zipfile -e "$ZIP" "$DEST"
        fi
        [ -f "$DEST/python.exe" ] || { echo "解压后没看到 python.exe" >&2; exit 1; }
        echo "完成：${DEST} ($(du -sh "${DEST}" | awk "{print \$1}"))"
        ;;
    macos-*|linux-*)
        ASSET="$(asset_for "$TARGET")"
        if [ -z "$ASSET" ]; then
            echo "未知平台名：${TARGET}" >&2
            exit 2
        fi
        TGZ="$TMP/python.tar.gz"
        echo "下载 Python ${PB_VER} (${TARGET}) …"
        fetch "https://github.com/astral-sh/python-build-standalone/releases/download/$PB_TAG/$ASSET" "$TGZ"
        rm -rf "$DEST"; mkdir -p "$DEST"
        # 包内顶层是 python/，剥掉后得到 bin/ lib/ 直接可用
        tar -xzf "$TGZ" -C "$DEST" --strip-components=1
        [ -x "$DEST/bin/python3" ] || { echo "解压后没看到 bin/python3" >&2; exit 1; }
        "$DEST/bin/python3" -V
        echo "完成：${DEST} ($(du -sh "${DEST}" | awk "{print \$1}"))"
        ;;
    *)
        echo "未知平台名：${TARGET}" >&2
        exit 2
        ;;
esac
