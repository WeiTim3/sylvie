# 希露薇の交配計劃 MOD v7.6.9 — 网页版运行笔记（方案 A）

## 状态：✅ 可玩

游戏已在本机跑通：标题画面、Start 按钮、序章（`intro/opening.ks`）全部正常。
在 Minis 内置浏览器里 **用手指点按** 即可游玩。

---

## 怎么启动

```sh
sh /var/minis/workspace/ver769/play.sh          # 默认 8765 端口
```

然后在内置浏览器打开：

```
http://127.0.0.1:8765/index.html
```

> 服务器只在 Minis 处于前台时存活。切到别的 App 会被系统挂起。

## 启动流程（前两下点按是必须的）

1. **点一下屏幕** → 引擎尝试播放 logo 影片
2. 影片在本 WebView 里无法解码，**约 5 秒后自动跳过**（或再点一下立即跳过）
3. **再点一下** → 解锁音频通道（iOS 的媒体手势限制）
4. 出现标题画面 → **点 Start** 开始游戏

---

## 改了什么（全部在 `/var/minis/workspace/ver769/ver769/assets/www/`）

### 1. 新增 `wkwrap-shim.js`（核心修复）
**症状**：整个画面纯黑，引擎无报错。
**根因**：内置 WebView 的 `document.visibilityState === "hidden"`，
`requestAnimationFrame` **完全不触发**，CSS 动画时钟停在 0。
TyranoScript 的转场给图层加 `animated fadeIn`，动画永远停在 `from` 关键帧
（`opacity: 0`）→ 黑屏；更糟的是引擎用 `.one("animationend", cb)` 等待，
该事件永不触发 → 卡死。

**做法**：探测帧时钟是否停摆；若停摆则
- 用 `setTimeout` 兜底 `requestAnimationFrame`（jQuery 动画依赖它）
- 用 `getAnimations()[].finish()` 手动推进 `animated` 元素并补发 `animationend`

帧正常时自动关闭，不影响真机/真浏览器。已在 `index.html` 中于 jQuery **之前**引入。

### 2. `data/scenario/**` — `.webm` → `.mp4`（35 处）
剧本引用 `.webm`，包里只有 `.mp4`。全量替换。
（原版备份：`data/scenario.bak/`）

### 3. `tyrano/plugins/kag/kag.tag_audio.js`
- `.ogg` 的浏览器映射：`safari → .m4a` 改成 `.mp3`（包里只有 mp3）
- **关键**：引擎只在音频 `play` 事件里恢复事件层并 `nextOrder()`：
  ```js
  $(audio_obj).on("play", function(){ showEventLayer(); nextOrder(); });
  ```
  媒体被拦截时 `play` 永不触发 → 事件层永远 `display:none` → **点击全无反应**。
  加了 1.2s 兜底：音频起不来就静默继续。
  （备份：`kag.tag_audio.js.orig`）

### 4. `tyrano/plugins/kag/kag.tag_ext.js` — 影片失败兜底
`playVideo()` 追加 `error` 监听 + 5s 超时；加载不出来就移除 `<video>` 并继续，
避免 `movie` / `bgmovie` 卡死。（备份：`kag.tag_ext.js.orig`）

---

## 已知限制

| 项 | 说明 |
|---|---|
| **无音视频** | 内置 WebView 完全禁止媒体解码（`.mp3`/`.mp4` 均 `networkState=3`，远程地址也一样）。BGM / 音效 / H 场景动画都会跳过。真机 Safari 里应当正常。 |
| **无过渡动画** | 帧时钟停摆，转场变成瞬切。 |
| **按钮要点按** | 引擎在 iOS 下绑的是 `touchstart`/`tap` 而非 `click`，所以用鼠标/脚本点击无效——**必须用手指点**。 |
| **体积** | 1.4 GB 素材按需加载，首次进入某场景会有一瞬卡顿。 |

## 相关文件

- `serve.py` —— 支持 HTTP Range 的静态服务器（`python3 -m http.server` 不支持 Range，会让 `<video>` 加载失败）
- `play.sh` —— 一键启动
- `IOS_PORTING_NOTES.md` —— 若要改成 IPA 的完整分析
- `APP_REPORT.md` —— 包内容分析
