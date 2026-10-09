#!/usr/bin/env python3
"""静态审计：把剧本里所有引用逐一核对，报告缺文件 / 断跳转 / 结构错误。

TyranoScript 的 storage 按标签决定落到哪个目录，这里按引擎里的实际规则来解析：

    [bg]                    -> data/bgimage/
    [chara_mod] [chara_show]-> data/fgimage/
    [image] [button] [glink]-> data/<folder>/     (folder 默认 image)
    [playbgm] [bgm]         -> data/bgm/
    [playse] [se] [voice]   -> data/sound/
    [movie] [bgmovie]       -> data/video/
    [loadjs]                -> data/others/
    [call] [jump]           -> data/scenario/

音频在移植时把 .ogg 转成了 .m4a（引擎在 Safari/iPhone 下会自己改名），
所以引用 .ogg 时按 .m4a 找文件。

用法: python3 audit.py <www_root>
"""
import os
import re
import sys
from collections import defaultdict

WWW = sys.argv[1] if len(sys.argv) > 1 else "/var/minis/workspace/sylvie/apk/assets"
SCEN = os.path.join(WWW, "data", "scenario")

TAG_FOLDER = {
    "bg": "bgimage", "bg2": "bgimage",
    "chara_mod": "fgimage", "chara_show": "fgimage", "chara_hide": "fgimage",
    "image": "image", "button": "image", "glink": "image", "link": "image",
    "playbgm": "bgm", "bgm": "bgm", "stopbgm": "bgm", "fadeoutbgm": "bgm",
    "playse": "sound", "se": "sound", "stopse": "sound",
    "playvoice": "sound", "voice": "sound",
    "movie": "video", "bgmovie": "video", "stop_bgmovie": "video", "wait_bgmovie": "video",
    "loadjs": "others", "loadcss": "others",
}
# 这些标签的 storage 不指向普通文件
SKIP_TAGS = {"eval", "emb", "if", "elsif", "else", "endif", "macro", "endmacro",
             "return", "call", "jump", "label", "s", "p", "r", "br", "cm", "ct",
             "title", "glyph", "deffont", "defstyle", "position", "layopt",
             "screen", "laycount", "current", "free", "clearvar", "clearsysvar",
             "autoconfig", "close", "trace", "camera", "wait_camera", "resetfont",
             "html", "savesnap", "breakgame", "sleepgame", "awakegame", "dialog",
             "glink", "rider", "commit", "nolog", "endnolog", "showlog", "hidemessage",
             "showmessage", "wa", "stopanim", "keyframe", "endkeyframe", "frame"}

ATTR = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"([^"]*)"|([^\s\]]+))')


def attrs_of(body):
    out = {}
    for m in ATTR.finditer(body):
        out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out


def scan_tags(text):
    """扫标签：`[` 到**不在引号里**的第一个 `]`，允许跨行（MOD 里很多标签是折行的）。

    直接按行扫会在折行的标签上出错，所以这里全文扫，同时维护行号。
    以 `;` 开头的整行是注释，跳过。
    """
    # 先把注释行挖掉（保留行号：用等长空白替换）
    lines = text.split("\n")
    cleaned = []
    for l in lines:
        if l.lstrip().startswith(";"):
            cleaned.append(" " * len(l))
        else:
            cleaned.append(l)
    text = "\n".join(cleaned)

    line_starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(i + 1)

    def line_of(pos):
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    i, n = 0, len(text)
    while i < n:
        if text[i] != "[":
            i += 1
            continue
        j = i + 1
        in_q = False
        while j < n:
            c = text[j]
            if c == '"':
                in_q = not in_q
            elif c == "]" and not in_q:
                break
            elif c == "[" and not in_q:
                break          # 可能是消息正文里的方括号，放弃这个
            j += 1
        if j >= n or text[j] != "]":
            i += 1
            continue
        body = text[i + 1:j]
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", body)
        if m:
            yield m.group(1), attrs_of(body), line_of(i)
        i = j + 1


