# getHrefstr —— 读取本地微信 WebView 中的厦大体育 hrefstr

从本机微信（Mac/Windows）内置 WebView 的 LocalStorage（LevelDB）里，读出厦大体育当前登录上下文 `hrefstr`（含 `uid/token/sign/...`），为后续“基于 hrefstr 登录 ”提供原始输入。**本工具只读取、不联网、不写盘、不打印任何额外身份字段。**

## 依赖

**不用安装 Python。** 脚本优先使用 `runtime/` 里的便携运行时。仓库不提交它（约 90 MB），第一次用先跑一次下载：

| 平台 | 下载方式 | 运行时 | 下载 → 解压体积 |
|---|---|---|---|
| macOS / Linux | `./fetch_runtime.sh` | CPython 3.12.16（python-build-standalone） | 24 MB → 68 MB |
| Windows | 双击 `fetch_runtime.bat` | CPython 3.13.9 embeddable | 11 MB → 20 MB |

- 都不需要安装、不需要管理员权限、不改 `PATH`，整个目录可以拷到别的机器上直接用。
- 已经下过（比如你本地这份目录）就直接双击启动；`runtime/` 被删了重新跑一次上面的命令即可。
- 系统里本来有 Python 3.8+ 的话，`runtime/` 缺失时会自动退化到用它，所以不下载也能跑。
- 代码只用标准库，LevelDB 读取器是纯 Python 实现（CCL Forensics，MIT），随附在 `_vendor/` 并保留许可证——所以便携运行时里不需要 `pip`。

## 用法

### 双击运行（macOS，最省事）

双击 `获取hrefstr.command`：弹出终端窗口，读出 hrefstr、复制到剪贴板并原样显示，按回车关闭。用的是本目录自带的便携 Python，不需要你装任何东西。

不用改 PATH，不用记参数，权限记在「终端」名下——终端一般早就被授予「完全磁盘访问权限」，所以不需要给新程序单独授权。若仍报 `Operation not permitted` 或「无法访问微信 WebView 配置目录」，去「系统设置 → 隐私与安全性 → 完全磁盘访问权限」把「终端」打开即可。

> 关于为什么不提供 `.app`：macOS 27 起，读取别的 App 的容器目录（微信数据就在 `~/Library/Containers/com.tencent.xinWeChat/`）默认拒绝、且不再弹窗询问，必须给该 App 单独授「完全磁盘访问权限」；而 osacompile 打的包缺少 bundle ID，系统设置里开关打开也匹配不上。`.command` 借用终端已有的权限，绕开这一整条链路。

### 双击运行（Windows）

双击 `get_hrefstr.bat`：读取 hrefstr、复制到剪贴板并显示，末尾显示「按任意键关闭窗口」后停住，不再是窗口一闪而过。

查找顺序是 `runtime\windows-amd64\python.exe` → `runtime\windows-arm64\python.exe` → `py -3` → `python` → `python3`，每一步都校验版本 ≥ 3.8；全都没有时会停住并提示用 `fetch_runtime.bat` 下载（约 11MB），或去装 Python。

### 命令行

```sh
# macOS / Linux
./get_hrefstr.sh                 # 自动定位并输出 hrefstr
./get_hrefstr.sh --json          # 输出 {"origin","hrefstr","source_db"}
./get_hrefstr.sh --verbose       # 在 stderr 打印定位过程

# Windows
get_hrefstr.bat
get_hrefstr.bat --json
```

等价地，也可以直接用 Python：

```sh
python3 get_hrefstr.py [--db DIR] [--profile DIR] [--origin URL] [--json] [--verbose]
```

- `--profile DIR`：指定 `webview_xxx`（或 `multitab_xxx`）配置目录，工具会自动找其下的 `Local Storage/leveldb`。
- `--db DIR`：直接指定 leveldb 目录（即包含 `CURRENT` 文件的那个目录）。
- 成功时 `hrefstr` 原样打印到 **stdout**（便于管道/重定向），诊断信息走 **stderr**。

退出码：`0` 成功；`1` 未找到/无有效 hrefstr；`2` 参数或环境问题。

## 注意事项

### 每次获取前

1. 在微信里打开 **「厦大体育 → 场馆预约」**，等页面加载完成——`hrefstr` 是那个 H5 写进微信 WebView LocalStorage 的，没打开过就没有数据。
2. 然后双击 `获取hrefstr.command`（macOS）或 `get_hrefstr.bat`（Windows），1–2 秒出结果。

`hrefstr` 里的 `token`/`sign` 有有效期。上层登录报鉴权失败时，回微信重新打开一次场馆预约页、重跑本工具即可，不用重启微信。

### 两平台速查

| | macOS | Windows |
|---|---|---|
| 怎么获取 | 双击 `获取hrefstr.command` | 双击 `get_hrefstr.bat` |
| 结果在哪 | 终端窗口显示，同时进剪贴板 | 窗口显示，同时进剪贴板；按任意键关闭 |
| 运行时从哪来 | `runtime/macos-arm64/`（已随包） | `runtime/windows-amd64/`（已随包） |
| 额外系统权限 | 「终端」需有完全磁盘访问权限 | 无 |
| 命令行等价物 | `./get_hrefstr.sh` | `get_hrefstr.bat` |

