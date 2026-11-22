#!/bin/bash
# 双击运行（macOS）：读取本地微信 WebView 里的厦大体育 hrefstr，
# 复制到剪贴板并原样显示，按回车关闭窗口。
#
# 权限记在「终端」名下——终端通常已有完全磁盘访问权限，所以不需要给新程序单独授权。
set -u

cd "$(dirname "$0")" || exit 1

# 从 Release 下载后本文件也带 quarantine 标记，顺手去掉（只影响本文件）。
xattr -d com.apple.quarantine "$0" 2>/dev/null || true

if ! href=$(./get_hrefstr.sh); then
    cat >&2 <<'EOF'

读取失败。常见原因：
  1. 还没在微信里打开过『厦大体育 → 场馆预约』（打开一次，让页面写入 LocalStorage）
  2. 终端没有「完全磁盘访问权限」
     系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 打开「终端」
EOF
    [ -t 0 ] && read -r -p "按回车关闭…" _
    exit 1
fi

printf '%s' "$href" | pbcopy
echo "hrefstr 已复制到剪贴板（长度 ${#href} 字符）："
echo
echo "$href"
echo
[ -t 0 ] && read -r -p "按回车关闭…" _

exit 0