def is_dynamic(v):
    """引用里带 [emb ...] / 变量拼接的，静态没法判断，跳过。"""
    return ("[" in v) or ("]" in v) or ("%" in v) or ("+" in v) or v.strip() == ""


def walk_ks():
    for dp, _d, fs in os.walk(SCEN):
        for n in sorted(fs):
            if n.endswith(".ks"):
                yield os.path.join(dp, n)


def main():
    labels = defaultdict(set)          # ks 相对路径 -> 标签集合
    files = list(walk_ks())

    # 第一遍：收集标签
    parsed = []
    for path in files:
        rel = os.path.relpath(path, SCEN).replace(os.sep, "/")
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        parsed.append((rel, text))
        for m in re.finditer(r"^\*([^\s\[]*)", text, re.M):
            labels[rel].add("*" + m.group(1))

    missing = []            # (ks, line, tag, 解析出的路径)
    dynamic = []
    bad_jump = []           # 跳转/调用目标不存在
    structure = []          # if/endif、macro/endmacro 不配平
    tag_count = defaultdict(int)

    for rel, text in parsed:
        # 结构检查（按标签出现顺序数，注释行已在 scan_tags 里跳过）
        depth_if = depth_macro = 0
        for name, attrs, line_no in scan_tags(text):
            tag_count[name] += 1
            if name == "if":
                depth_if += 1
            elif name == "endif":
                depth_if -= 1
                if depth_if < 0:
                    structure.append((rel, line_no, "endif 多余"))
                    depth_if = 0
            elif name == "macro":
                depth_macro += 1
            elif name == "endmacro":
                depth_macro -= 1
                if depth_macro < 0:
                    structure.append((rel, line_no, "endmacro 多余"))
                    depth_macro = 0

            if name in SKIP_TAGS:
                continue

            # [button] / [glink] 的 storage 是"跳到的剧本"，图片在 graphic 里
            scen_ref = None
            if name in ("button", "glink", "link"):
                scen_ref = attrs.get("storage")
                ref = attrs.get("graphic")
                folder = attrs.get("folder") or "image"
            else:
                ref = attrs.get("storage") or attrs.get("graphic")
                folder = attrs.get("folder") or TAG_FOLDER.get(name)

            if ref:
                if is_dynamic(ref):
                    dynamic.append((rel, line_no, name, ref))
                elif folder:
                    tgt = os.path.join(WWW, "data", folder, ref)
                    alt = tgt[:-4] + ".m4a" if tgt.endswith(".ogg") else None
                    if not os.path.isfile(tgt) and not (alt and os.path.isfile(alt)):
                        missing.append((rel, line_no, name, os.path.join("data", folder, ref)))

            for st, lab, kind in ((scen_ref, attrs.get("target"), name),
                                  (attrs.get("storage") if name in ("call", "jump") else None,
                                   attrs.get("target"), name)):
                if not st:
                    continue
                if is_dynamic(st):
                    dynamic.append((rel, line_no, name, st))
                    continue
                fn = st if st.endswith(".ks") else st + ".ks"
                path = os.path.join(SCEN, fn)
                if not os.path.isfile(path):
                    bad_jump.append((rel, line_no, kind, fn, "文件不存在"))
                    continue
                if lab and not is_dynamic(lab) and lab not in labels.get(fn, set()):
                    bad_jump.append((rel, line_no, kind, fn + " " + lab, "标签不存在"))

        if depth_if != 0:
            structure.append((rel, 0, f"if/endif 不配平 (差 {depth_if})"))
        if depth_macro != 0:
            structure.append((rel, 0, f"macro/endmacro 不配平 (差 {depth_macro})"))

    # ---- 属性引号不成对的标签（engine 会解析错，属于原文笔误）----
    quote_typos = []
    for rel, text in parsed:
        clean = "\n".join(" " * len(l) if l.lstrip().startswith(";") else l
                          for l in text.split("\n"))
        i, n = 0, len(clean)
        while i < n:
            if clean[i] != "[":
                i += 1
                continue
            j = i + 1
            while j < n and clean[j] not in "\n]":
                j += 1
            body = clean[i + 1:j]
            if body.count('"') % 2 == 1:
                ln = clean[:i].count("\n") + 1
                quote_typos.append((rel, ln, body.strip()[:90]))
            i = j + 1

    # ---- 用到的标签是否"引擎标签 或 已定义的宏" ----
    engine_tags = set()
    for jf in ("kag.js", "kag.tag.js", "kag.tag_system.js", "kag.tag_audio.js",
               "kag.tag_ext.js", "kag.menu.js", "kag.tag_camera.js"):
        jp = os.path.join(WWW, "tyrano", "plugins", "kag", jf)
        if not os.path.isfile(jp):
            continue
        js = open(jp, encoding="utf-8", errors="ignore").read()
        engine_tags |= set(re.findall(r'tyrano\.plugin\.kag\.tag\["([A-Za-z_0-9]+)"\]', js))
        engine_tags |= set(re.findall(r'tyrano\.plugin\.kag\.tag\.([A-Za-z_0-9]+)\s*=', js))
    defined_macros = set()
    for rel, text in parsed:
        for name, attrs, _ln in scan_tags(text):
            if name == "macro" and attrs.get("name"):
                defined_macros.add(attrs["name"].strip())
    unknown = defaultdict(list)
    for rel, text in parsed:
        for name, _a, line_no in scan_tags(text):
            if name in engine_tags or name in defined_macros:
                continue
            if name in ("macro",) or re.match(r"^[0-9]+$", name):
                continue
            unknown[name].append(f"{rel}:{line_no}")

    print(f"剧本文件: {len(parsed)}   标签引用标签总数: {sum(tag_count.values())}")
    print(f"资源引用: {sum(1 for _ in missing) + 0} 处找不到文件（明细见下）")
    print()
    print(f"== 缺失文件 {len(missing)} 处 ==")
    for rel, ln, tag, p in missing[:60]:
        print(f"  {rel}:{ln}  [{tag}]  {p}")
    if len(missing) > 60:
        print(f"  ...以及另外 {len(missing) - 60} 处")
    print()
    print(f"== 断跳转/断调用 {len(bad_jump)} 处 ==")
    for rel, ln, tag, tgt, why in bad_jump[:40]:
        print(f"  {rel}:{ln}  [{tag}]  {tgt}  ({why})")
    if len(bad_jump) > 40:
        print(f"  ...以及另外 {len(bad_jump) - 40} 处")
    print()
    print(f"== 结构问题 {len(structure)} 处 ==")
    for rel, ln, why in structure[:40]:
        print(f"  {rel}:{ln}  {why}")
    print()
    print(f"== 动态引用（静态无法判断）{len(dynamic)} 处 ==")
    for rel, ln, tag, v in dynamic[:8]:
        print(f"  {rel}:{ln}  [{tag}]  {v}")
    print()
    print(f"== 属性引号不成对（原文笔误）{len(quote_typos)} 处 ==")
    seen = set()
    for rel, ln, body in quote_typos:
        key = (rel, ln)
        if key in seen:
            continue
        seen.add(key)
        print(f"  {rel}:{ln}  [{body}]")
    print()

    print(f"== 用到了但既不是引擎标签、也不是已定义宏的名字 {len(unknown)} 个 ==")
    for name, where in sorted(unknown.items(), key=lambda x: -len(x[1]))[:25]:
        print(f"  [{name}]  x{len(where)}   例: {where[0]}")
    print()

    print("== 标签使用频次（前 25）==")
    for name, n in sorted(tag_count.items(), key=lambda x: -x[1])[:25]:
        print(f"  {name:16} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
