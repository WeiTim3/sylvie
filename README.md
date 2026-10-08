# SylvieGame — 把「希露薇の交配計劃」装成一个真正的 iOS App

这是一个**壳工程**：一个极简的 WKWebView 容器 + 一条 GitHub Actions 流水线。
推到 GitHub 后，云端 macOS runner 会自动编译出**未签名 `.ipa`**，
再用 **TrollStore** 装到越狱设备上 —— 全程不需要 Mac、不需要 Apple ID、不需要签名。

## 为什么值得折腾

| | Minis 内置浏览器（现在） | 这个 App |
|---|---|---|
| BGM / 音效 | ❌ WebView 禁解码 | ✅ |
| 过场视频 | ❌ | ✅ |
| 转场动画 | ❌ 帧时钟停摆 | ✅ |
| 服务依赖 | 要一直开着 `serve.py` | 不需要 |
| 桌面图标 | ❌ | ✅ |
| 离线 | ❌ | ✅ |

关键就是这两行 WebView 配置，正是内置浏览器给不了的：

```swift
config.mediaTypesRequiringUserActionForPlayback = []   // 媒体不再被拦
config.allowsInlineMediaPlayback = true
```

---

## 一、拿到 IPA（约 5 分钟）

1. **建仓库**：github.com → New repository → 名字随便（如 `sylvie`）→
   选 **Public**（公开仓库的 macOS runner 免费）→ Create。

2. **上传本文件夹里的全部内容**（不是外层目录，是里面的文件）：
   ```
   project.yml
   Sources/
   Resources/
   .github/workflows/build-ipa.yml
   ```
   ⚠️ `.github/` 是隐藏目录，用网页版拖拽上传时**要把 `.github` 一起拖进去**，
   否则 Actions 不会触发。用 git 命令行最省事：
   ```sh
   cd ios
   git init && git add -A && git commit -m "init"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/sylvie.git
   git push -u origin main
   ```

3. **等编译**：仓库页 → **Actions** → 点进最新那次 run。
   大约 2–4 分钟（首次要装 XcodeGen，稍慢）。

4. **下载 IPA**：run 成功后，页面底部 **Artifacts** → 下载
   `SylvieGame-unsigned-ipa`（是个 zip，解压得到 `SylvieGame-unsigned.ipa`）。

## 二、装到手机上

越狱设备有好几种办法，任选：

- **TrollStore**（推荐）：把 `.ipa` 存到「文件」App，用 TrollStore 打开它 → Install
- **AppSync Unified + Filza**：装了 AppSync 后，Filza 里直接点 `.ipa` 安装
- **`ipainstaller`**：`ipainstaller /path/to/SylvieGame-unsigned.ipa`

装完桌面会出现图标「**希露薇**」。

## 三、把游戏素材放进去

App 会按这个顺序找 `index.html`：

1. `Documents/www/index.html` ← 正常情况用这个
2. `/var/mobile/Media/ver769/www/index.html` ← 越狱专用捷径
3. App 包内的 `www/`（本工程没打包素材）

### 方法 A：文件 App（不用越狱工具）

App 开了 `UIFileSharingEnabled`，所以「文件」App 里能直接看到它：

```
文件 App → 我的 iPhone → 希露薇 → 放一个 www 文件夹进去
```

### 方法 B：Filza（推荐，13000 个文件用文件 App 拖会很慢）

素材现在在 Minis 的容器里，用 Filza 复制：

```
源：/var/mobile/Containers/Data/Application/6FD95196-7E4F-4FC1-8080-A19B920965B8/
     Documents/alpine-rootfs/data/var/minis/workspace/ver769/ver769/assets/www

到：/var/mobile/Media/ver769/www
```

（`6FD95196-…` 这个 UUID 在本机有效；如果翻不到，就在 Minis 容器目录里
搜 `alpine-rootfs/data/var/minis/workspace/ver769`。）

放好后启动 App 即可。**注意**：`www` 里应该直接看到 `index.html`、
`tyrano/`、`data/`、`wkwrap-shim.js`。

---

## 已包含的修复

这个 `www` 是打好补丁的版本，原包的几个坑都修过了（详见 `../PLAY_NOTES.md`）：

1. `wkwrap-shim.js` — 帧时钟停摆时兜底（真机 Safari/App 里会自动关闭，无副作用）
2. 剧本 35 处 `.webm` → `.mp4`
3. `kag.tag_audio.js` — Safari 的 `.ogg`→`.m4a` 改成 `.mp3`，并给音频 `play` 事件加兜底
4. `kag.tag_ext.js` — 影片加载失败兜底

## 故障排查

| 现象 | 原因 |
|---|---|
| Actions 里没有 run | `.github/workflows/` 没上传上去（隐藏目录） |
| `xcodegen: command not found` | 这步失败通常是网络问题，重跑一次 |
| 编译报 `No such module` | 不应该发生，本工程零第三方依赖 |
| 装好后打开是「还没放游戏文件」 | `www` 位置不对，检查上面三个候选路径 |
| 白屏/黑屏 | 看 Xcode Console 或 `idevicesyslog` 里的 `[SylvieGame]` 日志 |
| 素材太大复制慢 | 13k 文件 / 1.4 GB，Filza 复制需要几分钟 |

## 想改成内置本地 HTTP 服务？

如果 `file://` 的 XHR 在某个 iOS 版本上被拦，把 `GameViewController` 换成
启动一个支持 Range 的本地 HTTP 服务、再 `load(URLRequest("http://127.0.0.1:PORT/"))`
即可（参考外层 `serve.py` 的逻辑）。**先试 file:// 版本**，多数情况够用。
