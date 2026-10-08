# ver769.zip — 内容分析报告

## 一、文件本质

| 项目 | 值 |
|---|---|
| 文件名 | `ver769.zip` |
| 实际类型 | **Android APK**（ZIP 容器，含 `AndroidManifest.xml` + `classes.dex` + `resources.arsc` + `META-INF/CERT.RSA`） |
| 大小 | 1,354,936,509 字节（≈1.26 GiB） |
| 解压后 | ≈1.58 GB / 13,972 个文件（大部分是 **0 字节的伪文件占位**） |
| 应用名 | **【希露薇の交配計劃MOD】ver7.6.9** |
| 原名 | `TeachingFeeling`（教える少女 / Teaching Feeling，作者 Ray-Kbys） |
| 类型 | 中文粉丝 **MOD 版**，基于日文原作追加内容 |
| 引擎 | **TyranoBuilder / TyranoScript**（HTML5 视觉小说引擎） |
| 外壳 | Cordova + **XWalk**（`lib/armeabi-v7a/libxwalkcore.so`、`assets/xwalk-command-line`） |
| 附带 | 一个完整的 **NW.js macOS 应用包**（`TeachingFeeling.app`、`nwjs Framework.framework`），是作者打包时误带进去的开发文件 |

> 结论：这不是普通压缩包，而是**手机端 Galgame 的安装包（APK）被改名成了 .zip**。

## 二、目录结构

```
ver769/
├── AndroidManifest.xml      # 安卓清单
├── classes.dex              # Android 字节码
├── resources.arsc           # 编译后的资源表
├── META-INF/                # 签名文件（CERT.RSA / CERT.SF / MANIFEST.MF）
├── lib/armeabi-v7a/         # XWalk 原生库（libxwalkcore.so ≈ 数十 MB）
├── res/                     # 安卓图标 / 布局（mipmap-*、layout-*、drawable-*）
└── assets/
    ├── xwalk-command-line
    └── www/                 # ← 游戏本体（TyranoScript 工程）
        ├── index.html       # 引擎加载入口
        ├── tyrano/          # TyranoScript 引擎（kag 插件、libs、css）
        ├── Omake/           # 原日文「おまけ」编辑器说明 + 原创服装图
        ├── data/
        │   ├── scenario/    # ★ 剧本脚本（.ks，80 个文件 / 约 29,676 行）
        │   ├── image/       # 立绘 / 服装 / UI（1,350 文件，44 MB）
        │   ├── bgimage/     # 背景（193 文件，124 MB）
        │   ├── fgimage/     # 前景 / 表情差分（11,337 文件，1.1 GB）
        │   ├── bgm/         # 背景音乐（22 首，97 MB）
        │   ├── sound/       # 音效（23 个，12 MB）
        │   ├── video/       # 过场动画（25 个 MP4，92 MB）
        │   ├── system/      # Config.tjs / KeyConfig.js
        │   └── startup.tjs
        ├── node_modules/    # 打包残留（fs-extra 等）
        └── TeachingFeeling.app/   # 打包残留的 macOS NW.js 版
```

## 三、剧本（`.ks` 脚本）分布

| 目录 | 内容 | 主要文件 |
|---|---|---|
| `intro/` | 序章剧情 | `opening.ks`、`event.ks`、`step1–5.ks`、`town.ks` |
| `talk/` | 日常对话系统 | `text.ks`(39 KB)、`words.ks`、`select.ks`、`touch.ks`、`nade.ks`、`name.ks` |
| `act_with/` | 与女主外出事件 | `shop.ks`(143 KB，最大)、`cafe.ks`、`wine.ks`、`market.ks`、`dinner.ks`、`tea.ks` |
| `act_alone/` | 独自行动 | `shop_night.ks`、`cafe_alone.ks`、`ferrum.ks` |
| `H/` | 成人向剧本（26 个） | `mouth.ks`(81 KB)、`missional.ks`、`Hx.ks`、`morning.ks`、`nurse.ks`、`rape.ks`、`sexless1–3.ks` |
| `sys/` | 系统界面 | `dress_ex.ks`(153 KB，换装)、`dress.ks`、`config.ks`、`system.ks`、`memory.ks`、`title_screen.ks`、`update_info.ks` |
| `pre/` | 预处理 / 宏 | `macro.ks`(104 KB)、`set_show.ks`、`face.ks`、`chara_define.ks`、`exp.ks` |
| `mk/` | 特殊分支 | `mk-1.ks` |
| 另有 | `scenario old/`、`scenario_beta/` | 旧版与测试版备份剧本 |

## 四、版本与内容线索

- 标题栏硬编码：`[title name="【希露薇の交配計劃MOD】ver7.6.9"]`
- `sys/update_info.ks` 里有 **v10 → v21+** 的更新记录按钮，说明 MOD 已经过多轮迭代
- `first.ks` 中被注释掉的**密码门槛**：`ふりむけばカエル`（"回头一看是青蛙"），用于限制测试版流传
- MOD 作者标识：**REBEL-POWER**（爱发电 / 公众号），序章中作者借 NPC 之口自嘲
- 附带的 `Omake/` 说明文档是**日文原版**的，MOD 在其上做了中文汉化与扩展

## 五、可玩性说明

游戏本身是 **HTML5（TyranoScript）**，理论上可直接在浏览器中加载
`assets/www/index.html` 运行。但：
- 依赖 `data/` 下 1.4 GB 素材，移动端 WebView 加载会很吃力；
- 内容为 **R-18 成人向**，请自行留意。

## 六、已提取到工作区

解压路径：`/var/minis/workspace/ver769/ver769/assets/www/`
（已跳过 `node_modules/` 与 `TeachingFeeling.app/` 以节省空间）
