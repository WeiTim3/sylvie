#!/usr/bin/env python3
"""
Apply the iOS-port fixes to a raw `www/` extracted from the Android APK.

    python3 apply_www.py /path/to/assets/www

The script is idempotent: running it twice changes nothing.

Everything it does exists because TyranoScript assumes a desktop browser that
is allowed to do things WKWebView forbids. Each fix is listed below with the
symptom it cures -- see ../docs/IOS_PORTING.md for the full write-up.
"""
import os
import re
import sys
import shutil

# --------------------------------------------------------------------------
# Fix 4: the frame-starvation shim.
#
# In an embedded WebView whose document is "hidden", requestAnimationFrame
# never ticks and CSS animations sit at their `from` keyframe -- so TyranoScript
# crossfades leave layers at opacity:0 (a black screen) and the engine hangs
# waiting for an `animationend` that never fires. The shim drives those
# animations by hand and self-disables when frames are flowing normally.
# --------------------------------------------------------------------------
SHIM = r"""/*
 * wkwrap-shim.js -- compatibility layer for embedded WebViews that never
 * produce animation frames. Self-disabling: if requestAnimationFrame ticks,
 * this file does nothing at all.
 */
(function () {
  "use strict";
  var nativeRAF = window.requestAnimationFrame;
  var framesAlive = false;
  var polyfilled = false;

  function installPolyfill() {
    if (polyfilled) return;
    polyfilled = true;
    window.requestAnimationFrame = function (cb) {
      return setTimeout(function () { cb(Date.now()); }, 16);
    };
    window.cancelAnimationFrame = function (h) { clearTimeout(h); };
  }

  function probe() {
    if (typeof nativeRAF !== "function") {
      installPolyfill(); framesAlive = false; setTimeout(probe, 500); return;
    }
    var got = false;
    try { nativeRAF.call(window, function () { got = true; }); } catch (e) {}
    setTimeout(function () {
      framesAlive = got;
      if (!got) installPolyfill();
      setTimeout(probe, got ? 1500 : 250);
    }, 100);
  }

  var tracked = typeof WeakSet === "function" ? new WeakSet() : null;

  function fireAnimationEnd(el, name) {
    var types = ["animationend", "webkitAnimationEnd"];
    for (var i = 0; i < types.length; i++) {
      var ev;
      try {
        ev = new AnimationEvent(types[i], {
          animationName: name, elapsedTime: 1, bubbles: true, cancelable: false
        });
      } catch (e) {
        ev = document.createEvent("Event");
        ev.initEvent(types[i], true, false);
      }
      try { el.dispatchEvent(ev); } catch (e) {}
    }
  }

  function finishElement(el, attempt) {
    if (!el || el.nodeType !== 1 || !el.classList) return;
    var cls = el.className;
    if (typeof cls !== "string" || cls.indexOf("animated") === -1) return;
    attempt = attempt || 0;
    var name = "";
    try { name = getComputedStyle(el).animationName || ""; } catch (e) {}
    if (name === "none" || !name) name = "fadeIn";
    var anims = [];
    try { anims = el.getAnimations ? el.getAnimations() : []; } catch (e) {}
    if (anims.length) {
      for (var i = 0; i < anims.length; i++) { try { anims[i].finish(); } catch (e) {} }
      fireAnimationEnd(el, name);
      return;
    }
    if (attempt < 3) {
      setTimeout(function () { finishElement(el, attempt + 1); }, 40);
      return;
    }
    el.style.animation = "none";
    el.classList.remove("animated");
    if (/[Oo]ut$/.test(name)) el.style.opacity = "0";
    fireAnimationEnd(el, name);
  }

  function watch(node) {
    if (!node || node.nodeType !== 1) return;
    if (tracked) { if (tracked.has(node)) return; tracked.add(node); }
    if (node.className && typeof node.className === "string" &&
        node.className.indexOf("animated") !== -1) {
      setTimeout(function () { if (!framesAlive) finishElement(node); }, 30);
    }
    if (node.querySelectorAll) {
      var kids = node.querySelectorAll(".animated");
      for (var i = 0; i < kids.length; i++) watch(kids[i]);
    }
  }

  function boot() {
    if (typeof MutationObserver === "function") {
      new MutationObserver(function (muts) {
        if (framesAlive) return;
        for (var i = 0; i < muts.length; i++) {
          var m = muts[i];
          if (m.type === "attributes") {
            if (m.target && m.target.className &&
                String(m.target.className).indexOf("animated") !== -1) {
              setTimeout(function (t) { return function () { finishElement(t); }; }(m.target), 30);
            }
          } else if (m.addedNodes) {
            for (var j = 0; j < m.addedNodes.length; j++) watch(m.addedNodes[j]);
          }
        }
      }).observe(document.documentElement, {
        subtree: true, childList: true, attributes: true, attributeFilter: ["class"]
      });
    }
    var existing = document.querySelectorAll(".animated");
    for (var k = 0; k < existing.length; k++) watch(existing[k]);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
  probe();
})();
"""


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def patch_once(path, old, new, note, required=True):
    """Replace `old` with `new` if present. Returns True if something changed."""
    if not os.path.isfile(path):
        if required:
            print("  !! missing %s (%s)" % (path, note))
        return False
    text = read(path)
    if new in text:
        print("  =  %s already applied" % note)
        return False
    if old not in text:
        if required:
            print("  !! %s: anchor not found (%s)" % (note, path))
        return False
    write(path, text.replace(old, new, 1))
    print("  ✓  %s" % note)
    return True


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    www = os.path.abspath(sys.argv[1])
    if not os.path.isfile(os.path.join(www, "index.html")):
        sys.exit("not a TyranoScript www folder: %s" % www)

    print("patching %s\n" % www)

    # --- Fix 1: scenarios reference .webm but only .mp4 ships ---------------
    print("[1] scenario videos: .webm -> .mp4")
    count = 0
    for root, _dirs, files in os.walk(os.path.join(www, "data", "scenario")):
        for name in files:
            if not name.endswith(".ks"):
                continue
            p = os.path.join(root, name)
            text = read(p)
            if '.webm"' not in text:
                continue
            write(p, text.replace('.webm"', '.mp4"'))
            count += 1
    print("  ✓  %d .ks file(s) rewritten" % count)

    # --- Fix 2: audio extension mapping + a non-blocking play event --------
    print("[2] audio: serve .mp3 (not .m4a) and never wait on a play event")
    audio = os.path.join(www, "tyrano", "plugins", "kag", "kag.tag_audio.js")
    patch_once(audio,
               'replaceAll(storage,".ogg",".m4a")',
               'replaceAll(storage,".ogg",".mp3")',
               "safari ogg->mp3")
    patch_once(
        audio,
        '$(audio_obj).off("play");$(audio_obj).on("play",function(){that.kag.layer.showEventLayer();if(pm.stop=="false")that.kag.ftag.nextOrder()});audio_obj.play();',
        ('$(audio_obj).off("play");'
         'var _pgd=false,_pg=function(){if(_pgd){return}_pgd=true;'
         'try{that.kag.layer.showEventLayer()}catch(e){}'
         'if(pm.stop=="false")that.kag.ftag.nextOrder()};'
         '$(audio_obj).on("play",_pg);'
         'audio_obj.play();'
         'setTimeout(function(){if(!_pgd&&audio_obj.readyState<3){_pg()}},1200);'),
        "play-event fallback")

    # --- Fix 3: a video that cannot decode must not stall the script -------
    print("[3] movies: fail fast instead of hanging forever")
    ext = os.path.join(www, "tyrano", "plugins", "kag", "kag.tag_ext.js")
    patch_once(
        ext,
        'video.load();video.play()}};',
        ('video.load();video.play();'
         'var _vdone=false,_vfail=function(){if(_vdone){return}_vdone=true;try{$(video).remove()}catch(e){}'
         'if(pm.bgmode=="true"){that.kag.tmp.video_playing=false;'
         'if(that.kag.stat.is_wait_bgmovie==true){that.kag.stat.is_wait_bgmovie=false;that.kag.ftag.nextOrder()}}'
         'else{that.kag.ftag.nextOrder()}};'
         'video.addEventListener("error",_vfail);'
         'setTimeout(function(){if(video.readyState<2){_vfail()}},5000);}};'),
        "movie error/timeout fallback")

    # --- Fix 5: the centring double-shift ----------------------------------
    print("[5] layout: kill the double horizontal shift")
    base = os.path.join(www, "tyrano", "tyrano.base.js")
    patch_once(
        base,
        "window.scrollTo(width, height);",
        "window.scrollTo(0, 0); /* patched: was scrollTo(width,height), which double-shifted the centred layout */",
        "tyrano.base.js scrollTo x=0")
    base_text = read(base) if os.path.isfile(base) else ""
    if base_text.count("window.scrollTo(0, 0); /* patched") < 2:
        print("  !  expected 2 patched call sites")

    # --- Fix 6: viewport meta so innerWidth matches the layout viewport ----
    print("[6] index.html: viewport meta + shim include")
    index = os.path.join(www, "index.html")
    text = read(index)
    old_meta = re.search(r'<meta name="viewport"[^>]*>', text)
    if old_meta and "width=device-width" not in old_meta.group(0):
        new_meta = ('<meta name="viewport" content="width=device-width, initial-scale=1.0, '
                    'minimum-scale=1.0, maximum-scale=1.0, user-scalable=no" />')
        write(index, text.replace(old_meta.group(0), new_meta, 1))
        print("  ✓  viewport meta rewritten")
        text = read(index)
    else:
        print("  =  viewport meta already ok")

    if "wkwrap-shim.js" not in text:
        jq = '<script type="text/javascript" src="./tyrano/libs/jquery-2.0.3.min.js"></script>'
        if jq in text:
            write(index, text.replace(
                jq,
                '<script type="text/javascript" src="./wkwrap-shim.js"></script>\n' + jq, 1))
            print("  ✓  shim included before jQuery")
        else:
            print("  !! jquery script tag not found")

    # --- Fix 7: drop libraries nothing references --------------------------
    print("[7] dead weight")
    for rel in ["tyrano/libs/jquery-1.10.2.min.js"]:
        p = os.path.join(www, rel)
        if os.path.isfile(p):
            os.remove(p)
            print("  ✓  removed %s" % rel)
        else:
            print("  =  %s already gone" % rel)

    # --- Fix 8: skip the MOD's 20-question quiz gauntlet ------------------
    # The opening branches into *no / *ok; *ok starts a chain of biology
    # questions where a single wrong answer ends the game (*n20 -> game over).
    # *y20 is the pass branch: it does the handover (the man leaves, Sylvie
    # introduces herself) and jumps to intro/step1.ks. Entering there directly
    # keeps the scene state correct while dropping the quiz.
    print("[8] opening.ks: skip the quiz")
    opening = os.path.join(www, "data", "scenario", "intro", "opening.ks")
    if os.path.isfile(opening):
        text = read(opening)
        quiz_entry = re.compile(
            r'\[button target="\*no" graphic="ch/jqxw\.png"[^\]]*\]\s*'
            r'\[button target="\*ok" graphic="ch/ksrw\.png"[^\]]*\]\[s\]', re.S)
        if '[jump target="*y20"]' in text and not quiz_entry.search(text):
            print("  =  already applied")
        elif quiz_entry.search(text):
            write(opening, quiz_entry.sub('[jump target="*y20"]', text, count=1))
            print("  ✓  quiz entry replaced with a jump to *y20")
        else:
            print("  !  quiz entry pattern not found (scenario already differs?)")
    else:
        print("  !! opening.ks not found")

    # --- Fix 9: loading a save must not die half-way --------------------
    # loadGameData() re-binds every saved .event-setting-element. A missing
    # data-event-pm (or an unknown data-event-tag) makes JSON.parse / setEvent
    # throw, which aborts the function *before* the [call make.ks] that
    # finishes restoring the scene -- the game freezes mid-load. It also
    # restores stat.is_stop from the save, and layer_obj_click bails on
    # is_stop, so taps can end up dead.
    print("[9] kag.menu.js: load path")
    menu = os.path.join(www, "tyrano", "plugins", "kag", "kag.menu.js")
    if os.path.isfile(menu):
        text = read(menu)
        old_a = ('$(".event-setting-element").each(function(){var j_elm=$(this);'
                 'var kind=j_elm.attr("data-event-tag");'
                 'var pm=JSON.parse(j_elm.attr("data-event-pm"));'
                 'var event_tag=object(tyrano.plugin.kag.tag[kind]);'
                 'event_tag.setEvent(j_elm,pm)});')
        new_a = ('$(".event-setting-element").each(function(){'
                 'try{var j_elm=$(this);var kind=j_elm.attr("data-event-tag");'
                 'var pm=JSON.parse(j_elm.attr("data-event-pm"));'
                 'var event_tag=object(tyrano.plugin.kag.tag[kind]);'
                 'if(event_tag&&event_tag.setEvent)event_tag.setEvent(j_elm,pm)'
                 '}catch(e){if(window.console)console.warn("rebind skipped",e)}});')
        if new_a in text:
            print("  =  already applied")
        elif old_a in text:
            text = text.replace(old_a, new_a, 1)
            menu_pat = re.compile(r'(this\.kag\.ftag\.nextOrderWithIndex\('
                                  r'data\.current_order_index,data\.stat\.current_scenario,true,insert,"yes"\))')
            new_b = (r'\1;var __k=this.kag;'
                     r'var __fix=function(){try{__k.stat.is_stop=false;__k.layer.showEventLayer()}catch(e){}};'
                     r'__fix();setTimeout(__fix,300);setTimeout(__fix,900)')
            text = menu_pat.sub(new_b, text, count=1)
            write(menu, text)
            print("  ✓  rebind guarded + interactivity restored after load")
        else:
            print("  !  anchor not found")
    else:
        print("  !! kag.menu.js not found")

    shim_path = os.path.join(www, "wkwrap-shim.js")
    write(shim_path, SHIM)
    print("  ✓  wkwrap-shim.js written")

    print("\ndone.")


if __name__ == "__main__":
    main()
