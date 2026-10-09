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

WWW = sys.argv[1] if len(sys.argv) > 1 else "/var/minis/workspace/sylvie/apk/assets"

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


SKIP_BUTTON = r'''
<!-- ===== 跳过答题按钮（本移植版加入，不是原包内容） =====
     只在答题环节出现；答题起止行从剧本里现算，改剧情也不会失准。 -->
<style>
#skip_quiz_btn{position:fixed;right:10px;top:10px;z-index:2147483000;display:none;
  padding:9px 16px;border-radius:19px;background:rgba(0,0,0,.55);
  border:1px solid rgba(255,255,255,.5);color:#fff;
  font:15px/1 -apple-system,"PingFang SC","Hiragino Sans",sans-serif;
  letter-spacing:1px;-webkit-user-select:none;user-select:none;
  touch-action:manipulation;box-shadow:0 1px 6px rgba(0,0,0,.4)}
#skip_quiz_btn:active{background:rgba(255,255,255,.3)}
</style>
<div id="skip_quiz_btn">跳过答题</div>
<script>
(function () {
  var SCENARIO = 'intro/opening.ks';
  var PASS_LABEL = '*tgcs';          // 答题全对后走的那一段
  var btn = document.getElementById('skip_quiz_btn');
  var range = null, scanned = false, shown = false, pending = 0;

  function scan() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', './data/scenario/' + SCENARIO, true);
    xhr.onload = function () {
      try {
        var lines = xhr.responseText.split('\n'), start = -1, end = lines.length;
        for (var i = 0; i < lines.length; i++) {
          var t = lines[i].replace(/\s/g, '');
          if (start < 0 && t.indexOf('[buttontarget="*ok"') >= 0) start = i;
          else if (start >= 0 && /^\*(tgcs|mtgcs)/.test(t)) { end = i; break; }
        }
        if (start >= 0) range = {start: start, end: end};
      } catch (e) {}
      scanned = true;
    };
    xhr.onerror = function () { scanned = true; };
    try { xhr.send(); } catch (e) { scanned = true; }
  }

  function inQuiz() {
    try {
      var k = window.TYRANO && TYRANO.kag;
      if (!k || !k.stat || k.stat.current_scenario !== SCENARIO) return false;
      if (!range) return scanned && k.stat.current_line > 70;   // 扫不出来时退一步判断
      return k.stat.current_line >= range.start && k.stat.current_line < range.end;
    } catch (e) { return false; }
  }

  function sync() {
    if (!scanned) scan();
    var want = inQuiz() && pending === 0;
    if (want !== shown) { shown = want; btn.style.display = want ? 'block' : 'none'; }
  }
  setInterval(sync, 250);

  function inQuizNow() {
    return inQuiz();
  }

  // 引擎的 nextOrder() 在文字还在逐字显示时会直接 return false（is_adding_text），
  // 所以这一下大概率被吞掉 —— 等它打完再跳，不必让用户重点一次。
  function doJump(tries) {
    try {
      var k = TYRANO.kag;
      if (k.stat.is_adding_text) {
        if (tries > 0) setTimeout(function () { doJump(tries - 1); }, 250);
        else pending = 0;
        return;
      }
      k.ftag.nextOrderWithLabel(PASS_LABEL, SCENARIO);
      setTimeout(function () {
        try {
          if (TYRANO.kag.stat.current_scenario === SCENARIO && inQuizNow()) {
            if (tries > 0) doJump(tries - 1);
            else pending = 0;
          } else {
            pending = 0;                       // 跳过去了
          }
        } catch (e) { pending = 0; }
      }, 300);
    } catch (e) { pending = 0; }
  }

  function skip(ev) {
    // 引擎把点击绑在 document 上，不拦住的话这一下会同时被当成"推进剧情"
    ev.preventDefault();
    ev.stopPropagation();
    if (!inQuiz()) return;
    pending++;
    shown = false;
    btn.style.display = 'none';
    try {
      // 这就是引擎自己"点一下把这句话显示完"用的开关，打开它当前这句会立刻打完，
      // 否则 nextOrder() 会因为 is_adding_text 拒绝跳转
      if (TYRANO.kag.stat.is_adding_text) TYRANO.kag.stat.is_click_text = true;
    } catch (e) {}
    doJump(20);
  }
  ['click', 'touchstart', 'touchend'].forEach(function (type) {
    btn.addEventListener(type, skip, {passive: false});
  });
})();
</script>
'''


def install_skip_button():
    """Drop the skip-the-quiz button into index.html (idempotent, refreshes old versions)."""
    path = os.path.join(WWW, "index.html")
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    had = 'id="skip_quiz_btn"' in text
    # 老版本先摘掉，再重新插一遍，这样脚本升级不用手工处理
    stripped = re.sub(r"\n?<!-- ===== 跳过答题按钮.*?</script>\n", "\n", text, flags=re.S)
    if stripped != text:
        text = stripped
    if "</body>" not in text:
        print("  [警告] index.html 里没有 </body>，跳过按钮没插进去")
        return 0
    text = text.replace("</body>", SKIP_BUTTON + "</body>", 1)
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text)
    print("  [已更新] 跳过答题按钮（只在答题环节出现）" if had
          else "  [已加] 跳过答题按钮（只在答题环节出现）")
    return 1


def main():
    print(f"www root: {WWW}")
    print("== 引擎与配置 ==")
    total = 0
    for rel, old, new, desc in EDITS:
        total += patch_file(rel, old, new, desc)
    print("== 剧本媒体引用 ==")
    total += patch_scenarios()
    print("== 界面 ==")
    total += install_skip_button()
    print(f"共修改 {total} 处")
    return 0


if __name__ == "__main__":
    sys.exit(main())
