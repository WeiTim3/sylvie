#!/usr/bin/env python3
"""
把游戏素材打进已编译的 IPA。

用 Python 直接写 zip 而不是调 zip(1)，原因有两个：
  1. /var/minis 挂载点不支持 chmod（静默失败），没法把可执行位写到文件系统上；
     zipfile 允许按条目显式指定 external_attr，绕过这个限制。
  2. 可以直接从 /var/minis 读素材、从 /tmp 读 .app，不需要把 1.4GB 复制来复制去。
"""
import os
import sys
import time
import zipfile

BASE = "/var/minis/workspace/ver769"
APP_SRC = "/tmp/ipx/Payload/SylvieGame.app"
WWW_SRC = BASE + "/ver769/assets/www"
OUT = BASE + "/build/SylvieGame-baked.ipa"

DIR_MODE = 0o40755
FILE_MODE = 0o100644
EXEC_MODE = 0o100755

EXEC_NAMES = {"SylvieGame"}          # app 主二进制
SKIP = {"__MACOSX", ".DS_Store"}

t0 = time.time()
last = t0


def log(msg):
    print(f"[{time.time() - t0:7.1f}s] {msg}", flush=True)


def mode_for(name):
    return EXEC_MODE if name in EXEC_NAMES else FILE_MODE


def add_dir(zf, arcname, mtime):
    zi = zipfile.ZipInfo(arcname.rstrip("/") + "/", time.localtime(mtime)[:6])
    zi.external_attr = (DIR_MODE | 0o10) << 16   # 0o10 = MS-DOS directory bit
    zi.compress_type = zipfile.ZIP_STORED
    zf.writestr(zi, b"")


def add_file(zf, src, arcname, override_mode=None):
    st = os.stat(src)
    zi = zipfile.ZipInfo(arcname, time.localtime(st.st_mtime)[:6])
    zi.external_attr = (override_mode or FILE_MODE) << 16
    zi.compress_type = zipfile.ZIP_STORED
    with open(src, "rb") as fsrc, zf.open(zi, "w") as fdst:
        while True:
            chunk = fsrc.read(1 << 16)
            if not chunk:
                break
            fdst.write(chunk)


def walk_tree(zf, root, arc_prefix, counter, log_every=2000):
    """按 os.walk 顺序写入 root 下的所有内容，保留目录结构。"""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
        rel = os.path.relpath(dirpath, root)
        arc_dir = arc_prefix if rel == "." else arc_prefix + "/" + rel.replace(os.sep, "/")
        if rel != ".":
            add_dir(zf, arc_dir, os.stat(dirpath).st_mtime)
        for fn in sorted(filenames):
            if fn in SKIP:
                continue
            src = os.path.join(dirpath, fn)
            if not os.path.isfile(src):
                continue
            add_file(zf, src, arc_dir + "/" + fn,
                     mode_for(fn) if rel == "." else None)
            counter[0] += 1
            if counter[0] % log_every == 0:
                log(f"  {counter[0]} files...")


def main():
    if not os.path.isdir(APP_SRC):
        sys.exit("missing staged app: " + APP_SRC)
    if not os.path.isfile(os.path.join(WWW_SRC, "index.html")):
        sys.exit("missing game data: " + WWW_SRC)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)

    counter = [0]
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_STORED, allowZip64=True) as zf:
        add_dir(zf, "Payload", time.time())
        add_dir(zf, "Payload/SylvieGame.app", os.stat(APP_SRC).st_mtime)
        walk_tree(zf, APP_SRC, "Payload/SylvieGame.app", counter)
        log(f"app staged: {counter[0]} files")

        www_arc = "Payload/SylvieGame.app/www"
        if not zf.NameToInfo.get(www_arc + "/"):
            add_dir(zf, www_arc, os.stat(WWW_SRC).st_mtime)
        walk_tree(zf, WWW_SRC, www_arc, counter)
        log(f"www staged: {counter[0]} files total")

    size = os.path.getsize(OUT)
    log(f"DONE  {size / 1048576:.1f} MB  ({counter[0]} files)")

    # 回读校验权限
    with zipfile.ZipFile(OUT) as zf:
        for n in zf.namelist():
            if n.endswith("app/SylvieGame"):
                m = zf.getinfo(n).external_attr >> 16
                log(f"verify {n}: {oct(m)} " + ("EXEC OK" if m & 0o111 else "!! NOT EXEC"))


if __name__ == "__main__":
    main()
