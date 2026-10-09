# SylvieGame

iPhone 上跑 **【希露薇の交配計劃MOD】ver8.0.3**。

游戏本体是纯 HTML5（TyranoScript 引擎），所以这里只做一件事：
**一个极小的原生壳 + 一份改好的游戏数据。**

```
Sources/            4 个 Swift 文件 · 566 行 · 零第三方依赖
Resources/          图标
.github/workflows/  云端编译出未签名 IPA
```

---

## 为什么需要这个壳

游戏是给**桌面浏览器**写的，直接塞进 iOS 的 WKWebView 会死在这几处：

| 问题 | 原因 | 解决 |
|---|---|---|
| 黑屏，地图都读不出来 | **WKWebView 禁止 `file://` 页面发 XHR**，而 TyranoScript 靠 XHR 读 `Config.tjs` 和所有 `.ks` | 壳内嵌一个本地 HTTP 服务，改走 `http://127.0.0.1:<端口>` |
| 报错看不见，只有黑屏 | TyranoScript 用 `alert()` 报错，而没设 `WKUIDelegate` 时弹窗被静默丢弃 | 实现 `runJavaScriptAlertPanelWithMessage` |
| 横屏画面贴右 | `tyrano.base.js` 先设居中 `left`、又 `window.scrollTo(width,height)` 滚了同样距离（竖屏时该值为 0 所以原版没暴露） | 游戏数据里改掉（见下） |
| 打开要点一下才有画面 | 引擎为移动浏览器加的 `click.movie` / `click.bgm` 自动播放门槛 | 游戏数据里去掉（本 App 已放行自动播放） |
| 存档丢失 | **localStorage 按 origin 隔离，而 origin 含端口**。随机端口 = 每次全新存储 | 端口固定（记住 18765），另存一份镜像文件兜底 |
| 切后台还在响 | WebKit 的媒体进程独立占着音频会话 | `setAllMediaPlaybackSuspended` |

**`file://` 那条是根本原因** —— 它决定了必须有本地 HTTP 服务。
（自定义 `WKURLSchemeHandler` 不行：AVFoundation 不认自定义 scheme，音视频会全挂。）

---

## 游戏数据的修正

素材放在 `Documents/www`（见下方"放素材"），但它必须先是 **iOS 可用的版本**：

### 1. 媒体转码（必须）

原包的音频是 **Vorbis `.ogg`**、视频是 **VP9 `.webm`** —— iOS 的 WebKit **两个都不支持**。

```sh
# 音频：44 个 .ogg -> .m4a (AAC)
ffmpeg -i x.ogg -c:a aac -b:a 128k x.m4a

# 视频：25 个 .webm -> .mp4 (H.264)
ffmpeg -i x.webm -c:v h264_videotoolbox -b:v 1200k -pix_fmt yuv420p \
       -c:a aac -b:a 96k -movflags +faststart x.mp4
```

音频**不用改剧本引用**：引擎在 Safari 下会自己做
`storage = replaceAll(storage, ".ogg", ".m4a")`，所以磁盘上是 `.m4a` 就够了。
视频则相反，剧本里的 `.webm` 引用要改成 `.mp4`（35 处，在 `pre/macro.ks` 和 `H/video.ks`）。

### 2. 引擎脚本修正（必须）

| 文件 | 改动 |
|---|---|
| `index.html` | viewport 补 `width=device-width`（否则 iOS 用 980px 布局视口，居中算错） |
| `tyrano/tyrano.base.js` | `window.scrollTo(width, height)` → `window.scrollTo(0, 0)`（2 处） |
| `tyrano/plugins/kag/kag.tag_audio.js` | 去掉 `click.bgm` 门槛；给音频 `play` 事件加超时兜底 |
| `tyrano/plugins/kag/kag.tag_ext.js` | 影片加载失败兜底（解不了就跳过，别卡死） |

> 8.0.3 的影片标签**已经不需要点击**了（新版直接 `playVideo`），这一项不用改。

---

## 编译

```sh
git push        # 推到 main 即触发 GitHub Actions
```

约 2 分钟出未签名 `.ipa`（Actions → 最新 run → Artifacts）。
runner 必须是 `macos-15`：当前 XcodeGen 生成 `objectVersion 77`，`macos-14` 的 Xcode 15 打不开。

## 安装

- **TrollStore**（iOS 14.0–16.6.1）：`.ipa` 存到「文件」→ TrollStore 打开 → Install
- 或越狱 + **AppSync Unified** + Filza 直接点 `.ipa`

## 放素材

App 按顺序找 `index.html`：

```
1. <App Documents>/www              ← 常用（可用「文件」App 传）
2. /var/mobile/Media/ver769/www      ← 越狱捷径
3. <App Bundle>/www                  ← 自包含版
```

把改好的 `www` 整个放进去即可。1.5 GB / 13,000 个文件，用 Filza 比「文件」App 快得多。

## 操作

| 操作 | 行为 |
|---|---|
| 点击画面 | 推进对话（引擎自带） |
| 切到后台 | 音频暂停 |
| 回到前台 | 继续 |

没有别的了 —— 这是刻意的。

## 授权

壳代码自用，随便改。**游戏的剧本、美术、音乐版权属于原作者 Ray-Kbys
及 MOD 制作者「雙態協會×希露薇Fans團」，不可再分发。**
