#!/usr/bin/env bash
# 读取厦大体育 H5 hrefstr（macOS / Linux 入口）。
# 优先用本目录 runtime/ 里的便携 Python（免安装），没有才退回系统 python3。
# 本脚本不读也不写凭据，只把参数转发给 get_hrefstr.py。
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/get_hrefstr.py"

case "$(uname -m)" in
    arm64|aarch64) ARCH="arm64" ;;
    x86_64|amd64)  ARCH="x86_64" ;;
    *)             ARCH="" ;;
esac

# 从 Release 压缩包解出来的文件和便携 Python 会带 quarantine 标记，
# 未签名的运行时会被 Gatekeeper 直接 SIGKILL（"Killed: 9"）；这里静默清掉本目录的标记。
RT="$DIR/runtime/macos-$ARCH"
if [ -n "$ARCH" ] && [ -e "$RT/bin/python3" ] && xattr "$RT/bin/python3" 2>/dev/null | grep -q quarantine; then
    xattr -dr com.apple.quarantine "$DIR/runtime" 2>/dev/null || true
fi

PY=""
# 1) 随包便携运行时：本平台目录优先，其次 runtime/ 下任意能跑起来的
for d in "$DIR/runtime/macos-$ARCH" "$DIR/runtime/linux-$ARCH" "$DIR"/runtime/*; do
    [ -x "$d/bin/python3" ] || continue
    if "$d/bin/python3" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        PY="$d/bin/python3"
        break
    fi
done

# 2) 系统里的 python3 / python
if [ -z "$PY" ]; then
    for cand in python3 python; do
        if command -v "$cand" >/dev/null 2>&1 \
           && "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
            PY="$cand"
            break
        fi
    done
fi

if [ -z "$PY" ]; then
    echo "未找到可用的 Python 3.8+，本目录也没有内置运行时。" >&2
    echo "跑一次 ./fetch_runtime.sh 自动下载（约 24MB，只影响本目录），" >&2
    echo "或直接执行：python3 \"$SCRIPT\" $*" >&2
    exit 2
fi

exec "$PY" "$SCRIPT" "$@"
