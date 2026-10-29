#!/usr/bin/env bash
# Upload a video into kmuse996-bot/video-gallery without Google Drive.
# Usage:
#   gallery-video-upload.sh <video_path> <id> <title> <ratio> <date> [en] [ko]
#   gallery-video-upload.sh --json <entry.json>   # needs video_path or video + id,title,date,...
#   gallery-video-upload.sh --dry-run ...         # compress + write local files, no commit/push
# Env:
#   REPO_DIR   default: /workspace/video-gallery (clone if missing)
#   MAX_MB     soft target after compress (default 40). Hard GitHub limit 100MB.
#   CRF        libx264 crf (default 23)
#   PRESET     libx264 preset (default medium)
#   NO_PUSH=1  commit only
set -euo pipefail

DRY_RUN=0
JSON_PATH=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --json) JSON_PATH="${2:?}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

REPO_DIR="${REPO_DIR:-/workspace/video-gallery}"
MAX_MB="${MAX_MB:-40}"
CRF="${CRF:-23}"
PRESET="${PRESET:-medium}"
HARD_MB=95
OWNER_NAME="kmuse996-bot"
OWNER_EMAIL="kmuse996-bot@users.noreply.github.com"

need() { command -v "$1" >/dev/null 2>&1 || { echo "need: $1" >&2; exit 1; }; }
need ffmpeg; need ffprobe; need git; need python3; need gh

VIDEO_PATH=""; ID=""; TITLE=""; RATIO=""; DATE=""; EN=""; KO=""; LEN=""; RES=""

if [[ -n "$JSON_PATH" ]]; then
  eval "$(python3 - "$JSON_PATH" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
def g(*keys, default=""):
    for k in keys:
        if k in d and d[k] is not None: return str(d[k])
    return default
pairs = {
  "VIDEO_PATH": g("video_path", "src", "source"),
  "ID": g("id"),
  "TITLE": g("title", "file"),
  "RATIO": g("ratio", default="9/16"),
  "DATE": g("date"),
  "EN": g("en", "english"),
  "KO": g("ko", "korean"),
  "LEN": g("len", "length"),
  "RES": g("res", "resolution"),
}
# optional video already relative path in repo is not a source
for k,v in pairs.items():
    print(f'{k}={shlex.quote(v)}')