### 报错对照表

| 提示 | 原因与处理 |
|---|---|
| 当前 Origin 没有有效 hrefstr | 还没在本机微信里打开过场馆预约页，见上面「每次获取前」 |
| 读取期间微信存储发生变化 | 微信正在写 LocalStorage，退出微信后重试 |
| 当前为未实现的新版 h5_token 分支 | 微信已切新版登录方案，本工具只能读旧版 hrefstr |
| 无法访问微信 WebView 配置目录 / `Operation not permitted` | macOS：给「终端」（或 iTerm 等）完全磁盘访问权限 |
| 未能自动定位到含 hrefstr 的 Local Storage | macOS 先看 `--verbose` 输出；Windows 的自动搜索未在真机验证，用 `--db` 指定 leveldb 目录 |
| 未找到可用的 Python 3.8+ | Windows 双击 `fetch_runtime.bat`（约 11MB）或装 Python 3；macOS 跑 `./fetch_runtime.sh` |
| Windows 窗口一闪而过 | `.bat` 被存成了 LF 换行；必须 UTF-8（无 BOM）+ CRLF |

### 分发与维护

- 发给别人只带自己平台：macOS 用户带 `runtime/macos-arm64/`，Windows 用户带 `runtime/windows-amd64/`，另一个可以直接删掉。
- `runtime/` 不进仓库（已 `.gitignore`），克隆/解压后按上面「依赖」跑一次下载即可；也可以在一台 Mac 上把 Windows 那份取下来：`./fetch_runtime.sh windows-amd64`。
- `.bat` 必须保持 **UTF-8（无 BOM）+ CRLF**；用编辑器另存成 LF 会让 `goto` 失效，表现就是双击闪退。
- macOS 换机器、或换了终端 App（iTerm、Warp 等），都要重新确认那个 App 有完全磁盘访问权限。
- 便携运行时来自 python-build-standalone 和 python.org 官方 embeddable 包，不含 `pip`，本工具也用不到。
- 结果只进 stdout 和剪贴板，不落盘；`hrefstr` 含真实 `uid/token/sign`，不要粘到公开渠道或提交进仓库。

## 数据在哪

macOS（已在本机验证）：

```
~/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/web/profiles/webview_<hash>/Local Storage/leveldb
```

Windows（来自社区报告，**尚未在真实 Windows 机器上验证**，优先用 `--db`/`--profile`）：

```
%APPDATA%\Tencent\xwechat\radium\web\profiles\<hash>\Local Storage\leveldb   # 微信 4.x
%APPDATA%\Tencent\WeChat\...                                                  # 旧版候选
%USERPROFILE%\Documents\WeChat Files\...                                      # 旧版候选
```

自动定位规则：

- **macOS**：枚举 `radium/web/profiles/` 下的 `webview_*` 和 `multitab_*`，逐个检查是否含厦大 Origin 的 `hrefstr`。有一个匹配时直接输出，有多个匹配时列出数据库目录，可用 `--db` 指定。
- **Windows**：按上表候选根目录递归查找 `Local Storage/leveldb/CURRENT`（未验证）。

若自动定位失败，可运行 `./get_hrefstr.sh --verbose >/dev/null`。诊断信息会显示候选目录和跳过原因，读取成功时也会丢弃标准输出中的凭据。若提示当前 Origin 没有有效 `hrefstr`，在 Mac 版微信里打开「厦大体育 → 场馆预约」，等页面加载完成后重试。

## 原理与边界

- `hrefstr` 的键是 `_https://xdty.xmu.edu.cn\x00\x01hrefstr`，值带 Chromium 的编码标记字节（`0x00`=UTF-16LE / `0x01`=latin-1），脚本按标记解码，不猜测编码。
- 读取时会校验 LevelDB 清单/数据完整性，并检测读取期间微信是否并发写入；发现变化会中止并要求退出微信后重试，避免拿到撕裂数据。
- 若微信已切换到新版 `h5_token` 分支（LocalStorage 里 `isNewAjaxRes` 为真），脚本会明确报错而不是返回旧版 hrefstr——该分支目前不被上层登录模块支持。
- **隐私**：`hrefstr` 含真实 `uid/token/sign`。脚本只把它写到 stdout，不落盘、不写日志；请自行决定是否把它重定向到受保护的文件，且不要提交进版本库或终端历史。

## 与登录模块的衔接

`hrefstr` 是 URL 查询串（形如 `timestamp=...&nonce=...&...&token=...&sign=...`，含 `term_id`/`id` 前的所有字段）。拿到后：

```python
from auth import login  # 或 login_h5 / build_h5_context
session, info = login(lambda: parse_hrefstr(hrefstr))
```

多用户管理、`hrefstr` 的 URL 解码（`decodeURI` 语义）、缓存与轮换等，属后续工作，本目录暂不实现。
