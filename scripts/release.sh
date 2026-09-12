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
    ui_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/PokeTokenBar/UI/' 2>/dev/null)
    shot_changed=$(git diff --name-only "$last_tag"..HEAD -- 'assets/settings*' 'assets/screenshot*' 'assets/menubar*' 'assets/shiny*' 2>/dev/null)
    if [[ -n "$ui_changed" && -z "$shot_changed" ]]; then
      echo "  ⚠ UI 소스가 $last_tag 이후 변경됐으나 스크린샷(assets/) 갱신 없음 — README 이미지 stale 가능:"
      echo "$ui_changed" | sed 's/^/       /'
      echo "     → 변경된 화면이면 assets 스크린샷 재생성 (README.md/ko/ja 각 언어)."
      warn=1
    fi

    local ui_feats new_assets
    ui_feats=$(git log "$last_tag"..HEAD --format='%s' -- 'Sources/PokeTokenBar/UI/' 2>/dev/null \
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

# 포크(mobius) 전용 문서 검토. 상류 doc_check 를 그대로 쓰면 안 되는 이유:
# README*·assets·랜딩·cask 는 **상류 표면**이고 이 포크는 그것들을 유지하지 않는다
# (docs/reference/mobius-integration.md §상류 rebase: "README*.md 는 상류 파일이라 건드리지
# 않는다"). 특히 `feat:` 하드 게이트는 포크 커밋 대부분이 UI 를 건드리므로 모든 포크
# 릴리스를 막아 버린다. 포크의 문서 표면은 mobius-integration.md 하나다.
fork_doc_check() {
  local warn=0 last_tag src_changed doc_changed
  echo "▶ 문서 일관성 검토 (포크)"
  last_tag=$(git describe --tags --match 'v*+mobius.*' --abbrev=0 2>/dev/null || echo "")
  if [[ -n "$last_tag" ]]; then
    src_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/' 2>/dev/null)
    doc_changed=$(git diff --name-only "$last_tag"..HEAD -- 'docs/reference/mobius-integration.md' 2>/dev/null)
    if [[ -n "$src_changed" && -z "$doc_changed" ]]; then
      echo "  ⚠ $last_tag 이후 Sources/ 가 바뀌었는데 docs/reference/mobius-integration.md 는 그대로입니다."
      echo "     → 동작·경로·불변식이 바뀌었으면 그 문서를 먼저 갱신하세요(포크의 유일한 문서 표면)."
      warn=1
    fi
  else
    echo "  · 이전 포크 태그 없음 — 첫 포크 릴리스로 간주."
  fi
  cat <<'CHECK'
  ─ 수동 체크리스트 (포크) ──────────────────────────────────────────
   [ ] docs/reference/mobius-integration.md : 버전 표기·빌드/설치·운영 주의사항
   [ ] 상류 표면(README*/assets/랜딩/cask)은 **갱신 대상이 아니다** — 상류 파일이다
   [ ] 인앱 업데이트 배너는 상류 릴리스만 본다 → 이 릴리스는 배너로 전달되지 않는다
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

IS_FORK=0
grep -q '^FORK_BUILD=' scripts/build-app.sh && IS_FORK=1

if [[ "${1:-}" == "--check-only" ]]; then
  if [[ $IS_FORK -eq 1 ]]; then fork_doc_check || true; else doc_check || true; fi
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 포크(mobius) 릴리스 경로
# ──────────────────────────────────────────────────────────────────────────────
if [[ $IS_FORK -eq 1 ]]; then
  FORK_BRANCH="${PTB_RELEASE_BRANCH:-mobius-integration}"

  usage_fork() {
    cat <<'USAGE' >&2
사용 (포크):
  ./scripts/release.sh                     # FORK_BUILD 만 +1 (평소 포크 릴리스)
  ./scripts/release.sh --upstream 2.5.4    # 상류 rebase 후: UPSTREAM_VERSION 갱신 + FORK_BUILD=1

  PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh   # 릴리스 노트 본문(설치 안내는 자동 첨부)
USAGE
    exit 1
  }

  NEW_UPSTREAM=""
  case "${1:-}" in
    "")           : ;;
    --upstream)   NEW_UPSTREAM="${2:?--upstream 뒤에 상류 버전(예: 2.5.4)}" ;;
    -h|--help)    usage_fork ;;
    *)            echo "✗ 알 수 없는 인자: $1" >&2; usage_fork ;;
  esac

  CUR_UPSTREAM=$(sed -n 's/^UPSTREAM_VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)
  CUR_FORK=$(sed -n 's/^FORK_BUILD="\(.*\)"$/\1/p' scripts/build-app.sh)
  [[ -n "$CUR_UPSTREAM" && -n "$CUR_FORK" ]] || {
    echo "✗ build-app.sh 에서 UPSTREAM_VERSION/FORK_BUILD 를 읽지 못했습니다 (표기 규칙이 바뀌었나?)"; exit 1; }

  if [[ -n "$NEW_UPSTREAM" ]]; then
    [[ "$NEW_UPSTREAM" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ 상류 버전 형식 오류: $NEW_UPSTREAM"; exit 1; }
    TO_UPSTREAM="$NEW_UPSTREAM"; TO_FORK="1"
  else
    [[ "$CUR_FORK" =~ ^[0-9]+$ ]] || { echo "✗ FORK_BUILD 가 정수가 아닙니다: $CUR_FORK"; exit 1; }
    TO_UPSTREAM="$CUR_UPSTREAM"; TO_FORK="$((CUR_FORK + 1))"
  fi
  PREV_VERSION="$CUR_UPSTREAM+mobius.$CUR_FORK"
  VERSION="$TO_UPSTREAM+mobius.$TO_FORK"
  TAG="v$VERSION"

  [[ -n "$REPO" ]] || { echo "✗ origin 에서 owner/repo 를 못 읽었습니다 — PTB_RELEASE_REPO 로 지정하세요."; exit 1; }
  [[ "$REPO" != "$UPSTREAM_SLUG" ]] || {
    echo "✗ 포크 빌드인데 배포 대상이 상류($UPSTREAM_SLUG)입니다 — origin 을 확인하세요."; exit 1; }

  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  [[ "$BRANCH" == "$FORK_BRANCH" ]] || {
    echo "✗ $FORK_BRANCH 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push/태그 대상 일치 보장"; exit 1; }

  # 작업트리가 더러우면 중단한다. 상류 경로에 없는 게이트인데 포크에서 필요한 이유:
  # 범프 커밋이 `git add scripts/build-app.sh` 로 좁게 스테이징돼도, 이미 스테이징된
  # 남의 변경이 있으면 그대로 릴리스 커밋에 딸려 들어간다.
  [[ -z "$(git status --porcelain)" ]] || {
    echo "✗ 작업트리가 깨끗하지 않습니다 — 릴리스 커밋에 관계없는 변경이 딸려 들어갑니다:"
    git status --short | sed 's/^/    /'
    exit 1; }

  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "✗ 태그 $TAG 가 이미 로컬에 있습니다."; exit 1
  fi

  echo "=== PokeTokenBar(mobius 포크) 릴리스 $PREV_VERSION → $VERSION ==="
  echo "    저장소: $REPO   브랜치: $FORK_BRANCH   태그: $TAG"

  echo "▶ 1/7 릴리스 전 테스트 게이트"
  ./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
  echo "  ✓ 통과"

  echo "▶ 2/7 문서 검토"
  doc_rc=0; fork_doc_check || doc_rc=$?
  if [[ $doc_rc -ne 0 ]]; then
    read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
    [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
  fi

  echo "▶ 3/7 코드서명 신원 게이트"
  # ad-hoc 서명은 리빌드마다 코드 정체성이 바뀌어 사용자 Keychain '항상 허용'이 매번
  # 리셋된다 — 계정 전환 기능이 Keychain 을 쓰므로 고정 서명이 사실상 필수다.
  SIGN_IDENTITY="${CODESIGN_IDENTITY:?CODESIGN_IDENTITY 를 지정하세요 (예: \"Developer ID Application: … (TEAMID)\")}"
  LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" '$0 ~ id {print $2; exit}')
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
  export PTB_REQUIRE_STABLE_SIGN=1   # build-app.sh 방어선: ad-hoc 폴백으로 새면 즉시 실패

  echo "▶ 4/7 버전 범프 $PREV_VERSION → $VERSION (아직 미커밋)"
  # 두 변수만 고친다 — 파생된 VERSION= 줄을 평평한 리터럴로 덮으면 포크 표기 규칙이 사라진다.
  perl -pi -e "s/^UPSTREAM_VERSION=\"[^\"]*\"/UPSTREAM_VERSION=\"$TO_UPSTREAM\"/" scripts/build-app.sh
  perl -pi -e "s/^FORK_BUILD=\"[^\"]*\"/FORK_BUILD=\"$TO_FORK\"/" scripts/build-app.sh

  echo "▶ 5/7 빌드 + zip (push 전 검증 — 실패해도 범프 미커밋이라 origin 무손상)"
  echo "  ⚠ build-app.sh 는 마지막에 실행 중인 앱을 pkill 하고 /Applications 를 교체합니다."
  ./scripts/build-app.sh >/dev/null || {
    echo "✗ 빌드 실패 (복구: git checkout scripts/build-app.sh)"; exit 1; }
  rm -f build/PokeTokenBar.zip
  ditto -c -k --keepParent build/PokeTokenBar.app build/PokeTokenBar.zip
  BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PokeTokenBar.app/Contents/Info.plist)
  [[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (복구: git checkout scripts/build-app.sh)"; exit 1; }

  echo "▶ 6/7 커밋 + 태그 + push"
  git add scripts/build-app.sh
  git commit -q -m "release: bump fork build to $VERSION"
  git tag -a "$TAG" -m "PokeTokenBar $VERSION (mobius fork)"
  git push -q origin "$FORK_BRANCH" "$TAG"

  echo "▶ 7/7 GitHub Release $TAG ($REPO)"
  # 설치 안내는 **항상** 앞에 붙인다. 이 자산은 Developer ID 서명이지만 공증(notarization)이
  # 없어서 다운로드하면 quarantine 이 붙고 Gatekeeper 가 막는다 — 사람이 기억하는 대신
  # 스크립트가 매번 넣게 한다.
  NOTES=$(mktemp)
  cat > "$NOTES" <<NOTE
### Install

This build is signed with a Developer ID certificate but is **not notarized**. macOS
attaches \`com.apple.quarantine\` to anything you download, and Gatekeeper refuses
unnotarized bundles, so unzip and clear the attribute before installing:

\`\`\`bash
unzip PokeTokenBar.zip
xattr -d com.apple.quarantine PokeTokenBar.app
cp -R PokeTokenBar.app /Applications/
\`\`\`

### About this build

- This is the **mobius fork** (\`$VERSION\`), not upstream PokeTokenBar. It adds
  Claude/Codex account switching on top of upstream \`$TO_UPSTREAM\`.
- It shares its bundle id and install path with upstream, so do **not** keep the
  \`poke-token-bar\` Homebrew cask installed - \`brew upgrade\` would silently replace
  this build with an upstream one.
- The in-app update banner tracks **upstream** releases, so it will never offer this
  release. Take fork updates from this page or by rebuilding from source.

NOTE
  if [[ -n "${PTB_NOTES_FILE:-}" && -f "${PTB_NOTES_FILE}" ]]; then
    printf '### Changes\n\n' >> "$NOTES"
    cat "$PTB_NOTES_FILE" >> "$NOTES"
  fi
  gh release create "$TAG" build/PokeTokenBar.zip --repo "$REPO" \
    --title "PokeTokenBar $VERSION (mobius fork)" --target "$FORK_BRANCH" \
    --verify-tag --notes-file "$NOTES" || {
      rm -f "$NOTES"
      echo "✗ 릴리스 생성 실패 — 커밋과 태그는 이미 push 됐습니다."
      echo "  되돌리기: git push --delete origin $TAG && git tag -d $TAG"
      exit 1; }
  rm -f "$NOTES"

  echo "✓ $VERSION 배포 완료."
  echo "  설치: 릴리스 페이지에서 zip 을 받아 위 quarantine 해제 후 /Applications 로 복사"
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
LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" '$0 ~ id {print $2; exit}')
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
rm -f build/PokeTokenBar.zip
ditto -c -k --keepParent build/PokeTokenBar.app build/PokeTokenBar.zip
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PokeTokenBar.app/Contents/Info.plist)
[[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (수동 복구: git checkout scripts/build-app.sh)"; exit 1; }

echo "▶ 5/8 커밋 + push (빌드 성공 후)"
git add scripts/build-app.sh
git commit -q -m "release: bump version to $VERSION"
git push -q origin main

echo "▶ 6/8 GitHub Release v$VERSION"
NOTES_FILE="${PTB_NOTES_FILE:-}"
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  gh release create "v$VERSION" build/PokeTokenBar.zip --repo "$REPO" \
    --title "PokeTokenBar v$VERSION" --target main --notes-file "$NOTES_FILE"
else
  gh release create "v$VERSION" build/PokeTokenBar.zip --repo "$REPO" \
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
