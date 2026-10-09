#!/usr/bin/env python3
"""Bake the prepared game data into the (tiny) shell IPA.

The shell app looks for the game in this order:

    1. <App Documents>/www          (user-supplied, wins if present)
    2. <App Bundle>/www             (what this script fills in)

so baking makes the app self-contained: install one file, nothing to copy.

Two iSH quirks this has to work around, both learned the hard way:

  * /var/minis does not support chmod -- it returns success and silently keeps
    mode 0644.  So we cannot use zip(1), which reads permissions off the
    filesystem and would write the app binary as 0644 (uninstallable).
    -> Python's zipfile, setting external_attr explicitly per entry.
  * iSH supports neither hard links (EXDEV) nor symlinks, so there is no
    copy-cheap trick; we stream the files straight out of the sources.

Usage: python3 bake_ipa.py <shell.ipa> <www_dir> <out.ipa>
"""
import os
import shutil
import sys
import zipfile

SHELL_IPA = sys.argv[1] if len(sys.argv) > 1 else "build/SylvieGame-unsigned.ipa"
WWW = sys.argv[2] if len(sys.argv) > 2 else "www"
OUT = sys.argv[3] if len(sys.argv) > 3 else "build/SylvieGame-baked.ipa"

STAGE = "/tmp/ipx"
APP = "Payload/SylvieGame.app"

MODE_DIR = 0o040755
MODE_FILE = 0o100644
MODE_EXEC = 0o100755

# Paths inside the .app that must stay executable.
EXECUTABLE = {f"{APP}/SylvieGame"}


def zipinfo(name, mode):
    zi = zipfile.ZipInfo(name)
    zi.external_attr = mode << 16
    zi.create_system = 3          # unix: makes external_attr meaningful
    zi.compress_type = zipfile.ZIP_STORED   # media is already compressed
    return zi


def main():
    print(f"外壳  : {SHELL_IPA}")
    print(f"游戏  : {WWW}")
    print(f"输出  : {OUT}")

    if os.path.exists(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)
    with zipfile.ZipFile(SHELL_IPA) as z:
        z.extractall(STAGE)
    app_root = os.path.join(STAGE, "Payload", "SylvieGame.app")
    if not os.path.isdir(app_root):
        raise SystemExit(f"外壳里没有 {APP}：{os.listdir(os.path.join(STAGE,'Payload'))}")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    total = 0
    dirs = set()

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_STORED, allowZip64=True) as out:
        # 1. the app itself
        for dirpath, dirnames, filenames in os.walk(STAGE):
            for d in dirnames:
                rel = os.path.relpath(os.path.join(dirpath, d), STAGE).replace(os.sep, "/")
                dirs.add(rel)
            for f in filenames:
                full = os.path.join(dirpath, f)
                rel = os.path.relpath(full, STAGE).replace(os.sep, "/")
                mode = MODE_EXEC if rel in EXECUTABLE else MODE_FILE
                with open(full, "rb") as fh:
                    out.writestr(zipinfo(rel, mode), fh.read())
                total += 1
        print(f"  外壳文件 {total} 个")

        # 2. the game, as SylvieGame.app/www/**
        n = 0
        for dirpath, dirnames, filenames in os.walk(WWW):
            rel_dir = os.path.relpath(dirpath, WWW).replace(os.sep, "/")
            prefix = f"{APP}/www" + ("" if rel_dir == "." else "/" + rel_dir)
            for d in dirnames:
                name = f"{prefix}/{d}"
                if name not in dirs:
                    out.writestr(zipinfo(name + "/", MODE_DIR), b"")
                    dirs.add(name)
            for f in filenames:
                full = os.path.join(dirpath, f)
                name = f"{prefix}/{f}"
                with open(full, "rb") as fh:
                    out.writestr(zipinfo(name, MODE_FILE), fh.read())
                n += 1
                if n % 2000 == 0:
                    print(f"  ... 已写入 {n} 个游戏文件")
        print(f"  游戏文件 {n} 个")
    print(f"完成: {OUT} ({os.path.getsize(OUT)/1024/1024:.0f} MB)")


if __name__ == "__main__":
    main()
