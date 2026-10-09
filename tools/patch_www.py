#!/usr/bin/env python3
"""Idempotent iOS fixes for the TyranoScript game data.

Runs against <www>/ and only changes what still needs changing, so it is safe
to re-run.  Each fix exists because WebKit on iOS behaves differently from the
desktop browsers the game was written for.

Usage: python3 patch_www.py [www_root]
"""
import os
import re
import sys

WWW = sys.argv[1] if len(sys.argv) > 1 else "assets"

EDITS = [
    # (relative path, old, new, human description)
    (
        "index.html",
        '<meta name="viewport" content=" user-scalable=no" />',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no" />',
        "viewport: 补 width=device-width（否则 iOS 按 980px 布局视口算，画面居中会算错）",
    ),
    (
        "tyrano/tyrano.base.js",
        "window.scrollTo(width, height);",
        "window.scrollTo(0, 0);",
        "居中双重偏移：引擎设好 left 后又横向滚一次",
    ),
    (
        "tyrano/plugins/kag/kag.tag_audio.js",
        "else if(this.kag.tmp.ready_audio==false)",
        "else if(false)",
        "去掉移动端的 click.bgm 门槛（App 已放行自动播放，不必等一次点击）",
    ),
    (
        "tyrano/plugins/kag/kag.tag_ext.js",
        'video.load();video.addEventListener("canplay",(function(){video.style.display="";video.play()}))}};',
        'video.load();video.addEventListener("canplay",(function(){video.style.display="";video.play()}));'
        'var __vstart=false;video.addEventListener("playing",function(){__vstart=true});'
        'var __vfail=function(){if(__vstart)return;__vstart=true;try{$(".tyrano_base").find("video").remove();'
        'if("true"==pm.bgmode){that.kag.tmp.video_playing=false;'
        'if(1==that.kag.stat.is_wait_bgmovie){that.kag.stat.is_wait_bgmovie=false;that.kag.ftag.nextOrder()}}'
        'else{that.kag.ftag.nextOrder()}}catch(e){}};'
        'video.addEventListener("error",__vfail);setTimeout(__vfail,8000)}};',
        "影片放不出来时移除并继续（否则 [movie]/[wait_bgmovie] 会永远等 ended）",
    ),
    (
        "tyrano/plugins/kag/kag.tag_audio.js",
        '$(audio_obj).off("play");$(audio_obj).on("play",function(){that.kag.layer.showEventLayer();if(pm.stop=="false")that.kag.ftag.nextOrder()});audio_obj.play();',
        '$(audio_obj).off("play");var __played=false;$(audio_obj).on("play",function(){if(__played)return;__played=true;that.kag.layer.showEventLayer();if(pm.stop=="false")that.kag.ftag.nextOrder()});audio_obj.play();setTimeout(function(){if(!__played){__played=true;that.kag.layer.showEventLayer();if(pm.stop=="false")that.kag.ftag.nextOrder()}},1500);',
        "音频 play 事件加 1.5s 兜底（引擎只在 play 事件里推进剧情，媒体失败=永久卡死）",
    ),
    (
        "data/system/Config.tjs",
        ";configSave     = file",
        ";configSave     = webstorage_compress",
        "存档方式：file 是 NW.js/PC 专有，网页端会存不进；改存 localStorage",
    ),
]


def patch_file(rel, old, new, desc):
    path = os.path.join(WWW, rel)
    if not os.path.exists(path):
        print(f"  [跳过] {rel}: 文件不存在")
        return 0
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    n = text.count(old)
    if n == 0:
        if new in text:
            print(f"  [已是最新] {desc}")
        else:
            print(f"  [警告] {rel}: 找不到目标文本")
        return 0
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text.replace(old, new))
    print(f"  [已修] {desc}  ({rel} × {n})")
    return n


def patch_scenarios():
    """Re-point every .webm reference at the .mp4 we just transcoded to."""
    root = os.path.join(WWW, "data", "scenario")
    hits = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.endswith(".ks"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="surrogateescape") as fh:
                text = fh.read()
            if ".webm" not in text:
                continue
            count = text.count(".webm")
            with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(text.replace(".webm", ".mp4"))
            hits[os.path.relpath(path, root)] = count
    if hits:
        for rel, n in sorted(hits.items()):
            print(f"  [已修] .webm -> .mp4  ({rel} × {n})")
    else:
        print("  [已是最新] 剧本里已无 .webm 引用")
    return sum(hits.values())


def main():
    print(f"www root: {WWW}")
    print("== 引擎与配置 ==")
    total = 0
    for rel, old, new, desc in EDITS:
        total += patch_file(rel, old, new, desc)
    print("== 剧本媒体引用 ==")
    total += patch_scenarios()
    print(f"共修改 {total} 处")
    return 0


if __name__ == "__main__":
    sys.exit(main())
