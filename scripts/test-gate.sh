#!/usr/bin/env bash
#
# test-gate.sh — 안정성 가드레일. 커밋/머지 전 수동 실행 (1인 로컬, CI 없음).
#
#   1) swift test 전체 통과
#   2) "로직 코어" 파일 집합의 라인 커버리지 >= THRESHOLD
#
# 로직 코어 = 결정적으로 단위 테스트 가능한 파일만 포함. ProcessRunner / PokeAPIClient /
# CcusageProvider / CodexRateLimitsProvider / OAuthLimitsProvider / UpdateChecker /
# BinaryLocator, 그리고 Mobius 쪽의 KeychainClient / UsageFetcher / TokenRefresher /
# LoginFlow / AccountsState 는 실제 서브프로세스·네트워크·Keychain·UI 수명주기 의존이라
# 단위 커버리지 대상에서 제외 (해당 부분은 파서/순수 헬퍼만 별도로 테스트됨).
# 배열 안 각 구역의 주석이 무엇을 왜 뺐는지 적어 둔다 — 새 파일을 더할 때 그 기준을 따른다.
#
# ★ 이 숫자는 증거가 아니다 — line coverage 라 `if x { y }` 한 줄은 조건만 평가돼도 실행으로
#   센다. 새 조건 분기를 넣었으면 CLAUDE.md §결함 대응 3 대로 `llvm-cov show … --show-regions`
#   로 `^0` 을 직접 봐라.
#
# 사용:  ./scripts/test-gate.sh          # 게이트 실행
#        THRESHOLD=75 ./scripts/test-gate.sh   # 임계값 임시 상향
#
set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${THRESHOLD:-75}"

# 결정적으로 단위 테스트 가능한 파일만 담는다 — 서브프로세스(`Process`)·네트워크(`URLSession`)·
# Keychain(`Security`) 경계를 **직접** 여는 파일은 제외한다(그 경계 너머는 이 스위트가 재현할 수
# 없어 커버리지가 "테스트가 없다"가 아니라 "테스트할 수 없다"를 뜻하게 된다). 의존을 주입으로
# 받는 파일(예: `AccountStore` 의 `KeychainClient`, `CodexUsageProber` 의 `fetch`)은 결정적이므로
# 포함한다.
LOGIC_CORE=(
  # PokeTokenBarExtended 로직 코어
  "Sources/PokeTokenBarExtended/Core/CompanionModel.swift"
  "Sources/PokeTokenBarExtended/Core/CompanionStore.swift"
  "Sources/PokeTokenBarExtended/Core/PokemonProfile.swift"
  "Sources/PokeTokenBarExtended/Core/PokemonNameLocalization.swift"
  "Sources/PokeTokenBarExtended/Core/LocalizationErrors.swift"
  "Sources/PokeTokenBarExtended/Core/UsageStore.swift"
  "Sources/PokeTokenBarExtended/Core/Models.swift"
  "Sources/PokeTokenBarExtended/Core/UsageCost.swift"
  "Sources/PokeTokenBarExtended/Core/TokenFormatter.swift"
  "Sources/PokeTokenBarExtended/Core/UsageProvider.swift"
  "Sources/PokeTokenBarExtended/Core/LocalUsageReader.swift"
  "Sources/PokeTokenBarExtended/Core/LocalUsageCache.swift"
  "Sources/PokeTokenBarExtended/Core/ModelPricing.swift"
  "Sources/PokeTokenBarExtended/Core/CustomScanRoots.swift"
  "Sources/PokeTokenBarExtended/Core/StateDirectoryMigration.swift"
  "Sources/PokeTokenBarExtended/Core/LegacyDefaultsDomainMigration.swift"

  # Mobius 계정 전환 엔진 (Sources/MobiusCore)
  # 제외: KeychainClient(Security + `security` 서브프로세스),
  #       UsageFetcher / TokenRefresher / CodexUsageFetcher / CodexTokenRefresher / UpdateChecker
  #       (URLSession 을 직접 만드는 네트워크 경계),
  #       Notifications(알림 이름 상수뿐 — 로직 0), CodexAuthBlob 은 포함(순수 JWT 파싱).
  "Sources/MobiusCore/AccountStore.swift"
  "Sources/MobiusCore/AuthSuspicion.swift"
  "Sources/MobiusCore/AutoSwitchEngine.swift"
  "Sources/MobiusCore/ClaudeConfigIO.swift"
  "Sources/MobiusCore/CodexAuthBlob.swift"
  "Sources/MobiusCore/CodexConfigIO.swift"
  "Sources/MobiusCore/CodexRateLimitParser.swift"
  "Sources/MobiusCore/CodexStatusRouter.swift"
  "Sources/MobiusCore/CodexUsageProber.swift"
  "Sources/MobiusCore/DesktopSwitcher.swift"
  "Sources/MobiusCore/FallbackAuthChecker.swift"
  "Sources/MobiusCore/HitAttribution.swift"
  "Sources/MobiusCore/MobiusEnvironment.swift"
  "Sources/MobiusCore/Models.swift"
  "Sources/MobiusCore/ProviderConfigIO.swift"
  "Sources/MobiusCore/RateLimitParser.swift"
  "Sources/MobiusCore/ReauthClearance.swift"
  "Sources/MobiusCore/SessionLogWatcher.swift"
  "Sources/MobiusCore/Switcher.swift"
  "Sources/MobiusCore/SyncEngine.swift"
  "Sources/MobiusCore/UsagePollBreaker.swift"

  # Mobius 호스트 계층 (Sources/PokeTokenBarExtended/Mobius)
  # 제외: AccountsState(@MainActor 오케스트레이션 — 타이머·알림·NSWorkspace. 결정 로직은
  #       MobiusCore 순수 함수로 내려가 있고 나머지는 수동 QA 영역),
  #       LoginFlow / DesktopCoordinator / ClaudeCLI / ToolInventory(서브프로세스·PATH·
  #       설치된 앱 탐색 — 개발 머신 상태에 따라 결과가 달라진다),
  #       MobiusFeature / MobiusPaths(UserDefaults 읽기와 경로 결합 한 줄 — 로직 0).
  "Sources/PokeTokenBarExtended/Mobius/MobiusCoexistence.swift"
  "Sources/PokeTokenBarExtended/Mobius/MobiusDataMigration.swift"
  "Sources/PokeTokenBarExtended/Mobius/MobiusLaunchSequence.swift"
  "Sources/PokeTokenBarExtended/Mobius/MobiusSwitchSideEffects.swift"
)

