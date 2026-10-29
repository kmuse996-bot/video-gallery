# 동영상 갤러리 업로드 가이드 (모든 봇 공용)

- 저장소: https://github.com/kmuse996-bot/video-gallery (브랜치 `main`)
- 사이트: https://kmuse996-bot.github.io/video-gallery/ (push 후 1~2분 뒤 반영, 비밀번호 잠금)
- 이 컴퓨터(모든 봇이 함께 쓰는 박스)에서 `gh`가 kmuse996-bot 계정으로 로그인돼 있음. `gh auth status`로 확인.
- 로그인이 풀렸다면 '프로그래밍' 봇에게 다시 로그인을 부탁할 것.

## 권장 방식 (Google Drive 없이)

박스에 있는 mp4를 **저장소 `videos/`에 직접** 넣고 `videos/local.json`에 메타를 추가한 뒤 push 하면 끝.
시트로 올리던 Drive 경로도 그대로 동작한다(기존 항목 유지).

### 구조
- `videos/<id>.mp4` : 재생용 영상 (h264 + aac, `+faststart`, 긴 변 ≤1280)
- `videos/<id>.jpg` : 포스터(자동 생성, 선택)
- `videos/local.json` : **로컬 업로드** 메타 배열
- `videos/index.json` : Drive 동기화로 받은 파일 id 목록 (자동, 손대지 말 것)
- 시트 `영상프롬` : 예전 Drive 업로드 경로 (선택, 병행 가능)

### local.json 항목 형식
```json
{
  "id": "cat-pushup-meow",
  "title": "제목",
  "video": "videos/cat-pushup-meow.mp4",
  "poster": "videos/cat-pushup-meow.jpg",
  "ratio": "9/16",
  "date": "2026-10-29",
  "len": "15초",
  "res": "720p",
  "en": "English prompt",
  "ko": "한글 프롬프트"
}
```
- 새 항목은 배열 **맨 끝**에 추가. 사이트는 날짜 최신순.
- `id`는 영문 소문자·숫자·하이픈만, **중복 금지**. Drive 파일 id와 겹치지 않게 짧은 슬러그 사용.

### 한 줄 명령 (봇용)
```bash
/home/box/reference/gallery-video-upload.sh \
  /workspace/내영상.mp4 <id> "<제목>" "9/16" "2026-10-29" "English prompt" "한글 프롬프트"
```
또는 JSON:
```bash
/home/box/reference/gallery-video-upload.sh --json /tmp/entry.json
# entry.json 예: {"video_path":"/workspace/a.mp4","id":"...","title":"...","ratio":"9/16","date":"YYYY-MM-DD","en":"...","ko":"..."}
```
- 저장소 복사본: `video-gallery/tools/gallery-video-upload.sh` (같은 스크립트)
- `--dry-run` : 압축·파일 기록만, 커밋/푸시 안 함
- 스크립트가 ffmpeg로 압축(crf≈23) → `videos/<id>.mp4` + 포스터 → `local.json` append → kmuse996-bot으로 커밋 → `main` push

### 한도
- GitHub 파일 **100MB** 초과 불가. 스크립트는 약 **95MB**에서 실패. 소프트 목표 **40MB**(넘으면 crf를 한 단계 올려 재압축).
- GitHub Pages 사이트 용량 약 **1GB**. 지금처럼 클립당 수~십수 MB면 수십~백여 개 수준.
- 너무 큰 원본은 길이를 줄이거나 해상도를 낮출 것. (Release asset은 Pages와 별도 origin이라 기본 경로에서는 쓰지 않음.)

### 주의
- 사용자가 **명시적으로** 갤러리에 올려 달라고 한 영상만 올릴 것.
- 기존 Drive/시트 항목을 지우거나 `videos/<DriveId>.mp4`·`index.json`을 함부로 수정하지 말 것.
- 비밀번호·시트 ID 등 운영 세부는 저장소 `README.md` 참고.

## 예전 방식 (Drive + 시트) — 병행 가능
1. mp4→mov 리먹스 후 Drive 폴더 업로드 + 시트 `영상프롬` A–H열 행 추가
2. Actions `sync-videos`가 15분마다 Drive → `videos/<id>.mp4` 동기화
3. 자세한 절차는 `README.md` §3
