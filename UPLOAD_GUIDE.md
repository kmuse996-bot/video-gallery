# video-gallery 업로드 가이드 (고화질 / 용량 분리)

대상 저장소: `kmuse996-bot/video-gallery`
라이브: https://kmuse996-bot.github.io/video-gallery/

## 왜 Release인가

- GitHub Pages / 저장소 soft limit ≈ **1GB**. 시트→Actions 동기화는 Drive 파일을 `videos/<DriveId>.mp4`로 **저장소에 복사**한다. 원본 1080p를 계속 넣으면 Pages 용량이 금방 찬다.
- **GitHub Release 에셋**은 파일당 최대 약 **2GB**, **Pages/repo 용량에 포함되지 않는다**. 브라우저에서 `<video src="release URL">` 재생이 확인됐다(CORS 없이도 동작, content-type이 octet-stream이어도 Chrome이 재생).
- Google Drive 업로드는 Cursor `UploadFile(connection=google-drive)` 도구로 가능하지만, **지금 이 봇 환경에서는 Drive MCP가 설치만 되어 있고 로그인(`needsAuth`)되지 않았다**. 셸 rclone/서비스계정 업로드도 없다. Drive를 쓰려면 오너가 Drive 커넥터에 로그인한 뒤 **2단계**(도구 업로드 → `drive-register`)를 쓴다.

## 탑(bot)용 한 줄 명령 (권장 · 원본 화질)

```bash
/home/box/reference/gallery-video-upload.sh \
  "/path/to/original.mp4" <id> "<제목>" <비율> <YYYY-MM-DD> "<영문설명>" "<한글설명>"
```

기본 `--mode release`: **재인코딩 없음**(faststart remux만). Release 에셋 + `videos/local.json` + (작은) 포스터 jpg만 커밋. mp4는 저장소에 넣지 않는다.

예:

```bash
/home/box/reference/gallery-video-upload.sh \
  /workspace/video-src/crane-obi-untie-orig.mp4 \
  crane-obi-untie "학 매듭 풀기" 3/2 2026-04-18 \
  "Unfastening a crane-shaped decorative knot." \
  "학 모양 장식 매듭을 푸는 장면."
```

같은 id를 덮어쓸 때: `--replace` 추가.

## 모드

| 모드 | 명령 | 결과 |
|------|------|------|
| **release** (기본) | `--mode release` | 원본 화질 → GitHub Release. Pages 용량 밖. |
| **repo** | `--mode repo` | 예전처럼 CRF 압축 후 `videos/<id>.mp4` 커밋. 용량 빡쁠 때만. |
| **drive-register** | `--mode drive-register --drive-id <ID>` | Drive에 이미 올린 파일 id만 등록. iframe 재생. **시트 I열에 넣지 말 것**(Actions가 repo로 복사함). |

### Drive 2단계 (커넥터 로그인 후)

1. Cursor `UploadFile`로 mp4를 Drive 카메라 폴더(`1u2_waUmtWEUVaM4dWH76ChI8yu4hn4Js`)에 업로드 → file id 확보.
2. 등록만:

```bash
/home/box/reference/gallery-video-upload.sh --mode drive-register --drive-id <FILE_ID> \
  <id> "<제목>" <비율> <YYYY-MM-DD> "<en>" "<ko>"
```

시트에 Drive id를 적으면 Actions가 다시 repo에 복사하므로 **고화질은 시트 I열에 넣지 않는다.**

## JSON 일괄

```bash
/home/box/reference/gallery-video-upload.sh --json /tmp/entry.json
```

```json
{
  "video_path": "/path/to.mp4",
  "id": "my-clip",
  "title": "제목",
  "ratio": "9/16",
  "date": "2026-10-29",
  "en": "...",
  "ko": "...",
  "mode": "release"
}
```

## dry-run / 푸시 끄기

```bash
... --dry-run ...
NO_PUSH=1 ...
```

## id 규칙

소문자·숫자·하이픈만 (`crane-obi-untie`). Drive 동기화 id(긴 문자열)와 섞이지 않게 짧게.

## 기존 시트(Drive) 항목

그대로 유지. Actions가 시트 I열 Drive id → `videos/<id>.mp4` 동기화. 고화질 신규는 **release 또는 drive-register(시트 밖)** 로만 추가.
