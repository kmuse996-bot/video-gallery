#!/usr/bin/env bash
# Upload a video into kmuse996-bot/video-gallery at original quality (default: GitHub Release).
#
# Usage:
#   gallery-video-upload.sh [--mode release|repo|drive-register] [--replace] \
#       <video_path> <id> <title> <ratio> <date> [en] [ko]
#   gallery-video-upload.sh --json entry.json
#   gallery-video-upload.sh --dry-run ...
#
# Modes:
#   release (default)  Remux +faststart only (no re-encode). Upload as GitHub Release
#                      asset (up to ~2GB). Does NOT put the mp4 in the repo / Pages
#                      budget. local.json gets an absolute release URL.
#   repo               Re-encode h264 crf~23 (legacy). Stores videos/<id>.mp4 in repo.
#   drive-register     No upload. Registers an already-uploaded Drive file id into
#                      local.json for iframe playback (mp4 stays on Drive, not in repo).
#                      Requires --drive-id <id> (or JSON drive_id). Prefer Cursor
#                      UploadFile(connection=google-drive) first — shell has no Drive
#                      credentials on this box.
#
# Env: REPO_DIR=/workspace/video-gallery  NO_PUSH=1  DRY via --dry-run
set -euo pipefail

MODE="release"
DRY_RUN=0
REPLACE=0
JSON_PATH=""
DRIVE_ID=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --replace) REPLACE=1; shift ;;
    --mode) MODE="${2:?}"; shift 2 ;;
    --drive-id) DRIVE_ID="${2:?}"; shift 2 ;;
    --json) JSON_PATH="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

REPO_DIR="${REPO_DIR:-/workspace/video-gallery}"
MAX_MB="${MAX_MB:-40}"
CRF="${CRF:-23}"
PRESET="${PRESET:-medium}"
HARD_MB=95
RELEASE_HARD_MB=1900
OWNER_NAME="kmuse996-bot"
OWNER_EMAIL="kmuse996-bot@users.noreply.github.com"
REPO_SLUG="kmuse996-bot/video-gallery"

need() { command -v "$1" >/dev/null 2>&1 || { echo "need: $1" >&2; exit 1; }; }
need ffmpeg; need ffprobe; need git; need python3; need gh

VIDEO_PATH=""; ID=""; TITLE=""; RATIO=""; DATE=""; EN=""; KO=""; LEN=""; RES=""

if [[ -n "$JSON_PATH" ]]; then
  _CLI_MODE="$MODE"
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
  "DRIVE_ID": g("drive_id", "driveId", "vid"),
  "JSON_MODE": g("mode", default=""),
}
for k,v in pairs.items():
    print(f'{k}={shlex.quote(v)}')
