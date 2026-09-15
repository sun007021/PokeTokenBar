---
summary: "릴리스 실행 절차 — 문서·에셋 갱신 의무, 스크린샷 재생성 방법, release.sh 게이트의 함정."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 가 문서·에셋 경고나 하드 게이트로 중단됐을 때
  - UI 를 바꿔 스크린샷·랜딩을 갱신해야 할 때
  - PokeTokenBar Extended 를 배포할 때(서명·공증·DMG) — §PokeTokenBar Extended 릴리스
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
- **스크린샷(`assets/`)**: UI(`Sources/PokeTokenBarExtended/UI/`) 변경 시 재생성. 기존 방식 = **HTML 렌더**
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

## PokeTokenBar Extended 릴리스 (`APP_NAME="PokeTokenBarExtended"` 인 체크아웃)

위 1~3 절은 **상류**(`chattymin/PokeTokenBar`) 기준이다. 이 저장소는 표면이 다르므로
`release.sh` 가 `scripts/build-app.sh` 의 `APP_NAME` 을 보고 **다른 경로**로 갈라진다.
버전은 상류와 별개로 1.0.0 부터 매긴다(`docs/reference/mobius-integration.md` §버전 표기).

```bash
# 한 번만: 공증 자격을 Keychain 프로필로 저장 (암호 = appleid.apple.com 앱 암호)
xcrun notarytool store-credentials PokeTokenBarExtended \
  --apple-id <Apple ID> --team-id TYN557Y96W

# 릴리스 (main 브랜치, 깨끗한 작업트리)
CODESIGN_IDENTITY="Developer ID Application: Sunwook Lee (TYN557Y96W)" \
  PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh patch   # 또는 minor | major | 1.2.0
```

검토만: `./scripts/release.sh --check-only`.

### 단계 (9)

1. `test-gate.sh` 2. 문서 검토(README 의 최신 DMG 링크 존재 포함) 3. 서명·공증 자격 게이트 —
   Developer ID 필수, `notarytool history` 로 프로필을 **빌드 전에** 확인 4. `VERSION=` 범프(미커밋)
5. `PTB_SKIP_INSTALL=1 build-app.sh` — 설치·pkill 없이 번들만, hardened runtime 검증
6. 앱 zip 공증 → `stapler staple` → staple 된 앱으로 zip 재생성 → `spctl` 이 `Notarized Developer ID` 인지
7. DMG(앱 + `/Applications` 심볼릭 링크) 생성 → 서명 → 공증 → staple → `spctl -t open` 확인
8. 범프 커밋·주석 태그·push 9. GitHub Release 에 `.dmg` + `.zip`, 설치 안내 노트 자동 첨부

5~7 에서 실패하면 아직 아무것도 push 되지 않았다 — `git checkout scripts/build-app.sh` 로 되돌린다.

### 상류와 무엇이 다른가

| 단계 | 상류 | 이 저장소 | 왜 |
|---|---|---|---|
| 배포 대상 | `chattymin/PokeTokenBar` | `origin` 에서 파생 (`PTB_RELEASE_REPO`) | 하드코딩이면 권한 없는 상류에 쏜다 |
| 버전 인자 | `x.y.z` | `x.y.z` 또는 `patch`/`minor`/`major` | CLAUDE.md §릴리스의 세그먼트 단어를 그대로 받는다 |
| 자산 | zip | **공증된 DMG** + zip | 다운로드한 파일에 quarantine 이 붙어도 Gatekeeper 가 경고 없이 연다 |
| 태그 충돌 검사 | 로컬 | 로컬 + **origin** | 상류에서 넘어온 `v2.4.5`~`v2.5.x` 태그가 origin 에 남아 있다 |
| 문서 게이트 | README·assets·랜딩·cask | README.md/ko 의 다운로드 링크 + `mobius-integration.md` | 이 앱은 랜딩·cask·스크린샷 게이트를 유지하지 않는다 |
| Homebrew cask / Pages | 갱신 | **없음** | tap·랜딩이 없다 |
| 작업트리 | 검사 없음 | **깨끗해야 시작** | 범프 커밋에 관계없는 스테이징이 딸려 들어가는 것 방지 |

### 서명·공증 — 자산은 로컬에서만 만든다

릴리스 자산은 **이 머신에서** 만든다. CI 러너에는 인증서가 없어 ad-hoc 서명밖에 못 하는데,
ad-hoc 은 **리빌드마다 코드 정체성이 바뀌어** 사용자 Keychain 의 "항상 허용"을 매번 리셋한다 —
계정 전환 기능이 Keychain 을 쓰므로 고정 서명이 사실상 필수다.

- `build-app.sh` 는 신원이 `Developer ID Application:` 이면 `--options runtime --timestamp` 로 서명한다
  (공증 필수 조건). 이 앱은 JIT·서명 안 된 dylib·Apple Events 를 쓰지 않아 entitlement 가 필요 없다.
  hardened runtime 여부는 지정 요구사항(DR)을 바꾸지 않으므로 기존 Keychain 승인에 영향이 없다.
- 공증 판정은 `notarytool submit --wait` 의 종료 코드가 아니라 JSON `status == Accepted` 로 본다.
  거부되면 스크립트가 `notarytool log <id>` 명령을 출력한다.
- 앱과 DMG 를 **각각** staple 한다 — DMG 만 staple 하면 DMG 에서 꺼낸 앱은 오프라인에서 공증 확인을
  못 한다.

### CI (`.github/workflows/release.yml`)

태그(`v*`) push 에 붙는 **검증 전용** 워크플로다: 릴리스 구성 빌드 + `test-gate.sh` +
"태그가 `build-app.sh` 의 `VERSION` 과 일치하는가". 자산은 만들지도 올리지도 않는다(위 서명 이유).

### 배포 후

인앱 업데이트 배너는 **이 저장소**의 `releases/latest` 를 본다(`UpdateChecker.releaseRepo`).
README 의 다운로드 링크 `releases/latest/download/PokeTokenBarExtended.dmg` 도 같은 릴리스를 가리킨다 —
릴리스 직후 그 링크로 DMG 가 받아지는지 확인한다.