echo "▶ swift test (--enable-code-coverage)"
swift test --enable-code-coverage

PROF=$(find .build -name 'default.profdata' | head -1)
# dSYM 안에도 같은 이름의 DWARF 바이너리가 있어 head -1 이 그걸 집으면 llvm-cov 가 실패한다 → 제외.
BIN=$(find .build -name 'PokeTokenBarExtendedPackageTests' -type f ! -path '*.dSYM/*' | head -1)
if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "✗ 커버리지 산출물(profdata/binary)을 찾지 못했습니다." >&2
  exit 1
fi

# Coverage profile format is tied to the Swift/LLVM toolchain that produced it. Homebrew Swift 6.x
# profiles are newer than the llvm-cov bundled with older Xcode, so prefer the sibling llvm-cov.
SWIFT_TOOL_DIR=$(dirname "$(realpath "$(command -v swift)")")
if [[ -x "$SWIFT_TOOL_DIR/llvm-cov" ]]; then
  LLVM_COV="$SWIFT_TOOL_DIR/llvm-cov"
else
  LLVM_COV=$(xcrun --find llvm-cov)
fi

echo
echo "▶ 로직 코어 커버리지 (임계값 ${THRESHOLD}%)"
REPORT=$("$LLVM_COV" report "$BIN" -instr-profile="$PROF" "${LOGIC_CORE[@]}" 2>/dev/null)
echo "$REPORT"

# TOTAL 행의 라인 커버리지(%) 추출 — 컬럼: ... Lines MissedLines Cover(=$10)
COVER=$(echo "$REPORT" | awk '/^TOTAL/ { gsub("%","",$10); print $10 }')
if [[ -z "$COVER" ]]; then
  echo "✗ 커버리지 수치 파싱 실패." >&2
  exit 1
fi

echo
# 소수 비교는 awk 로 (bash 정수 비교 회피)
if awk "BEGIN { exit !($COVER >= $THRESHOLD) }"; then
  echo "✓ 게이트 통과 — 로직 코어 라인 커버리지 ${COVER}% >= ${THRESHOLD}%"
else
  echo "✗ 게이트 실패 — 로직 코어 라인 커버리지 ${COVER}% < ${THRESHOLD}%" >&2
  echo "  테스트를 보강하거나, 의도된 하락이면 THRESHOLD 를 조정하세요." >&2
  exit 1
fi
