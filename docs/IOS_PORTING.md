# ver769 → iOS (IPA) 移植笔记

## 结论
**可以移植，而且比一般安卓游戏容易得多** —— 游戏本体是 100% HTML5/JS（TyranoScript），
唯一的原生依赖是 Android 的 XWalk WebView 外壳。换成 iOS 的 WKWebView 即可，游戏代码无需改动。

## 有利条件（实测确认）
- 引擎自带 iOS 分支，作者做过跨平台：
  - `$.userenv()` 在本机返回 `"iphone"` → 引擎走移动端分支（视频点击解锁 + `playsinline`）
  - 引擎里已有 `$.getBrowser()=="safari"` 的音频格式映射逻辑
- `fetch` 实测：`.ks`（剧本）、`.mp4`（视频）、`.mp3`（音频）全部 200 可读
- 首次加载后 `TYRANO.kag.stat.map_macro` 注册了 **1065 个宏**，引擎初始化成功

## 必须修的 3 个坑

### 1. 视频引用 `.webm`，但包里只有 `.mp4`（35 处）
`data/scenario/**/*.ks` 里 35 处 `storage="xxx.webm"`，而 `data/video/` 下全是 `.mp4`。
→ 修复：全量 `sed 's/\.webm"/.mp4"/g'`
（引擎在 PC 分支做的是 `.mp4 → .webm`，说明剧本本意就该是 `.mp4`）

### 2. Safari 下 `.ogg` 被映射成 `.m4a`，但包里只有 `.mp3`
`tyrano/plugins/kag/kag.tag_audio.js` 里有：
```js
if(browser=="msie"||browser=="safari"||browser=="edge") storage = $.replaceAll(storage,".ogg",".m4a");
```
iOS WebKit 的 `$.getBrowser()` 返回 `"safari"` → 引擎去找 `Silver_Glass.m4a` → 404。
→ 修复：把映射目标改成 `.mp3`

### 3. 自定义 URL scheme 下媒体加载失败（需要 HTTP Range）
`minis://` 之类的自定义 scheme 不支持 Range 请求，`<video>` 直接 `networkState=3 (NO_SOURCE)`。
→ 真正的 IPA 必须用 `file://`（需正确配置）或内置 HTTP 服务（如 GCDWebServer）来伺服素材。

## 三大构建障碍
1. **不能在 iPhone 上生成 IPA** —— 编译 + 签名 iOS 应用必须有 Xcode（Mac）或云端 macOS runner。
   iOS 设备本身没有编译链；iSH 只是 Linux aarch64 用户态模拟，产不出 IPA。
2. **签名**：侧载需 Apple ID 免费证书（7 天有效期）或 $99/年 开发者账号，配 Sideloadly / AltStore。
3. **App Store 不可能上架**（R-18 内容）。

## 三条路线

| 路线 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. 不做 IPA** | 用 Safari 以本地 HTTP 服务打开 `index.html`（PWA） | 今天就能跑，零签名 | 无原生整合；后台会断 |
| **B. 套壳 + 云编译** | Cordova/Capacitor iOS 空白模板 + 放入 `www/`；用 GitHub Actions 的 macOS runner 出未签名 IPA，再本地签名 | 不用买 Mac | 需一次云编译 |
| **C. 完整重打包** | `cordova platform add ios`，改 `Info.plist` | 最正统 | 步骤最多 |

### C 路线关键 Info.plist / 配置项
- `UISupportedInterfaceOrientations`：仅竖屏
- `UIStatusBarHidden = true`、`UIViewControllerBasedStatusBarAppearance = false`
- WKWebView 配置：`mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone`
  （否则 iOS 会拦截 BGM 自动播放，和安卓行为不一致）
- `NSAppTransportSecurity`：允许本地 `file://` / http

## 体积
- 原始 APK 1.26 GB；解压后 1.58 GB / 13972 文件
- 进 IPA 约 1.2 GB（`data/fgimage` 1.1 GB 是主要占用）
- 可安全删除：`lib/`（XWalk）、`assets/www/node_modules/`、`assets/www/TeachingFeeling.app/`（macOS NW.js 残留）

## 本地调试存档
- 工作副本：`/var/minis/workspace/ver769/ver769/assets/www/`
- 剧本备份：`data/scenario.bak/`（打补丁前的原版）
- 本地 HTTP 服务：`python3 -m http.server 8765 --bind 127.0.0.1`（工作目录 = www/）
