#!/bin/bash
# PokeTokenBar.app 번들 조립 + /Applications 설치
set -euo pipefail
cd "$(dirname "$0")/.."

# ── 버전 (이 저장소의 유일한 정의 지점) ──────────────────────────────────────
# 이 포크는 상류(chattymin/PokeTokenBar) 위에 mobius 계정 전환을 얹은 것이라, 표시 버전이
# 상류 기준점과 포크 빌드 번호를 함께 담는다. 상류를 rebase 해 기준점이 올라가면
# UPSTREAM_VERSION 을 그 버전으로 올리고 FORK_BUILD 를 1 로 되돌린다.
#
# CFBundleShortVersionString — 표시(설정창 푸터)·업데이트 비교용. semver 빌드 메타데이터
#   (`+mobius.N`)를 쓴다: 배너가 "🆕 v2.5.4 available (you have 2.5.3+mobius.1)" 로 나와
#   지금 돌고 있는 게 포크라는 사실이 결정 시점에 그대로 보인다. `UpdateChecker.isNewer` 는
#   `+` 앞의 숫자 세그먼트만 비교하므로 상류 2.5.4 는 여전히 새 버전으로 잡힌다(회귀 테스트
#   `UpdateCheckerTests.testFork*` 가 고정). Apple 규격은 "마침표로 구분된 정수"를 기대하지만
#   실측(2026-09-12) plutil·codesign --verify --strict·`defaults read`·`PlistBuddy`·
#   `Bundle.main.object(forInfoDictionaryKey:)` 전부 이 문자열을 그대로 통과시킨다. 규격을
#   집행하는 곳은 App Store 심사이고 이 포크는 거기로 안 간다.
#   곁가지: `CodexRateLimitsProvider` 가 이 값을 Codex MCP 핸드셰이크의 `clientInfo.version`
#   으로 보낸다 — `2.5.3+mobius.1` 은 **유효한 semver**(빌드 메타데이터)이고, 대안이던
#   `2.5.3.1` 은 semver 가 아니다. 상대가 검증한다면 `+` 쪽이 오히려 안전한 표기다.
# CFBundleVersion — LaunchServices 가 같은 번들 ID 의 중복 사본 중 무엇을 띄울지 고를 때
#   비교하는 키다. 여기는 숫자만 유지하고, 네 번째 세그먼트를 포크 빌드 번호로 둬 상류
#   2.5.3 보다 항상 위에 놓이게 한다.
UPSTREAM_VERSION="2.5.3"
FORK_BUILD="1"
VERSION="$UPSTREAM_VERSION+mobius.$FORK_BUILD"
BUNDLE_VERSION="$UPSTREAM_VERSION.$FORK_BUILD"
APP_NAME="PokeTokenBar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# 심볼 strip — 릴리스 바이너리 1.84MB → 0.80MB(-57%). codesign 전에 수행(서명 무효화 방지).
strip -rSTx "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || strip -rSx "$APP/Contents/MacOS/$APP_NAME"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.chattymin.poketokenbar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUNDLE_VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 크래시/OOM(exit≠0) 시 자동 재실행 LaunchAgent(KeepAlive) — SMAppService.agent 가 등록해 launchd 가
# 워치독으로 동작. 정상 종료(exit 0: 사용자 종료·업데이트)엔 재실행 안 함(SuccessfulExit=false).
# ProgramArguments 는 brew 설치 경로(/Applications) 고정. codesign 전에 생성해 서명 seal 에 포함.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.login.plist" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>io.github.chattymin.poketokenbar.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
AGENT

echo "==> codesign"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-PokeTokenBar Local}"
# 안정적 Keychain ACL 을 위해서는 인증서 존재가 아니라 유효한 codesigning identity 가 필요하다.
if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    # 안정적 자체 서명 신원 → 재빌드해도 Keychain "항상 허용" 유지
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    # 인증서 없음 → ad-hoc (빌드마다 cdhash 변경 = Keychain 재프롬프트 가능)
    if [[ "${PTB_REQUIRE_STABLE_SIGN:-0}" == "1" ]]; then
        # 릴리스 경로(release.sh 가 세팅). ad-hoc 릴리스는 사용자 Keychain 승인을 깨므로 절대 금지.
        echo "   ✗ PTB_REQUIRE_STABLE_SIGN=1 인데 '$SIGN_IDENTITY' 유효 identity 없음 → ad-hoc 금지, 중단." >&2
        echo "     ./scripts/create-signing-cert.sh 실행 후 다시 시도하세요." >&2
        exit 1
    fi
    echo "   ('$SIGN_IDENTITY' 유효 codesigning identity 없음 → ad-hoc 서명 — 로컬 개발용)"
    echo "   반복 Keychain 허용 프롬프트를 줄이려면 ./scripts/create-signing-cert.sh 실행 후 다시 빌드하세요."
    codesign --force -s - "$APP"
fi

echo "==> 기존 인스턴스 종료 + /Applications 설치"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" /Applications/

echo "완료: open /Applications/$APP_NAME.app"
