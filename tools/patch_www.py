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


# --------------------------------------------------------------------------
# 读档兜底
#
# 「点 Continue → 进游戏 → 点什么都没反应」的根因是读档这条路上一抛异常就没人管了：
# 事件层在异常前已经被 hideEventLayer() 关掉，而 kag.tag.js 的点击处理里有
#     if (layer_event 不可见) return false
# 所以整局再也收不到点击。异常来源至少有三种：
#   1. 存档结构不对（比如从别的版本 / 别的 configSave 格式存下来的）→ getSaveData 返回的不是对象
#   2. 某个 .event-setting-element 缺 data-event-pm → JSON.parse(undefined) 抛
#   3. 存档里的 current_order_index 在当前版本的剧本文件里已经不存在
# 这里把每处都包住，失败就走 __sylvie_load_fail：恢复交互 + 回标题 + 说明原因。
# --------------------------------------------------------------------------

LOAD_GUARD_JS = r"""

/* ===== 读档兜底（本移植版加入，不是原包内容）=====
   读档路上有几处会抛异常（存档结构不对 / 索引超出剧本 / 某个 tag 找不到……），
   一抛异常整局就点不动了：事件层是关着的，引擎也不再推进。
   这里保证任何一步失败都能恢复成可操作的状态，并且告诉玩家发生了什么。 */
window.__sylvie_load_fail = function (e) {
  var msg = (e && e.message) ? e.message : String(e);
  try {
    var k = TYRANO.kag;
    k.stat.is_adding_text = false;   // 这几个标志任何一个残留，点击都会被引擎忽略
    k.stat.is_click_text = false;
    k.stat.is_strong_stop = false;
    k.stat.is_stop = false;
    k.layer.showEventLayer();
  } catch (_) {}
  try {
    TYRANO.kag.ftag.nextOrderWithIndex(-1, "sys/title_screen.ks");   // 游戏自己也是这么回标题的
  } catch (_) {
    try { TYRANO.kag.ftag.nextOrderWithLabel("*title", "sys/title_screen.ks"); } catch (__) {}
  }
  try {
    alert("读档失败，已经回到标题画面。\n\n"
        + "这个存档多半来自旧版本的数据（各版本的存档不通用）。\n"
        + "选 Start 重新开始即可。\n\n"
        + "详情：" + msg);
  } catch (_) {}
};

/* 读档后如果事件层一直关着，说明有东西没跑完（媒体没起来、某一步悄悄失败……），
   这时把交互恢复回来，免得整屏点不动。 */
window.__sylvie_watch_load = function () {
  var n = 0;
  var timer = setInterval(function () {
    n++;
    var k = window.TYRANO && TYRANO.kag;
    if (!k || !k.layer) { clearInterval(timer); return; }
    var hidden = k.layer.layer_event.css("display") == "none";
    if (!hidden) { clearInterval(timer); return; }          // 正常了
    if (k.stat.is_adding_text == true) return;              // 正在逐字显示，正常
    if (k.stat.is_strong_stop == true) { if (n > 12) clearInterval(timer); return; }
    if (n > 4) {                                            // 2 秒还没恢复，强制恢复
      try { k.stat.is_stop = false; k.layer.showEventLayer(); } catch (_) {}
      clearInterval(timer);
    }
  }, 500);
};
"""

LOAD_EDITS = [
    # (old, new, 说明)
    (
        'getSaveData:function(){var tmp_array=$.getStorage(this.kag.config.projectID+"_tyrano_data",'
        'this.kag.config.configSave);if(tmp_array)return JSON.parse(tmp_array);else{'
        'tmp_array=new Array;var root={kind:"save"};',
        'getSaveData:function(){var __raw=null,__root=null;try{__raw=$.getStorage('
        'this.kag.config.projectID+"_tyrano_data",this.kag.config.configSave);if(__raw){'
        '__root=JSON.parse(__raw);if(__root&&typeof __root=="object"&&__root.data instanceof Array'
        '&&__root.data.length)return __root}}catch(__e){}if(1){'
        'var tmp_array=new Array;var root={kind:"save"};',
        "存档结构不对时不再往外抛异常（否则点 Continue 直接卡死）",
    ),
    (
        'loadGame:function(num){var array_save=this.getSaveData();var array=array_save.data;'
        'if(array[num].save_date=="")return;var auto_next="no";'
        'if(array[num].stat.load_auto_next==true)auto_next="yes";'
        'this.loadGameData($.extend(true,{},array[num]),{"auto_next":auto_next})},',
        'loadGame:function(num){try{var array_save=this.getSaveData();var array=array_save.data;'
        'if(!array||!array[num])return;if(array[num].save_date=="")return;var auto_next="no";'
        'if(array[num].stat&&array[num].stat.load_auto_next==true)auto_next="yes";'
        'if(window.__sylvie_watch_load)window.__sylvie_watch_load();'
        'this.loadGameData($.extend(true,{},array[num]),{"auto_next":auto_next})}catch(e){'
        'window.__sylvie_load_fail(e)}},',
        "读档整段包住，失败时恢复交互并给出说明",
    ),
    (
        '$(".event-setting-element").each(function(){var j_elm=$(this);'
        'var kind=j_elm.attr("data-event-tag");var pm=JSON.parse(j_elm.attr("data-event-pm"));'
        'var event_tag=object(tyrano.plugin.kag.tag[kind]);event_tag.setEvent(j_elm,pm)});',
        '$(".event-setting-element").each(function(){try{var j_elm=$(this);'
        'var kind=j_elm.attr("data-event-tag");var pm=JSON.parse(j_elm.attr("data-event-pm"));'
        'var event_tag=object(tyrano.plugin.kag.tag[kind]);'
        'if(event_tag&&event_tag.setEvent)event_tag.setEvent(j_elm,pm)}catch(__e){}});',
        "事件重绑定的异常不再中断读档（否则 make.ks 那一步永远不会执行）",
    ),
    (
        'this.kag.clearTmpVariable();\nthis.kag.ftag.nextOrderWithIndex(data.current_order_index,'
        'data.stat.current_scenario,true,insert,"yes")},',
        'this.kag.clearTmpVariable();try{this.kag.ftag.nextOrderWithIndex(data.current_order_index,'
        'data.stat.current_scenario,true,insert,"yes")}catch(e){window.__sylvie_load_fail(e)}},',
        "索引/剧本文件对不上时不再静默卡死",
    ),
]


def install_load_guard():
    """Make the save-load path fail-safe (idempotent)."""
    rel = "tyrano/plugins/kag/kag.menu.js"
    path = os.path.join(WWW, rel)
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    if "__sylvie_load_fail" in text:
        print("  [已是最新] 读档兜底")
        return 0
    changed = 0
    for old, new, desc in LOAD_EDITS:
        if old not in text:
            print(f"  [警告] {rel}: 找不到目标片段 —— {desc}")
            continue
        text = text.replace(old, new, 1)
        changed += 1
    text = text.rstrip("\n") + "\n" + LOAD_GUARD_JS
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text)
    print(f"  [已加] 读档兜底（{changed}/{len(LOAD_EDITS)} 处改动 + 兜底函数）")
    return changed


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
    print("== 读档兜底 ==")
    total += install_load_guard()
    print("== 界面 ==")
    total += install_skip_button()
    print(f"共修改 {total} 处")
    return 0


if __name__ == "__main__":
    sys.exit(main())
