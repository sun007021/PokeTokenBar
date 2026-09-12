---
summary: "릴리스 실행 절차 — 문서·에셋 갱신 의무, 스크린샷 재생성 방법, release.sh 게이트의 함정."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 가 문서·에셋 경고나 하드 게이트로 중단됐을 때
  - UI 를 바꿔 스크린샷·랜딩을 갱신해야 할 때
  - mobius 포크(`FORK_BUILD` 가 있는 체크아웃)를 배포할 때 — §포크 릴리스
---

# 릴리스 실행 절차

버전 결정 규칙과 트리거는 `CLAUDE.md` §릴리스에 있다. 이 문서는 그 다음의 *실행 세부*를 담는다.
체크리스트 원본은 `RELEASE.md`.

## 1. 문서·이미지 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다)

`./scripts/release.sh --check-only` 로 경고를 확인한 뒤 아래를 모두 반영한다.

- **README.md/ko/ja**: 기능 목록·how-it-works·스크린샷 참조.
- **랜딩(gh-pages orphan 브랜치) — 필수.** `git worktree add /tmp/ptb-ghpages gh-pages` → `index.html`
  기능 카드(f#) + i18n 사전(en/ko/ja 동시·키 정합) 갱신 → 커밋 → `git push origin gh-pages` →
  `git worktree remove`. (Pages 자동 재빌드. 커밋은 gh-pages log 모방 = `landing:` 프리픽스.)
- **스크린샷(`assets/`)**: UI(`Sources/PokeTokenBar/UI/`) 변경 시 재생성. 기존 방식 = **HTML 렌더**
  (팝오버 라이브 캡처 아님) — Chrome `--headless --screenshot --force-device-scale-factor=2` 로 다크
  팝오버를 720px PNG 로 그린다. 애니 GIF(home)는 프레임 합성 후 `gifsicle -O3 --lossy` 로 최적화
  (PIL 재인코딩 단독은 용량 팽창 주의). 언어별 이미지(`settings.png`/`-ko`/`-ja` 등) 각 README 참조.
- homebrew-tap cask caveat.

### 게이트의 함정

- `release.sh` 문서검토는 *커밋된* 상태를 비교 → 스크린샷을 스테이징만 하면 경고 프롬프트가
  여전히 뜬다. 미리 커밋하거나 프롬프트에 `y`(스테이징분이 release.sh line 93-94 에서 릴리스 커밋에 함께 담김).
- **신규 기능 = 신규 에셋 (하드 게이트, 프롬프트로 못 넘김).** 직전 태그 이후 `Sources/**/UI/` 를 건드린
  `feat:` 커밋이 있는데 `assets/` 에 **새로 추가된** 파일이 없으면 `release.sh` 가 중단한다
  (**예외 없음** — 통과시키려면 에셋을 만들거나 커밋 타입을 바꿔야 한다). 기존 staleness 검사는 "에셋이 하나라도 바뀌었나"만
  보기 때문에 **기존 스크린샷만 다시 그려도 통과**한다 — 2.5.0 에서 플로팅 펫이 이미지 없이 나간 경로가
  정확히 이것이다(`settings.png` 를 갱신해 둔 탓에 조용히 통과). 갱신(stale)과 커버리지(신규)는 다른 질문이다.

## 2. 실행

릴리스 노트를 작성한 뒤 반드시 `main` 브랜치에서:

```bash
# 직전 릴리스 이후 변경을 요약해 노트 파일 작성
PTB_NOTES_FILE=/tmp/ptb-notes.md ./scripts/release.sh <version>
```

스크립트가 test-gate → 문서검토 → 범프 → 빌드검증 → 커밋·push → GitHub Release → cask → Pages 를
순서대로 수행한다.

## 3. 검증

완료 후 `brew upgrade --cask poke-token-bar` 로 실제 업그레이드 동작을 확인한다.

## 포크 릴리스 (mobius — `FORK_BUILD` 가 있는 체크아웃)

위 1~3 절은 **상류**(`chattymin/PokeTokenBar`) 기준이다. 이 포크는 표면이 다르므로
`release.sh` 가 `scripts/build-app.sh` 의 `FORK_BUILD=` 를 보고 **다른 경로**로 갈라진다.
(`docs/reference/mobius-integration.md` §`release.sh` 는 이 포크에서 돌지 않는다 는 이 경로가
생기기 전 기록이다 — 지금은 돈다.)

```bash
# 평소 포크 릴리스: FORK_BUILD 만 +1  (2.5.3+mobius.1 → 2.5.3+mobius.2)
CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
  PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh

# 상류 rebase 로 기준점이 올라갔을 때: UPSTREAM_VERSION 갱신 + FORK_BUILD=1
CODESIGN_IDENTITY="…" ./scripts/release.sh --upstream 2.5.4
```

검토만: `./scripts/release.sh --check-only` (포크에서는 포크용 체크리스트가 나온다).

### 상류와 무엇이 다른가

| 단계 | 상류 | 포크 | 왜 |
|---|---|---|---|
| 브랜치 | `main` | `mobius-integration` (`PTB_RELEASE_BRANCH`) | 포크 작업 브랜치 |
| 배포 대상 | `chattymin/PokeTokenBar` | `origin` 에서 파생 (`PTB_RELEASE_REPO`) | 하드코딩이면 권한 없는 상류에 쏜다 |
| 버전 | `VERSION="x.y.z"` 한 줄 | `UPSTREAM_VERSION`+`FORK_BUILD` 두 변수 | §버전 표기 — 평평한 리터럴로 덮으면 포크 표기가 사라진다 |
| 태그 | `vX.Y.Z` | `vX.Y.Z+mobius.N` | 번들의 `CFBundleShortVersionString` 과 **같은 문자열**. `+` 는 git ref 로 유효함을 확인했다(`git check-ref-format`, 실제 태그 생성·`rev-parse`·`describe` 왕복) |
| 문서 게이트 | README·assets·랜딩·cask | `mobius-integration.md` 하나 | 상류 표면은 이 포크가 유지하지 않는다(§상류 rebase: "README*.md 는 상류 파일") |
| Homebrew cask | 버전 갱신 | **단계 없음** | 이 포크엔 tap 이 없고, cask 자체가 금지다 — 같은 번들 ID·같은 경로라 `brew upgrade` 가 포크를 상류 빌드로 덮는다 |
| 랜딩/Pages | 재빌드 요청 | 없음 | 포크는 랜딩을 유지하지 않는다 |
| 작업트리 | 검사 없음 | **깨끗해야 시작** | 범프 커밋에 관계없는 스테이징이 딸려 들어가는 것 방지 |

### 서명·공증 — 자산은 로컬에서만 만든다

릴리스 자산은 **이 머신에서** 만든다. CI 러너에는 인증서가 없어 ad-hoc 서명밖에 못 하는데,
ad-hoc 은 **리빌드마다 코드 정체성이 바뀌어** 사용자 Keychain 의 "항상 허용"을 매번 리셋한다 —
계정 전환 기능이 Keychain 을 쓰므로 고정 서명이 사실상 필수다. `release.sh` 의 서명 게이트와
`PTB_REQUIRE_STABLE_SIGN=1` 이 ad-hoc 폴백을 막는다.

★ **Developer ID 서명이어도 공증(notarization)은 안 돼 있다.** 로컬 `cp -R` 설치는 quarantine 이
안 붙어 문제가 없지만(§빌드·설치), **릴리스 zip 은 다운로드되므로 quarantine 이 붙고 Gatekeeper 가
막는다.** 그래서 `release.sh` 가 릴리스 노트 맨 앞에 `xattr -d com.apple.quarantine` 안내를
**자동으로** 붙인다 — 사람이 기억할 일로 남기지 않는다.

### CI (`.github/workflows/release.yml`)

태그(`v*`) push 에 붙는 **검증 전용** 워크플로다: 릴리스 구성 빌드 + `test-gate.sh` +
"태그가 `build-app.sh` 의 버전과 일치하는가". 자산은 만들지도 올리지도 않는다(위 서명 이유).
`build-app.sh` 는 마지막에 `pkill` 하고 `/Applications` 를 교체하는 **설치 스크립트**라
CI 에서 돌리지 않는다.

- `workflow_dispatch` 는 워크플로 파일이 **저장소 기본 브랜치**에 있어야 UI 에 뜬다.
  기본 브랜치가 `main` 인 동안에는 태그 트리거만 동작한다(태그 트리거는 태그가 가리키는
  커밋의 워크플로를 쓰므로 기본 브랜치와 무관하다).
- `ci.yml` 은 `main` 브랜치/PR 에만 붙어 있어 `mobius-integration` push 에는 **안 돈다.**
  포크 작업 중 상시 CI 가 필요하면 그 트리거를 넓혀야 한다(상류 공유 파일이라 rebase 충돌
  면적이 늘어나는 것과 맞바꾼다).

### 배포 후

인앱 업데이트 배너는 **상류** `releases/latest` 를 본다(`UpdateChecker.repo =
chattymin/PokeTokenBar`, 의도된 결정). 즉 **포크 릴리스는 배너로 전달되지 않는다** —
자신이 릴리스 페이지에서 받거나 소스에서 다시 빌드하는 것이 유일한 갱신 경로다.
