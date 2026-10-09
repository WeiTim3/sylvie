#!/bin/sh
# Transcode the MOD's media to formats iOS/WebKit can actually decode.
#   .ogg  (Vorbis) -> .m4a (AAC)   -- WebKit has no Vorbis decoder
#   .webm (VP9)    -> .mp4 (H.264) -- WebKit has no VP9 decoder
# Originals are removed afterwards: nothing on iOS can play them anyway.
set -u
WWW="${1:-assets}"
LOG=/tmp/transcode.log
: > "$LOG"

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

say "=== 音频 Vorbis -> AAC ==="
ok=0; bad=0
for f in "$WWW"/data/bgm/*.ogg "$WWW"/data/sound/*.ogg; do
  [ -e "$f" ] || continue
  base="${f%.ogg}"
  if [ -s "$f" ] && ffmpeg -y -hide_banner -loglevel error -i "$f" \
      -c:a aac -b:a 128k -movflags +faststart "$base.m4a" </dev/null 2>>"$LOG"; then
    rm -f "$f"; ok=$((ok+1))
  else
    say "  !! 失败: $f"; bad=$((bad+1))
  fi
done
say "音频完成: $ok 个转换, $bad 个失败"

say "=== 视频 VP9 -> H.264 ==="
ok=0; bad=0
for f in "$WWW"/data/video/*.webm; do
  [ -e "$f" ] || continue
  base="${f%.webm}"
  if ffmpeg -y -hide_banner -loglevel error -i "$f" \
      -c:v h264_videotoolbox -b:v 1200k -pix_fmt yuv420p \
      -c:a aac -b:a 96k -movflags +faststart "$base.mp4" </dev/null 2>>"$LOG"; then
    rm -f "$f"; ok=$((ok+1))
  else
    say "  !! 失败: $f"; bad=$((bad+1))
  fi
done
say "视频完成: $ok 个转换, $bad 个失败"

say "=== 剩余未转换 ==="
say "  .ogg : $(find "$WWW/data" -name '*.ogg' | wc -l)"
say "  .webm: $(find "$WWW/data" -name '*.webm' | wc -l)"
say "DONE"
