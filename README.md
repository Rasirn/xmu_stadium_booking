# getHrefstr

从本机微信的 WebView 缓存里读出厦大体育的 `hrefstr`（登录上下文，含 `uid/token/sign`），供「基于 hrefstr 登录」使用。

只读本地文件：不联网、不写盘，结果只打印到屏幕和剪贴板。

## 快速开始

**先做一次**：在微信里打开「厦大体育 → 场馆预约」，等页面加载完成。`hrefstr` 是那个页面写进微信缓存的，没打开过就没有数据。

然后双击对应文件，**不需要安装 Python**：

| 平台 | 双击 | 结果 |
|---|---|---|
| macOS | `获取hrefstr.command` | 终端窗口显示，同时复制到剪贴板 |
| Windows | `get_hrefstr.bat` | 窗口显示，同时复制到剪贴板；按任意键关闭 |

- **整包下载**：[Releases](https://github.com/Rasirn/xmu_stadium_booking/releases/latest) 里有 macOS 和 Windows 两个压缩包，解压即用。
- **从仓库用**：`runtime/` 里没有运行时的话，macOS 跑 `./fetch_runtime.sh`、Windows 双击 `fetch_runtime.bat` 下载（24 MB / 11 MB），下完再双击启动。
- macOS 若提示 `Operation not permitted`，给「终端」开完全磁盘访问权限（系统设置 → 隐私与安全性）。

## 命令行

```sh
./get_hrefstr.sh                # macOS / Linux，stdout 即 hrefstr
./get_hrefstr.sh --json         # {"origin","hrefstr","source_db"}
./get_hrefstr.sh --verbose      # 在 stderr 打定位过程

get_hrefstr.bat                 # Windows
get_hrefstr.bat --json
```

参数：`--db DIR` 直接指定 leveldb 目录；`--profile DIR` 指定 `webview_xxx` 配置目录；`--origin URL` 换采集站点（默认厦大体育）。

退出码：`0` 成功；`1` 未找到或无有效 hrefstr；`2` 参数或环境问题。

## 数据在哪

macOS（已验证）：

```
~/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/web/profiles/webview_<hash>/Local Storage/leveldb
```

Windows（**未在真机验证**，优先用 `--db`）：

```
%APPDATA%\Tencent\xwechat\radium\web\profiles\<hash>\Local Storage\leveldb
```

自动定位失败时，`--verbose` 会列出候选目录和跳过原因；仍不行就用 `--db` 指到含 `CURRENT` 的那个 leveldb 目录。

## 常见问题

| 提示 | 处理 |
|---|---|
| 当前 Origin 没有有效 hrefstr | 按「快速开始」先打开一次场馆预约页 |
| 读取期间微信存储发生变化 | 微信正在写缓存，退出微信后重试 |
| 当前为未实现的新版 h5_token 分支 | 微信已换新版登录方案，本工具读不了 |
| macOS：`Operation not permitted` | 给「终端」完全磁盘访问权限 |
| macOS：双击 `.command` 提示没有执行权限 | 终端里执行一次 `chmod +x 获取hrefstr.command` |
| Windows：窗口一闪而过 | 开 cmd 进目录执行 `get_hrefstr.bat`，看具体报错 |
| 找不到 Local Storage | 用 `--db` 显式指定 leveldb 目录 |

## 注意

- `hrefstr` 里的 `token`/`sign` 会过期。上层登录报鉴权失败时，回微信重开一次场馆预约页再取即可。
- 结果含真实凭据，不要贴到公开渠道或提交进仓库。

## 实现

纯 Python 标准库，配 `_vendor/` 里随附的 CCL Forensics LevelDB 读取器（MIT）。键是 `_https://xdty.xmu.edu.cn\x00\x01hrefstr`，值按 Chromium 的标记字节解码（`0x00` UTF-16LE / `0x01` latin-1）；读取时校验清单并检测并发写入，发现微信正在写就中止，不会返回半截数据。
