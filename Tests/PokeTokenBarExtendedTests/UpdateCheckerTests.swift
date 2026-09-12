import XCTest
@testable import PokeTokenBarExtended

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    // MARK: - Detached upgrade script wait loop (#175)

    // MARK: 포크 버전 표기 (`2.5.3+mobius.1`)

    /// 이 포크의 표시 버전은 semver 빌드 메타데이터를 단다. 비교기가 그걸 그대로 `.` 으로
    /// 쪼개면 `"3+mobius"` → 0 이라 `[2, 5, 0, 1]` 이 되고, **이미 나와 있는 상류 2.5.3 이
    /// 자기보다 최신으로 보여** 업데이트 배너가 상시로 뜬다. 그 정확한 조건을 잠근다.
    func testForkBuildIsNotOlderThanTheUpstreamReleaseItWasForkedFrom() {
        XCTAssertFalse(UpdateChecker.isNewer("2.5.3", than: "2.5.3+mobius.1"))
    }

    /// 표기를 바꾼 뒤에도 **상류 릴리스 알림은 계속 받는다**(사용자 결정). 위 테스트만 있으면
    /// "비교를 아예 죽여서" 통과시키는 구현도 초록불이라, 반대 방향을 함께 못 박는다.
    func testForkBuildStillSeesANewerUpstreamRelease() {
        XCTAssertTrue(UpdateChecker.isNewer("2.5.4", than: "2.5.3+mobius.1"))
        XCTAssertTrue(UpdateChecker.isNewer("2.6.0", than: "2.5.3+mobius.1"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.5.3+mobius.1"))
    }

    /// 포크 빌드 번호가 올라가도 판정은 상류 기준점(`+` 앞)만 본다 — 빌드 번호를 올렸다고
    /// 상류 릴리스가 가려지면 알림을 계속 받겠다는 결정이 조용히 깨진다.
    func testForkBuildNumberDoesNotAffectUpstreamComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("2.5.4", than: "2.5.3+mobius.9"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.3", than: "2.5.3+mobius.9"))
    }

    /// 프리릴리스 접미사도 같은 규칙으로 잘린다(semver §9 — 우선순위에서 제외).
    func testPreReleaseSuffixIsStrippedBeforeComparing() {
        XCTAssertFalse(UpdateChecker.isNewer("2.5.3-rc1", than: "2.5.3"))
        XCTAssertTrue(UpdateChecker.isNewer("2.5.4-rc1", than: "2.5.3+mobius.1"))
    }

    /// 상류 cask 업그레이드는 확인창 없이 앱을 종료하고 번들을 상류 빌드로 교체한다(같은 번들
    /// ID·같은 설치 경로) → 포크의 계정 전환 기능이 조용히 사라진다. 지금은 사용자가 cask 를
    /// 지워 경로가 죽어 있지만 재설치 한 번이면 되살아나므로, 코드에서 닫혀 있는지를 잠근다.
    func testForkNeverTakesTheBrewCaskUpgradePath() {
        XCTAssertFalse(
            UpdateChecker.allowsBrewCaskUpgrade,
            "a cask upgrade replaces this fork with the upstream build without confirmation"
        )
    }

    func testDetachedUpgradeScriptWaitsOnPidNotProcessName() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertFalse(
            script.contains("pgrep -x"),
            "pgrep -x matches any instance by name and always times out when a duplicate runs"
        )
        XCTAssertTrue(
            script.contains("kill -0 \"$3\""),
            "the wait loop must wait on the specific terminating PID via $3"
        )
    }

    func testDetachedUpgradeScriptUsesPositionalParameters() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("\"$1\" update"), "must execute brew via $1 positional arg")
        XCTAssertTrue(script.contains("\"$1\" upgrade"), "must execute brew upgrade via $1 positional arg")
        XCTAssertTrue(script.contains("open \"$2\""), "must open bundlePath via $2 positional arg")
    }
}