PY
)"
  if [[ ${#ARGS[@]} -gt 0 ]]; then
    echo "do not mix --json with positional args" >&2; exit 1
  fi
else
  if [[ ${#ARGS[@]} -lt 5 ]]; then
    echo "usage: $0 [--dry-run] <video_path> <id> <title> <ratio> <date> [en] [ko]" >&2
    echo "   or: $0 [--dry-run] --json entry.json" >&2
    exit 1
  fi
  VIDEO_PATH="${ARGS[0]}"; ID="${ARGS[1]}"; TITLE="${ARGS[2]}"; RATIO="${ARGS[3]}"; DATE="${ARGS[4]}"
  EN="${ARGS[5]:-}"; KO="${ARGS[6]:-}"
fi

[[ -n "$VIDEO_PATH" && -f "$VIDEO_PATH" ]] || { echo "video not found: $VIDEO_PATH" >&2; exit 1; }
[[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "id must be lowercase letters/digits/hyphens: got '$ID'" >&2; exit 1; }
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "date must be YYYY-MM-DD: got '$DATE'" >&2; exit 1; }
[[ -n "$TITLE" ]] || { echo "title required" >&2; exit 1; }
RATIO="${RATIO:-9/16}"

# ensure repo
if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  gh repo clone kmuse996-bot/video-gallery "$REPO_DIR"
fi
cd "$REPO_DIR"
if [[ "$DRY_RUN" -eq 0 ]]; then
  git fetch origin main -q
  git checkout main -q
  git pull --ff-only origin main -q
fi

mkdir -p videos tools
OUT_MP4="videos/${ID}.mp4"
OUT_JPG="videos/${ID}.jpg"
LOCAL_JSON="videos/local.json"
[[ -f "$LOCAL_JSON" ]] || echo '[]' > "$LOCAL_JSON"

python3 - "$LOCAL_JSON" "$ID" <<'PY'
import json, sys
path, id_ = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
if any(str(x.get("id")) == id_ for x in d):
    sys.exit(f"id already exists in local.json: {id_}")
PY

# probe source
probe_json="$(ffprobe -v error -show_entries format=duration:stream=codec_type,width,height -of json "$VIDEO_PATH")"
read -r SRC_DUR SRC_W SRC_H <<<"$(python3 -c 'import json,sys;d=json.loads(sys.argv[1]);streams=d.get("streams")or[];v=next((s for s in streams if s.get("codec_type")=="video"),{});print(float(d.get("format",{}).get("duration")or 0), int(v.get("width")or 0), int(v.get("height")or 0))' "$probe_json")"

if [[ -z "$LEN" || "$LEN" == "0" ]]; then
  LEN="$(python3 -c 'import math,sys;d=float(sys.argv[1]);print(f"{int(round(d))}초" if d else "")' "$SRC_DUR")"
fi
if [[ -z "$RES" ]]; then
  # after scale max 1280 on long side → report target-ish
  if (( SRC_H >= SRC_W )); then RES="720p"; else RES="720p"; fi
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "== compress $VIDEO_PATH → $OUT_MP4 (crf=$CRF preset=$PRESET, max≈${MAX_MB}MB)"
# scale so longer side <= 1280, even height/width for yuv420
ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
  -vf "scale='min(1280,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -c:v libx264 -pix_fmt yuv420p -crf "$CRF" -preset "$PRESET" \
  -c:a aac -b:a 128k -ac 2 -movflags +faststart \
  "$TMP/out.mp4"

SIZE_B=$(stat -c%s "$TMP/out.mp4")
SIZE_MB=$(python3 -c "print(round($SIZE_B/1024/1024,2))")
echo "   compressed: ${SIZE_MB} MB"

# if still over soft target, bump CRF once
if python3 -c "import sys; sys.exit(0 if $SIZE_B > ${MAX_MB}*1024*1024 else 1)"; then
  echo "   over soft ${MAX_MB}MB → retry crf=$((CRF+4))"
  ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
    -vf "scale='min(1280,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -c:v libx264 -pix_fmt yuv420p -crf $((CRF+4)) -preset "$PRESET" \
    -c:a aac -b:a 96k -ac 2 -movflags +faststart \
    "$TMP/out.mp4"
  SIZE_B=$(stat -c%s "$TMP/out.mp4")
  SIZE_MB=$(python3 -c "print(round($SIZE_B/1024/1024,2))")
  echo "   recompressed: ${SIZE_MB} MB"
fi

if python3 -c "import sys; sys.exit(0 if $SIZE_B > ${HARD_MB}*1024*1024 else 1)"; then
  echo "ERROR: still ${SIZE_MB}MB > ${HARD_MB}MB GitHub soft hard-cap. Shorten/lower resolution or use a Release asset manually." >&2
  exit 1
fi

ffmpeg -y -hide_banner -loglevel error -i "$TMP/out.mp4" -ss 0.3 -frames:v 1 -q:v 3 "$TMP/poster.jpg" || true
cp -f "$TMP/out.mp4" "$OUT_MP4"
HAS_POSTER=0
if [[ -s "$TMP/poster.jpg" ]]; then
  cp -f "$TMP/poster.jpg" "$OUT_JPG"
  HAS_POSTER=1
fi

python3 - "$LOCAL_JSON" "$ID" "$TITLE" "$RATIO" "$DATE" "$EN" "$KO" "$LEN" "$RES" "$HAS_POSTER" <<'PY'
import json, sys
path, id_, title, ratio, date, en, ko, length, res, has_poster = sys.argv[1:11]
d = json.load(open(path, encoding="utf-8"))
if any(str(x.get("id")) == id_ for x in d):
    raise SystemExit(f"id already exists: {id_}")
e = {
  "id": id_,
  "title": title,
  "video": f"videos/{id_}.mp4",
  "ratio": ratio,
  "date": date,
  "en": en,
  "ko": ko,
  "len": length,
  "res": res,
}
if has_poster == "1":
  e["poster"] = f"videos/{id_}.jpg"
d.append(e)
json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
print("appended", id_, "→", path, f"({len(d)} entries)")
PY

# also keep a copy of this script inside the repo tools/
SELF_SRC="${BASH_SOURCE[0]}"
if [[ -f "$SELF_SRC" ]]; then
  cp -f "$SELF_SRC" tools/gallery-video-upload.sh
  chmod +x tools/gallery-video-upload.sh
fi

echo "== files ready:"
ls -lh "$OUT_MP4" ${HAS_POSTER:+$OUT_JPG} "$LOCAL_JSON"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN: skipped commit/push. Working tree left dirty on purpose."
  git status --short | head -40
  exit 0
fi

git add "$OUT_MP4" "$LOCAL_JSON" tools/gallery-video-upload.sh
[[ "$HAS_POSTER" -eq 1 ]] && git add "$OUT_JPG"
git -c user.name="$OWNER_NAME" -c user.email="$OWNER_EMAIL" commit -m "Add video: ${TITLE}"
if [[ "${NO_PUSH:-0}" == "1" ]]; then
  echo "NO_PUSH=1: commit done, not pushed"
else
  git push origin HEAD:main
  echo "pushed. site: https://kmuse996-bot.github.io/video-gallery/ (1–2 min)"
fi
