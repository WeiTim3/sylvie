# SylvieGame

把 **【希露薇の交配計劃MOD】ver7.6.9**（原为 Android APK，TyranoScript 引擎）
变成一个真正能用的 iPhone 游戏。

游戏本体是纯 HTML5，所以这里做的事情是：**一个极小的原生壳 + 一套让 TyranoScript
在 WKWebView 里正常工作的兼容补丁**。壳只有 4 个 Swift 文件、零第三方依赖。

```
┌──────────────────────────────────────────────┐
│  SylvieGame.app            (221 KB 二进制)    │
│   ├ WKWebView  ──  TyranoScript 引擎 ── 剧本  │
│   ├ LocalServer  本地 HTTP 服务 (127.0.0.1)   │
│   └ Splash / 手势 / 触觉 / 诊断                │
└──────────────────────────────────────────────┘
              素材 (1.4 GB) 放在 Documents/www
```

---

## 目录

| 路径 | 作用 |
|---|---|
| `Sources/` | 壳（4 个 Swift 文件） |
| `Resources/` | 图标、启动图、启动背景色 |
| `patches/apply_www.py` | **把原版 APK 的 www 修成能在 WKWebView 跑** |
| `tools/serve.py` | 带 Range 支持的本地服务（浏览器调试用） |
| `tools/bake.py` | 把素材烘进 IPA，做自包含版 |
| `docs/IOS_PORTING.md` | 完整移植笔记（每个坑的根因与修法） |
| `docs/PACKAGE_ANALYSIS.md` | 原始 APK 内容分析 |
| `docs/WEB_PORT.md` | 备选方案：不装 App，用浏览器玩 |
| `.github/workflows/build-ipa.yml` | 云端编译出未签名 IPA |

---

## 编译与安装

```sh
git push          # 推到 main 即触发 GitHub Actions
```

约 2 分钟产出未签名 `.ipa`（Actions → 最新 run → Artifacts）。装法：

- **TrollStore**（推荐，iOS 14.0–16.6.1）：`.ipa` 存到「文件」→ TrollStore 打开 → Install
- 或越狱 + **AppSync Unified** + Filza 直接点 `.ipa`

> runner 必须是 `macos-15`：当前 XcodeGen 生成 `objectVersion 77`（Xcode 16 格式），
> `macos-14` 的 Xcode 15 打不开。

## 放素材

App 按顺序找 `index.html`：

```
1. <App Documents>/www              ← 常用
2. /var/mobile/Media/ver769/www      ← 越狱捷径
3. <App Bundle>/www                  ← 自包含版
```

`www` 里应直接看到 `index.html` / `tyrano/` / `data/`。

**素材必须先过一遍补丁**，否则黑屏：

```sh
python3 patches/apply_www.py /path/to/assets/www
```

## 内容覆盖（Content overrides）

`www` 有 1.4 GB、上万个文件，在手机上用 Filza 改剧情很痛苦。所以 App 支持一层覆盖：

```
App 包里  SylvieGame.app/patches/<相对路径>      ← 优先
游戏目录  Documents/www/<相对路径>
```

`Content/patches/` 以 **folder reference** 方式进工程，整棵树原样拷贝进 App，
所以 `Content/patches/data/scenario/intro/opening.ks` 会落到
`SylvieGame.app/patches/data/scenario/intro/opening.ks`，请求同路径时覆盖 Documents 里那份。

**当前覆盖的内容**：

| 文件 | 改动 | 原因 |
|---|---|---|
| `data/scenario/intro/opening.ks` | 入口两个按钮 → `[jump target="*y20"]` | 跳过 MOD 的 20 题答题闯关（答错任何一题直接 game over） |

要再加覆盖，把文件按同样的相对路径丢进 `Content/patches/` 即可。


---

## 操作

| 手势 | 行为 |
|---|---|
| 单击 | 推进对话（引擎自带） |
| **长按** | 快进（松手停止） |
| **双指点击** | 打开游戏菜单（存档 / 读档 / 设置 / 回想） |
| **三指点击** | 自动播放开关 |

切到后台自动静音，回前台继续。

---

## 这套补丁在修什么

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| 1 | 黑屏，无任何提示 | TyranoScript 用 `alert()` 报错，但没设 `WKUIDelegate`，弹窗被静默丢弃 | 实现 `runJavaScriptAlertPanelWithMessage` |
| 2 | `file not found: ./data/system/Config.tjs` | `tyrano/libs.js` 的 `$.loadText` 走 XHR，**WKWebView 禁止 `file://` 页面发 XHR** | 壳内嵌 HTTP 服务，改走 `http://127.0.0.1:<随机端口>` |
| 3 | 横屏画面贴右、左侧全黑 | `tyrano.base.js` 先设居中 `left`，再 `window.scrollTo(width, height)` **滚了同样的距离** → 双重偏移（竖屏时该值为 0，所以原版没暴露） | 引擎补丁 + 壳侧每 250ms 清 `scrollLeft` |
| 4 | 竖屏浪费 69% 屏幕 | 游戏是 1350×900（3:2） | 强制横屏，按高度缩放占宽 69% |
| 5 | 打开要点了才有画面 | TyranoScript 给移动端加的 `click.movie` / `click.bgm` 门槛 | 壳直接调用那两个带命名空间的 handler（不动普通 click，避免跳剧情） |
| 6 | 剧本引用 `.webm`，包里只有 `.mp4` | MOD 打包时没同步改剧本 | 全量替换（35 处） |
| 7 | 音频在 Safari 下被映射成 `.m4a`，包里只有 `.mp3` | 引擎的浏览器嗅探逻辑 | 改成映射 `.mp3` |
| 8 | 切后台 BGM 还在响 | WebKit 的媒体进程独立占用音频会话 | iOS 15+ `setAllMediaPlaybackSuspended` |

**为什么不用自定义 `WKURLSchemeHandler`**：AVFoundation 不认自定义 scheme，
这样音视频会全挂。必须走真 HTTP —— 这也是 `LocalServer.swift` 存在的原因（约 300 行，POSIX socket）。

---

## 已知无害噪音

| 现象 | 说明 |
|---|---|
| `LOAD-FAIL .../images/system/button_menu.png` | 这文件**本来就不在包里**，MOD 作者删了但 `kag.js` 仍引用 |
| `REJECT: The operation is not supported.` | 音视频 `play()` 的 promise 拒绝 |
| 上下/左右黑边 | 3:2 的游戏放在 19.5:9 的屏幕上，信箱式留黑是正确的（强行填满要裁掉 65% 宽度） |

## 授权

壳代码是自用的，随便改。**游戏的剧本、美术、音乐版权属于原作者 Ray-Kbys
及 MOD 制作者「雙態協會×希露薇Fans團」，不可再分发。**
