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

### 3. 读档兜底（点 Continue 卡死）

「读档进游戏后点什么都没反应」的根因：**读档这条路上任何一处抛异常，整局就死了** ——
异常发生前 `hideEventLayer()` 已经把事件层关掉，而 `kag.tag.js` 的点击处理里有

```js
if (that.kag.layer.layer_event.css("display") == "none" && is_strong_stop != true) return false;
```

所以事件层关着 = 所有点击被吞掉。可抛异常的地方至少三处：

1. `getSaveData()` —— 存档结构不对（比如来自别的版本、别种 `configSave` 格式）时
   `JSON.parse` 出来的不是对象，后面 `array[num].save_date` 直接 TypeError
2. `.event-setting-element` 缺 `data-event-pm` 时 `JSON.parse(undefined)` 抛，
   **`nextOrderWithIndex(…, make.ks, …)` 就永远不会执行**（状态停在半路）
3. 存档里的 `current_order_index` 在当前剧本文件里已经不存在

`tools/patch_www.py` 的 `install_load_guard()` 把每处都包住，失败时执行
`__sylvie_load_fail()`：清掉 `is_adding_text` / `is_click_text` / `is_strong_stop` / `is_stop`
这四个只要残留就会让点击失效的标志 → `showEventLayer()` → 弹一句话说明 → 回标题画面
（用游戏自己的 `sys/title_screen.ks`）。另有一个 `__sylvie_watch_load()` 看门狗：
读档后 2 秒内事件层还是关着（媒体没起来、某步悄悄失败）就强制恢复交互。

### 3. 界面：跳过答题按钮

答题环节（`intro/opening.ks` 里那 9 道题）**答错一题就 game over**。
`tools/patch_www.py` 会往 `index.html` 里塞一个「跳过答题」按钮：

- 只在答题环节出现 —— 起止行是从剧本里现算的（找 `[button target="*ok"` 和 `*tgcs`），
  改剧情也不会失准；标题画面、日常剧情里不会出现
- 点击后跳到 `*tgcs`（全对才走的那段「通過測試了！男人告辭」，立绘状态在那一段里重建，
  不能直接跳到 `step1.ks`）
- 位置固定在右上角：横屏下正好落在游戏画面右侧的黑边里，不压任何按钮
- 两个坑：
  1. 引擎把点击绑在 `document` 上，按钮里必须 `stopPropagation()`，
     否则这一下会同时被当成「推进剧情」
  2. `nextOrder()` 在文字逐字显示时（`is_adding_text`）会直接 `return false`，
     点太早会没反应 —— 所以先打开引擎自己的 `is_click_text`（就是「点一下把这句话显示完」的开关），
     再跳

不想要这个按钮：把它从 `index.html` 里删掉即可（`<!-- ===== 跳过答题按钮` 到对应的 `</script>`），
或者干脆不跑这一步。

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
2. <App Bundle>/www                  ← 自包含版（烘焙过的 IPA 走这条）
```

把改好的 `www` 整个放进去即可。1.5 GB / 13,000 个文件，用 Filza 比「文件」App 快得多。

## 上面这些修正是有脚本的

`tools/` 里的脚本把 APK 直接变成 iOS 能跑的 `www`，不用手工改文件：

```sh
# 1. 解出 APK 里的游戏本体（assets/ 就是 www 的内容）
unzip 希露薇の交配計劃.apk 'assets/index.html' 'assets/tyrano/*' 'assets/data/*' \
      'assets/package.json' 'assets/tyrano_player.js' -d apk

# 2. 媒体转码（45 个 .ogg -> .m4a，25 个 .webm -> .mp4，约 1 分钟）
sh tools/transcode.sh apk/assets

# 3. 打引擎补丁（幂等，可反复执行；做了什么它自己会打印）
python3 tools/patch_www.py apk/assets

# 4. （可选）烘焙成自包含 IPA，装完即玩
python3 tools/bake_ipa.py build/SylvieGame-unsigned.ipa apk/assets build/SylvieGame-baked.ipa
```

`tools/serve.py` 是本机预览用的静态服务器（支持 Range，`-m http.server` 不支持，
WebKit 就没法 seek `<video>`）：

```sh
python3 tools/serve.py 8765 apk/assets        # 浏览器开 http://127.0.0.1:8765/index.html
```

### 一个兜底机制：内容覆盖

`LocalServer` 会在服务文件前先看一眼 App 包里的 `patches/<相对路径>`，命中就优先返回它。
**当前包里没有任何覆盖文件，所以这条路是空的** —— 这是刻意留的逃生口：
以后若要改剧情，把改好的文件按同样相对路径放进工程的 `Content/patches/`，
推一次代码（1.6 MB 的 App）就能生效，**不用让你重新复制 1.5 GB 的 www**。

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
