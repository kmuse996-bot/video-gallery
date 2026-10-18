#!/usr/bin/env bash
# Sync Drive videos listed in the '영상프롬' sheet (column I = Drive video id)
# into videos/<id>.mp4 (remuxed, faststart) and rebuild videos/index.json.
set -uo pipefail
SHEET_ID="${SHEET_ID:-134ZE8aVQlCcgW9dnMynFGc84a5k1yg0dq-JNgGxYzbs}"
GID="${GID:-0}"
cd "$(dirname "$0")/.."
mkdir -p videos
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?gid=${GID}&headers=1&tqx=out:csv&tq=select%20I" -o "$tmp/ids.csv" || { echo "sheet fetch failed"; exit 1; }
ids=$(tail -n +2 "$tmp/ids.csv" | tr -d '"\r' | grep -E '^[A-Za-z0-9_-]{20,}$' | sort -u)
echo "ids in sheet: $(echo "$ids" | grep -c . || true)"

fail=0
for id in $ids; do
  [ -s "videos/$id.mp4" ] && continue
  echo "== downloading $id"
  if ! curl -fsSL --retry 3 "https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t" -o "$tmp/src"; then
    echo "download failed: $id"; fail=1; continue
  fi
  if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$tmp/src" >/dev/null 2>&1; then
    echo "not a video (maybe not public?): $id"; fail=1; continue
  fi
  if ffmpeg -y -v error -i "$tmp/src" -map 0:v:0 -map '0:a:0?' -c copy -movflags +faststart -f mp4 "$tmp/out.mp4"; then
    mv "$tmp/out.mp4" "videos/$id.mp4"; echo "ok $id ($(du -h "videos/$id.mp4" | cut -f1))"
  else
    echo "remux failed: $id"; fail=1
  fi
done

# index.json = ids that actually exist on disk
python3 - <<'PY'
import json, os, re
ids = sorted(f[:-4] for f in os.listdir("videos") if f.endswith(".mp4") and os.path.getsize(os.path.join("videos", f)) > 0)
open("videos/index.json", "w").write(json.dumps(ids, indent=0) + "\n")
print("index.json:", len(ids), "ids")
PY
exit $fail