PY
)"
  if [[ "$_CLI_MODE" == "release" && -n "${JSON_MODE:-}" ]]; then MODE="$JSON_MODE"; fi
  if [[ ${#ARGS[@]} -gt 0 ]]; then
    echo "do not mix --json with positional args" >&2; exit 1
  fi
else
  if [[ "$MODE" == "drive-register" ]]; then
    if [[ ${#ARGS[@]} -lt 4 ]]; then
      echo "usage: $0 --mode drive-register --drive-id <id> <id> <title> <ratio> <date> [en] [ko]" >&2
      exit 1
    fi
    # allow video_path omitted: shift pattern id title ratio date
    ID="${ARGS[0]}"; TITLE="${ARGS[1]}"; RATIO="${ARGS[2]}"; DATE="${ARGS[3]}"
    EN="${ARGS[4]:-}"; KO="${ARGS[5]:-}"
  else
    if [[ ${#ARGS[@]} -lt 5 ]]; then
      echo "usage: $0 [--mode release|repo] [--replace] [--dry-run] <video_path> <id> <title> <ratio> <date> [en] [ko]" >&2
      exit 1
    fi
    VIDEO_PATH="${ARGS[0]}"; ID="${ARGS[1]}"; TITLE="${ARGS[2]}"; RATIO="${ARGS[3]}"; DATE="${ARGS[4]}"
    EN="${ARGS[5]:-}"; KO="${ARGS[6]:-}"
  fi
fi

case "$MODE" in release|repo|drive-register) ;; *) echo "bad --mode: $MODE" >&2; exit 1 ;; esac
[[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "id must be lowercase letters/digits/hyphens: got '$ID'" >&2; exit 1; }
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "date must be YYYY-MM-DD: got '$DATE'" >&2; exit 1; }
[[ -n "$TITLE" ]] || { echo "title required" >&2; exit 1; }
RATIO="${RATIO:-9/16}"

if [[ "$MODE" != "drive-register" ]]; then
  [[ -n "$VIDEO_PATH" && -f "$VIDEO_PATH" ]] || { echo "video not found: $VIDEO_PATH" >&2; exit 1; }
fi
if [[ "$MODE" == "drive-register" ]]; then
  [[ -n "$DRIVE_ID" ]] || { echo "--drive-id required for drive-register" >&2; exit 1; }
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  gh repo clone "$REPO_SLUG" "$REPO_DIR"
fi
cd "$REPO_DIR"
if [[ "$DRY_RUN" -eq 0 ]]; then
  git fetch origin main -q
  git checkout main -q
  git pull --ff-only origin main -q
fi

mkdir -p videos tools posters
LOCAL_JSON="videos/local.json"
[[ -f "$LOCAL_JSON" ]] || echo '[]' > "$LOCAL_JSON"

python3 - "$LOCAL_JSON" "$ID" "$REPLACE" <<'PY'
import json, sys
path, id_, replace = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
d = json.load(open(path, encoding="utf-8"))
exists = any(str(x.get("id")) == id_ for x in d)
if exists and not replace:
    sys.exit(f"id already exists in local.json: {id_} (pass --replace)")
if not exists and replace:
    print(f"note: --replace but id {id_} not found; will append", file=sys.stderr)
PY

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ASSET_NAME="${ID}.mp4"
OUT_MP4="$TMP/$ASSET_NAME"
OUT_JPG="$TMP/${ID}.jpg"
VIDEO_URL=""
PLAY_VIA=""
HAS_POSTER=0

probe_len_res() {
  local src="$1"
  local probe_json
  probe_json="$(ffprobe -v error -show_entries format=duration:stream=codec_type,width,height -of json "$src")"
  read -r SRC_DUR SRC_W SRC_H <<<"$(python3 -c 'import json,sys;d=json.loads(sys.argv[1]);streams=d.get("streams")or[];v=next((s for s in streams if s.get("codec_type")=="video"),{});print(float(d.get("format",{}).get("duration")or 0), int(v.get("width")or 0), int(v.get("height")or 0))' "$probe_json")"
  if [[ -z "$LEN" ]]; then
    LEN="$(python3 -c 'import sys;d=float(sys.argv[1]);print(f"{int(round(d))}초" if d else "")' "$SRC_DUR")"
  fi
  if [[ -z "$RES" ]]; then
    if (( SRC_H >= 1080 || SRC_W >= 1080 )); then RES="1080p"
    elif (( SRC_H >= 720 || SRC_W >= 720 )); then RES="720p"
    else RES="${SRC_W}x${SRC_H}"; fi
  fi
}

make_poster() {
  local src="$1"
  if ffmpeg -y -hide_banner -loglevel error -i "$src" -ss 0.3 -frames:v 1 -q:v 3 "$OUT_JPG"; then
    HAS_POSTER=1
  fi
}

if [[ "$MODE" == "release" ]]; then
  echo "== remux +faststart (no re-encode) → release asset"
  probe_len_res "$VIDEO_PATH"
  if ! ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
      -map 0:v:0 -map '0:a:0?' -c copy -movflags +faststart -f mp4 "$OUT_MP4"; then
    echo "copy remux failed; trying remux with aac audio copy fallback" >&2
    ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
      -c:v copy -c:a aac -b:a 192k -movflags +faststart -f mp4 "$OUT_MP4"
  fi
  SIZE_B=$(stat -c%s "$OUT_MP4")
  SIZE_MB=$(python3 -c "print(round($SIZE_B/1024/1024,2))")
  echo "   size: ${SIZE_MB} MB (original quality)"
  if python3 -c "import sys; sys.exit(0 if $SIZE_B > ${RELEASE_HARD_MB}*1024*1024 else 1)"; then
    echo "ERROR: ${SIZE_MB}MB > ~${RELEASE_HARD_MB}MB GitHub release soft cap" >&2
    exit 1
  fi
  make_poster "$OUT_MP4"
  TAG="video-${ID}"
  VIDEO_URL="https://github.com/${REPO_SLUG}/releases/download/${TAG}/${ASSET_NAME}"
  PLAY_VIA="release"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if gh release view "$TAG" >/dev/null 2>&1; then
      gh release upload "$TAG" "$OUT_MP4" --clobber
    else
      gh release create "$TAG" "$OUT_MP4" --title "video: ${TITLE}" --notes "Gallery asset for id=${ID} (not in Pages/repo tree)." --latest=false
    fi
    echo "   release: https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
  else
    echo "DRY-RUN: would upload to release tag $TAG"
  fi

elif [[ "$MODE" == "repo" ]]; then
  echo "== re-encode into repo videos/${ID}.mp4 (crf=$CRF)"
  probe_len_res "$VIDEO_PATH"
  ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
    -vf "scale='min(1280,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -c:v libx264 -pix_fmt yuv420p -crf "$CRF" -preset "$PRESET" \
    -c:a aac -b:a 128k -ac 2 -movflags +faststart \
    "$OUT_MP4"
  SIZE_B=$(stat -c%s "$OUT_MP4")
  if python3 -c "import sys; sys.exit(0 if $SIZE_B > ${MAX_MB}*1024*1024 else 1)"; then
    ffmpeg -y -hide_banner -loglevel error -i "$VIDEO_PATH" \
      -vf "scale='min(1280,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
      -c:v libx264 -pix_fmt yuv420p -crf $((CRF+4)) -preset "$PRESET" \
      -c:a aac -b:a 96k -ac 2 -movflags +faststart \
      "$OUT_MP4"
    SIZE_B=$(stat -c%s "$OUT_MP4")
  fi
  SIZE_MB=$(python3 -c "print(round($SIZE_B/1024/1024,2))")
  echo "   compressed: ${SIZE_MB} MB"
  if python3 -c "import sys; sys.exit(0 if $SIZE_B > ${HARD_MB}*1024*1024 else 1)"; then
    echo "ERROR: still ${SIZE_MB}MB > ${HARD_MB}MB — use --mode release instead" >&2
    exit 1
  fi
  make_poster "$OUT_MP4"
  mkdir -p videos
  cp -f "$OUT_MP4" "videos/${ID}.mp4"
  VIDEO_URL="videos/${ID}.mp4"
  PLAY_VIA="repo"

elif [[ "$MODE" == "drive-register" ]]; then
  echo "== register Drive id $DRIVE_ID (no file upload; iframe playback)"
  PLAY_VIA="drive"
  VIDEO_URL=""
  # optional poster from provided video path
  if [[ -n "${VIDEO_PATH:-}" && -f "${VIDEO_PATH:-}" ]]; then
    probe_len_res "$VIDEO_PATH"
    make_poster "$VIDEO_PATH"
  fi
fi

POSTER_REL=""
if [[ "$HAS_POSTER" -eq 1 ]]; then
  mkdir -p videos
  cp -f "$OUT_JPG" "videos/${ID}.jpg"
  POSTER_REL="videos/${ID}.jpg"
fi

python3 - "$LOCAL_JSON" "$ID" "$TITLE" "$RATIO" "$DATE" "$EN" "$KO" "$LEN" "$RES" \
  "$VIDEO_URL" "$PLAY_VIA" "$DRIVE_ID" "$POSTER_REL" "$REPLACE" <<'PY'
import json, sys
(path, id_, title, ratio, date, en, ko, length, res,
 video_url, play_via, drive_id, poster, replace) = sys.argv[1:15]
replace = replace == "1"
d = json.load(open(path, encoding="utf-8"))
e = {
  "id": id_,
  "title": title,
  "ratio": ratio,
  "date": date,
  "en": en,
  "ko": ko,
  "len": length,
  "res": res,
  "playVia": play_via,
}
if video_url:
  e["video"] = video_url
if poster:
  e["poster"] = poster
if drive_id:
  e["driveId"] = drive_id
# remove old entry if replace
d = [x for x in d if str(x.get("id")) != id_]
d.append(e)
json.dump(d, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
print("local.json ←", id_, play_via, video_url or drive_id, f"({len(d)} entries)")
PY

# If switching away from repo mode, drop old in-repo mp4
if [[ "$MODE" != "repo" && -f "videos/${ID}.mp4" ]]; then
  # only delete if it is a local gallery file (not a Drive-synced long id)
  if [[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#ID} -lt 40 ]]; then
    echo "== removing in-repo mp4 videos/${ID}.mp4 (quality/capacity: not keeping compressed copy)"
    git rm -f "videos/${ID}.mp4" 2>/dev/null || rm -f "videos/${ID}.mp4"
  fi
fi

SELF_SRC="${BASH_SOURCE[0]}"
if [[ -f "$SELF_SRC" ]]; then
  cp -f "$SELF_SRC" tools/gallery-video-upload.sh
  chmod +x tools/gallery-video-upload.sh
fi

echo "== done files:"
ls -lh "videos/${ID}.jpg" 2>/dev/null || true
[[ "$MODE" == "repo" ]] && ls -lh "videos/${ID}.mp4" || true
python3 -c "import json;print([x for x in json.load(open('videos/local.json')) if x.get('id')=='$ID'][0])"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN: skipped commit/push"
  git status --short | head -40
  exit 0
fi

git add "$LOCAL_JSON" tools/gallery-video-upload.sh
[[ -n "$POSTER_REL" && -f "$POSTER_REL" ]] && git add "$POSTER_REL"
[[ "$MODE" == "repo" ]] && git add "videos/${ID}.mp4"
# staged deletions
git add -u videos 2>/dev/null || true
git -c user.name="$OWNER_NAME" -c user.email="$OWNER_EMAIL" commit -m "Add/update video (${MODE}): ${TITLE}"
if [[ "${NO_PUSH:-0}" == "1" ]]; then
  echo "NO_PUSH=1: commit done, not pushed"
else
  git push origin HEAD:main
  echo "pushed. site: https://kmuse996-bot.github.io/video-gallery/"
fi
