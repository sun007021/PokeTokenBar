#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 배포 대상 저장소는 origin 에서 파생한다. 하드코딩(`chattymin/*`)이면 이 포크에서 돌 때
# 권한 없는 상류에 릴리스를 만들려다 죽는다 — 포크를 또 포크해도 그대로 동작하게 한다.
origin_slug() {
  local url; url=$(git remote get-url origin 2>/dev/null || echo "")
  url="${url%.git}"
  case "$url" in
    git@*:*)        echo "${url##*:}" ;;
    *github.com/*)  echo "${url#*github.com/}" ;;
    *)              echo "" ;;
  esac
}
UPSTREAM_SLUG="chattymin/PokeTokenBar"
REPO="${PTB_RELEASE_REPO:-$(origin_slug)}"
CASK_PATH="Casks/poke-token-bar.rb"

# Homebrew tap 은 상류에만 있다. 포크에는 tap 이 없으므로 그 단계를 아예 넣지 않는다 —
# 없는 tap 에 PUT 을 쏘면 GitHub Release 는 이미 만들어진 채 스크립트가 죽어서
# "릴리스가 반쯤 된" 상태로 남는다. (포크에서 cask 자체가 금지인 이유는
# docs/reference/mobius-integration.md §Homebrew cask 는 제거한다 — 같은 번들 ID·같은 설치
# 경로라 `brew upgrade` 한 번에 포크가 상류 빌드로 조용히 덮어써진다.)
if [[ -n "${PTB_TAP_REPO:-}" ]]; then
  TAP_REPO="$PTB_TAP_REPO"
elif [[ "$REPO" == "$UPSTREAM_SLUG" ]]; then
  TAP_REPO="chattymin/homebrew-tap"
else
  TAP_REPO=""
fi

doc_check() {
  local warn=0
  echo "▶ 문서 일관성 검토"
  if grep -rnE "img.shields.io/badge/release-v[0-9]" README*.md 2>/dev/null; then
    echo "  ⚠ README 에 정적 버전 배지가 있습니다(동적 github/v/release 배지 권장)."; warn=1
  fi
  for pat in ccusage; do
    if grep -rniq "$pat" README*.md 2>/dev/null; then
      echo "  ⚠ README 에 '$pat' 잔존 — 제거된 항목인지 확인."; warn=1
    fi
  done
  local last_tag ui_changed shot_changed
  last_tag=$(git describe --tags --match "v*" --abbrev=0 2>/dev/null || echo "")
  if [[ -n "$last_tag" ]]; then
    ui_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/PokeTokenBarExtended/UI/' 2>/dev/null)
    shot_changed=$(git diff --name-only "$last_tag"..HEAD -- 'assets/settings*' 'assets/screenshot*' 'assets/menubar*' 'assets/shiny*' 2>/dev/null)
    if [[ -n "$ui_changed" && -z "$shot_changed" ]]; then
      echo "  ⚠ UI 소스가 $last_tag 이후 변경됐으나 스크린샷(assets/) 갱신 없음 — README 이미지 stale 가능:"
      echo "$ui_changed" | sed 's/^/       /'
      echo "     → 변경된 화면이면 assets 스크린샷 재생성 (README.md/ko/ja 각 언어)."
      warn=1
    fi

    local ui_feats new_assets
    ui_feats=$(git log "$last_tag"..HEAD --format='%s' -- 'Sources/PokeTokenBarExtended/UI/' 2>/dev/null \
                 | grep -iE '^(feat|feature)[(:]' || true)
    new_assets=$(git diff --name-only --diff-filter=A "$last_tag"..HEAD -- 'assets/' 2>/dev/null)
    if [[ -n "$ui_feats" && -z "$new_assets" ]]; then
      echo "  ✗ UI 를 바꾼 신규 기능이 있는데 assets/ 에 **새로 추가된** 파일이 없습니다:"
      echo "$ui_feats" | sed 's/^/       /'
      echo "     → 새 화면·새 표면이면 전용 스크린샷을 만들어 README(ko/ja 포함)와 랜딩에 넣으세요."
      echo "     → 이미지가 정말 불필요하다고 판단되면 그 판단을 커밋에 남기세요(feat 가 아닌 타입으로)."
      return 2
    fi
  fi
  cat <<'CHECK'
  ─ 수동 체크리스트 (내용 변경 시 갱신) ─────────────────────────────
   [ ] README.md / .ko / .ja : 기능 목록·요구사항·데이터소스·스크린샷
   [ ] 랜딩(gh-pages/index.html): hero·features·install·works-with·요구사항·푸터
       · 버전 배지는 동적(github/v/release) → 자동. 기능/문구만 수동.
       · 3개 언어 i18n 사전(en/ko/ja) 동시 갱신 + 키 정합 유지.
   [ ] homebrew-tap cask: caveats(설치 요구사항) 최신 상태인지
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

# PokeTokenBar Extended 전용 문서 검토. 상류 doc_check 를 그대로 쓰면 안 되는 이유:
# 상류의 assets·랜딩·cask 게이트는 이 저장소가 유지하지 않는 표면이고, 특히 `feat:` 하드
# 게이트는 이 앱 커밋 대부분이 UI 를 건드리므로 모든 릴리스를 막아 버린다.
# 이 앱의 문서 표면은 README.md·README.ko.md(설치·다운로드)와 mobius-integration.md 다.
fork_doc_check() {
  local warn=0 last_tag src_changed doc_changed f
  echo "▶ 문서 일관성 검토 (PokeTokenBar Extended)"
  # 상류에서 넘어온 v2.x 태그가 같은 저장소에 섞여 있다 — 이 스크립트가 만든 태그만 고른다
  # (태그 주석에 "PokeTokenBar Extended" 를 넣는다).
  last_tag=$(git tag -l 'v*' -n1 --sort=-v:refname | awk '/PokeTokenBar Extended/ {print $1; exit}')
  if [[ -n "$last_tag" ]]; then
    src_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/' 2>/dev/null)
    doc_changed=$(git diff --name-only "$last_tag"..HEAD -- 'docs/reference/mobius-integration.md' 2>/dev/null)
    if [[ -n "$src_changed" && -z "$doc_changed" ]]; then
      echo "  ⚠ $last_tag 이후 Sources/ 가 바뀌었는데 docs/reference/mobius-integration.md 는 그대로입니다."
      echo "     → 동작·경로·불변식이 바뀌었으면 그 문서를 먼저 갱신하세요."
      warn=1
    fi
  else
    echo "  · 이전 PokeTokenBar Extended 태그 없음 — 첫 릴리스로 간주."
  fi
  # README 의 "최신 DMG" 링크는 자산 파일 이름에 묶여 있다 — 이름이 어긋나면 404 가 된다.
  for f in README.md README.ko.md; do
    grep -qF "releases/latest/download/$APP_NAME.dmg" "$f" || {
      echo "  ⚠ $f 에 최신 DMG 다운로드 링크(releases/latest/download/$APP_NAME.dmg)가 없습니다."
      warn=1; }
  done
  cat <<'CHECK'
  ─ 수동 체크리스트 ──────────────────────────────────────────────────
   [ ] README.md / README.ko.md : 설치·기능·요구사항 (다운로드 링크는 위에서 자동 검사)
   [ ] docs/reference/mobius-integration.md : 버전·빌드/배포·운영 주의사항
   [ ] README.ja.md·assets·랜딩·cask 는 상류 표면이다 — 갱신 대상 아님
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

# 이 체크아웃이 PokeTokenBar Extended 인가 — 산출물 이름(build-app.sh 의 APP_NAME)이 단일 진실이다.
IS_FORK=0
grep -q '^APP_NAME="PokeTokenBarExtended"$' scripts/build-app.sh && IS_FORK=1

# 산출물 이름은 build-app.sh 의 APP_NAME 이 단일 진실이다 — 여기서 다시 적으면 개명 때 조용히
# 어긋나고(실제로 어긋났다), 릴리스가 "빌드는 됐는데 zip 대상이 없다"로 죽는다.
APP_NAME=$(sed -n 's/^APP_NAME="\(.*\)"$/\1/p' scripts/build-app.sh)
[[ -n "$APP_NAME" ]] || { echo "✗ build-app.sh 에서 APP_NAME 을 읽지 못했습니다"; exit 1; }

if [[ "${1:-}" == "--check-only" ]]; then
  if [[ $IS_FORK -eq 1 ]]; then fork_doc_check || true; else doc_check || true; fi
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# PokeTokenBar Extended 릴리스 경로 — 서명 → 공증 → DMG → GitHub Release
# ──────────────────────────────────────────────────────────────────────────────
if [[ $IS_FORK -eq 1 ]]; then
  RELEASE_BRANCH="${PTB_RELEASE_BRANCH:-main}"
  NOTARY_PROFILE="${PTB_NOTARY_PROFILE:-PokeTokenBarExtended}"
  VOLUME_NAME="PokeTokenBar Extended"
  APP="build/$APP_NAME.app"
  ZIP="build/$APP_NAME.zip"
  DMG="build/$APP_NAME.dmg"

  usage_fork() {
    cat <<'USAGE' >&2
사용 (PokeTokenBar Extended):
  ./scripts/release.sh 1.2.0              # 버전 명시
  ./scripts/release.sh patch|minor|major  # 현재 VERSION 기준 세그먼트 올림

  필수: CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)"
  공증: xcrun notarytool store-credentials PokeTokenBarExtended --apple-id <id> --team-id <TEAMID>
        (프로필 이름이 다르면 PTB_NOTARY_PROFILE)
  선택: PTB_NOTES_FILE=/tmp/notes.md      # 릴리스 노트 본문 — 설치 안내는 자동 첨부
USAGE
    exit 1
  }

  # $1 을 공증 서비스에 올리고 Accepted 가 아니면 실패한다. `--wait` 의 종료 코드만 믿지 않고
  # JSON status 를 본다 — Invalid 판정도 "제출·대기는 성공"으로 끝날 수 있다.
  notarize() {
    local file="$1" out status id
    out=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json 2>&1) || true
    status=$(printf '%s' "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")
    id=$(printf '%s' "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
    if [[ "$status" != "Accepted" ]]; then
      echo "✗ 공증 실패: $file (status='${status:-?}')"
      printf '%s\n' "$out" | sed 's/^/    /'
      [[ -n "$id" ]] && echo "  원인: xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE"
      return 1
    fi
    echo "  ✓ 공증 통과: $file ($id)"
  }

  CUR_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)
  [[ "$CUR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "✗ build-app.sh 의 VERSION 을 읽지 못했습니다: '$CUR_VERSION'"; exit 1; }
  IFS=. read -r MAJ MIN PAT <<< "$CUR_VERSION"
  case "${1:-}" in
    ""|-h|--help) usage_fork ;;
    patch) VERSION="$MAJ.$MIN.$((PAT + 1))" ;;
    minor) VERSION="$MAJ.$((MIN + 1)).0" ;;
    major) VERSION="$((MAJ + 1)).0.0" ;;
    *)     VERSION="$1" ;;
  esac
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ 버전 형식 오류: $VERSION" >&2; usage_fork; }
  TAG="v$VERSION"

  [[ -n "$REPO" ]] || { echo "✗ origin 에서 owner/repo 를 못 읽었습니다 — PTB_RELEASE_REPO 로 지정하세요."; exit 1; }
  [[ "$REPO" != "$UPSTREAM_SLUG" ]] || {
    echo "✗ PokeTokenBar Extended 빌드인데 배포 대상이 상류($UPSTREAM_SLUG)입니다 — origin 을 확인하세요."; exit 1; }

  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  [[ "$BRANCH" == "$RELEASE_BRANCH" ]] || {
    echo "✗ $RELEASE_BRANCH 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push/태그 대상 일치 보장"; exit 1; }

  # 작업트리가 더러우면 중단한다: 범프 커밋이 `git add scripts/build-app.sh` 로 좁게 스테이징돼도
  # 이미 스테이징된 남의 변경이 있으면 그대로 릴리스 커밋에 딸려 들어간다.
  [[ -z "$(git status --porcelain)" ]] || {
    echo "✗ 작업트리가 깨끗하지 않습니다 — 릴리스 커밋에 관계없는 변경이 딸려 들어갑니다:"
    git status --short | sed 's/^/    /'
    exit 1; }

  # 상류에서 넘어온 v2.x 태그가 origin 에 남아 있다 — 로컬뿐 아니라 원격도 본다.
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
     || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "✗ 태그 $TAG 가 이미 있습니다(로컬 또는 origin)."; exit 1
  fi

  echo "=== PokeTokenBar Extended 릴리스 $CUR_VERSION → $VERSION ==="
  echo "    저장소: $REPO   브랜치: $RELEASE_BRANCH   태그: $TAG"

  echo "▶ 1/9 릴리스 전 테스트 게이트"
  ./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
  echo "  ✓ 통과"

  echo "▶ 2/9 문서 검토"
  doc_rc=0; fork_doc_check || doc_rc=$?
  if [[ $doc_rc -ne 0 ]]; then
    read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
    [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
  fi

  echo "▶ 3/9 서명·공증 자격 게이트"
  # ad-hoc 서명은 리빌드마다 코드 정체성이 바뀌어 사용자 Keychain '항상 허용'이 매번
  # 리셋되고, 공증은 Developer ID 서명만 받는다 — 배포 자산은 Developer ID 로만 만든다.
  SIGN_IDENTITY="${CODESIGN_IDENTITY:?CODESIGN_IDENTITY 를 지정하세요 (예: \"Developer ID Application: … (TEAMID)\")}"
  [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]] || {
    echo "✗ 공증하려면 Developer ID Application 인증서가 필요합니다: '$SIGN_IDENTITY'"; exit 1; }
  LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" 'index($0, id) {print $2; exit}')
  [[ -n "$LEAF" ]] || { echo "✗ 유효 codesigning identity '$SIGN_IDENTITY' 없음(미설치·만료 포함)."; exit 1; }
  LEAF_PIN="scripts/fork-signing-leaf.txt"
  if [[ -f "$LEAF_PIN" ]]; then
    PINNED=$(tr -d '[:space:]' < "$LEAF_PIN")
    if [[ "$LEAF" != "$PINNED" ]]; then
      echo "⚠ 서명 인증서 leaf 불일치: 현재 $LEAF ≠ 고정 $PINNED ($LEAF_PIN)"
      echo "  인증서를 교체했다면 이 빌드로 올리는 사용자는 Keychain 을 1회 재승인해야 한다."
      read -r -p "  의도한 교체면 $LEAF_PIN 을 갱신하고 계속하세요. 지금 계속? [y/N] " a
      [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 서명 신원을 확인하세요."; exit 1; }
    fi
  else
    echo "  · leaf 고정 파일이 없습니다. 한 번 고정해 두면 인증서 교체를 자동으로 잡습니다:"
    echo "      echo $LEAF > $LEAF_PIN && git add $LEAF_PIN"
  fi
  echo "  ✓ '$SIGN_IDENTITY' leaf=$LEAF"
  # 공증 자격은 빌드 전에 확인한다 — 몇 분짜리 빌드 뒤에 "프로필 없음"으로 죽지 않게.
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "✗ 공증 자격 프로필 '$NOTARY_PROFILE' 을 쓸 수 없습니다. 한 번 저장하세요:"
    echo "    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <TEAMID>"
    echo "  (암호는 appleid.apple.com 에서 만든 앱 암호)"
    exit 1; }
  echo "  ✓ 공증 프로필 '$NOTARY_PROFILE'"
  export CODESIGN_IDENTITY PTB_REQUIRE_STABLE_SIGN=1   # build-app.sh 방어선: ad-hoc 폴백 차단

  RECOVER="복구: git checkout scripts/build-app.sh"
  echo "▶ 4/9 버전 $CUR_VERSION → $VERSION (아직 미커밋)"
  perl -pi -e "s/^VERSION=\"[^\"]*\"/VERSION=\"$VERSION\"/" scripts/build-app.sh

  echo "▶ 5/9 빌드 + 서명 (설치하지 않음)"
  PTB_SKIP_INSTALL=1 ./scripts/build-app.sh >/dev/null || { echo "✗ 빌드 실패 ($RECOVER)"; exit 1; }
  BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
  [[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT ($RECOVER)"; exit 1; }
  codesign --verify --strict --deep "$APP" || { echo "✗ 서명 검증 실패 ($RECOVER)"; exit 1; }
  codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' || {
    echo "✗ hardened runtime 이 꺼져 있습니다 — 공증이 거부됩니다 ($RECOVER)"; exit 1; }
  echo "  ✓ $APP ($BUILT, hardened runtime)"

  echo "▶ 6/9 앱 공증 + staple (수 분 걸릴 수 있음)"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP" || { echo "  ($RECOVER)"; exit 1; }
  xcrun stapler staple "$APP" >/dev/null || { echo "✗ 앱 staple 실패 ($RECOVER)"; exit 1; }
  # staple 된 앱으로 zip 을 다시 만든다 — 오프라인에서도 Gatekeeper 가 공증을 확인할 수 있게.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -t exec -vv "$APP" 2>&1 | grep -q 'source=Notarized Developer ID' || {
    echo "✗ Gatekeeper 가 앱을 공증된 Developer ID 로 인정하지 않습니다 ($RECOVER)"; exit 1; }
  echo "  ✓ Gatekeeper: Notarized Developer ID"

  echo "▶ 7/9 DMG 생성 + 서명 + 공증 + staple"
  STAGE=$(mktemp -d)
  ditto "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null || {
    rm -rf "$STAGE"; echo "✗ DMG 생성 실패 ($RECOVER)"; exit 1; }
  rm -rf "$STAGE"
  codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG" || { echo "✗ DMG 서명 실패 ($RECOVER)"; exit 1; }
  notarize "$DMG" || { echo "  ($RECOVER)"; exit 1; }
  xcrun stapler staple "$DMG" >/dev/null || { echo "✗ DMG staple 실패 ($RECOVER)"; exit 1; }
  spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | grep -q 'source=Notarized Developer ID' || {
    echo "✗ Gatekeeper 가 DMG 를 공증된 Developer ID 로 인정하지 않습니다 ($RECOVER)"; exit 1; }
  echo "  ✓ $DMG (Notarized Developer ID)"

  echo "▶ 8/9 커밋 + 태그 + push"
  if ! git diff --quiet -- scripts/build-app.sh; then
    git add scripts/build-app.sh
    git commit -q -m "release: PokeTokenBar Extended $VERSION"
  fi
  git tag -a "$TAG" -m "PokeTokenBar Extended $VERSION"
  git push -q origin "$RELEASE_BRANCH" "$TAG"

  echo "▶ 9/9 GitHub Release $TAG ($REPO)"
  # 설치 안내는 **항상** 앞에 붙인다 — 사람이 기억하는 대신 스크립트가 매번 넣게 한다.
  NOTES=$(mktemp)
  cat > "$NOTES" <<NOTE
### Install

1. Download **$APP_NAME.dmg** below.
2. Open it and drag \`$APP_NAME.app\` onto the **Applications** shortcut. Keep it in
   \`/Applications\` — launch at login and automatic restart after a crash point there.
3. Open it from Applications. It's a menu-bar app, so look for its icon in the menu bar.

Signed with a Developer ID certificate and **notarized by Apple** — it opens without
Gatekeeper warnings. \`$APP_NAME.zip\` contains the same app for scripted installs.

To update, replace the app in \`/Applications\` with the new one. Your data in
\`~/Library/Application Support/PokeTokenBarExtended/\` is kept.

### About this app

PokeTokenBar Extended is [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) with
[Mobius](https://github.com/chussum/mobius) Claude/Codex account switching built in. It is a
separate app from upstream PokeTokenBar (its own bundle id) and is versioned independently,
starting at 1.0.0. The in-app update banner tracks this repository's releases.

NOTE
  if [[ -n "${PTB_NOTES_FILE:-}" && -f "${PTB_NOTES_FILE}" ]]; then
    printf '### Changes\n\n' >> "$NOTES"
    cat "$PTB_NOTES_FILE" >> "$NOTES"
  fi
  gh release create "$TAG" "$DMG" "$ZIP" --repo "$REPO" \
    --title "PokeTokenBar Extended $VERSION" --target "$RELEASE_BRANCH" \
    --verify-tag --notes-file "$NOTES" || {
      rm -f "$NOTES"
      echo "✗ 릴리스 생성 실패 — 커밋과 태그는 이미 push 됐습니다."
      echo "  재시도: gh release create $TAG $DMG $ZIP --repo $REPO --verify-tag --notes-file <notes>"
      exit 1; }
  rm -f "$NOTES"

  echo "✓ $VERSION 배포 완료: https://github.com/$REPO/releases/tag/$TAG"
  echo "  최신 DMG: https://github.com/$REPO/releases/latest/download/$APP_NAME.dmg"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 상류 릴리스 경로 (chattymin/PokeTokenBar)
# ──────────────────────────────────────────────────────────────────────────────
VERSION="${1:?사용: release.sh <version>  (예: 2.1.1)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ 버전 형식 오류: $VERSION"; exit 1; }
PREV=$(grep -oE 'VERSION="[0-9.]+"' scripts/build-app.sh | grep -oE '[0-9.]+')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "✗ main 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push 대상 일치 보장"; exit 1; }
[[ -n "$REPO" ]] || { echo "✗ origin 에서 owner/repo 를 못 읽었습니다 — PTB_RELEASE_REPO 로 지정하세요."; exit 1; }
echo "=== PokeTokenBar 릴리스 $PREV → $VERSION ($REPO) ==="

echo "▶ 1/8 릴리스 전 테스트 게이트"
./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
echo "  ✓ 통과"

doc_rc=0; doc_check || doc_rc=$?
if [[ $doc_rc -eq 2 ]]; then
  echo "중단 — 새 기능에 필요한 에셋을 먼저 만드세요(프롬프트로 넘길 수 없는 게이트)."
  exit 1
elif [[ $doc_rc -ne 0 ]]; then
  read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
fi

echo "▶ 코드서명 신원 게이트 (배포 전 — ad-hoc 릴리스 차단으로 사용자 Keychain '항상 허용' 유지)"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-PokeTokenBar Local}"
EXPECTED_LEAF="507F814330C727B38AC9A987ECBA929721C52C62"
LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" 'index($0, id) {print $2; exit}')
if [[ -z "$LEAF" ]]; then
  echo "✗ 유효 codesigning identity '$SIGN_IDENTITY' 없음(미설치·만료 포함)."
  echo "  이대로면 build-app.sh 가 ad-hoc 서명 → 이 릴리스로 올린 사용자 전원이 Keychain 을 재승인해야 한다."
  echo "  복구: ./scripts/create-signing-cert.sh 실행 → 새 leaf 로 이 스크립트의 EXPECTED_LEAF 갱신 → 재실행."
  exit 1
fi
if [[ "$LEAF" != "$EXPECTED_LEAF" ]]; then
  echo "⚠ 서명 인증서 leaf 불일치: 현재 $LEAF ≠ 고정 $EXPECTED_LEAF"
  echo "  인증서를 재생성/교체했다면, 이 릴리스로 업그레이드하는 기존 사용자 전원이 Keychain 을 1회 재승인해야 한다."
  read -r -p "  의도한 변경이면 EXPECTED_LEAF 를 갱신하고 계속하세요. 지금 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 서명 신원을 확인하세요."; exit 1; }
fi
echo "  ✓ '$SIGN_IDENTITY' leaf=$LEAF — 안정적 서명으로 배포(사용자 재프롬프트 없음)"
export PTB_REQUIRE_STABLE_SIGN=1   # build-app.sh 방어선: ad-hoc 폴백으로 새면 즉시 실패

echo "▶ 3/8 VERSION 범프 $PREV → $VERSION (아직 미커밋)"
perl -pi -e "s/VERSION=\"[0-9.]+\"/VERSION=\"$VERSION\"/" scripts/build-app.sh

echo "▶ 4/8 빌드 + zip (push 전 검증 — 실패해도 범프 미커밋이라 origin/main 무손상)"
./scripts/build-app.sh >/dev/null
rm -f build/$APP_NAME.zip
ditto -c -k --keepParent build/$APP_NAME.app build/$APP_NAME.zip
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/$APP_NAME.app/Contents/Info.plist)
[[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (수동 복구: git checkout scripts/build-app.sh)"; exit 1; }

echo "▶ 5/8 커밋 + push (빌드 성공 후)"
git add scripts/build-app.sh
git commit -q -m "release: bump version to $VERSION"
git push -q origin main

echo "▶ 6/8 GitHub Release v$VERSION"
NOTES_FILE="${PTB_NOTES_FILE:-}"
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  gh release create "v$VERSION" build/$APP_NAME.zip --repo "$REPO" \
    --title "PokeTokenBar v$VERSION" --target main --notes-file "$NOTES_FILE"
else
  gh release create "v$VERSION" build/$APP_NAME.zip --repo "$REPO" \
    --title "PokeTokenBar v$VERSION" --target main --notes "Release v$VERSION"
fi

echo "▶ 7/8 Homebrew cask $VERSION"
if [[ -z "$TAP_REPO" ]]; then
  echo "  · tap 이 설정되지 않아 건너뜁니다 (PTB_TAP_REPO 로 지정 가능)."
else
  TMP_CASK=$(mktemp)
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.content' | base64 -d \
    | perl -pe "s/version \"[0-9.]+\"/version \"$VERSION\"/" > "$TMP_CASK"
  SHA=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha')
  gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
    -f message="cask: poke-token-bar $VERSION" \
    -f content="$(base64 -i "$TMP_CASK")" -f sha="$SHA" --jq '.commit.html_url'
  rm -f "$TMP_CASK"
fi

echo "▶ 8/8 GitHub Pages 재빌드(랜딩 동적 배지 갱신 유도)"
gh api -X POST "repos/$REPO/pages/builds" >/dev/null 2>&1 || true

echo "✓ v$VERSION 배포 완료. 검증: brew upgrade --cask poke-token-bar"
