import XCTest
@testable import PokeTokenBar

/// 계정 전환 엔진이 만드는 타이머의 idle 배터리 규율.
///
/// 이 앱의 하우스 규칙은 **자기가 만드는 모든 타이머가 wakeup 을 코얼레싱한다** 이고, 그 근거는
/// `docs/reference/defect-log.md` '에너지' 절에 쌓여 있다(`UsageStore.reschedule`,
/// `AppDelegate.menuFrameTolerance`). 이식된 Mobius 타이머 둘만 tolerance 없이 들어와 있었다.
///
/// 규율은 `FloatingPetEnergyTests` 와 같은 모양으로 잠근다 — **"캡이 존재한다(>0)"** 이 본질이고
/// (0 이면 코얼레싱이 통째로 사라진다), 동시에 **상한**도 본다: tolerance 는 늦게만 발화시키므로
/// 값이 곧 최악 지연이고, 자동 전환에서 그 지연은 사용자가 막힌 CLI 앞에 앉아 있는 시간이다.
@MainActor
final class MobiusTimerEnergyTests: XCTestCase {

    /// 최악 지연 상한(배수). 메뉴바 재생 지연 가드(`testToleranceDoesNotVisiblyStretchPlayback`)
    /// 와 같은 값 — 축이 재생 속도에서 전환 지연으로 바뀌었을 뿐 "코얼레싱은 하되 눈에 띄게
    /// 늘어지지는 않는다"는 계약은 같다.
    private let worstCaseStretch = 0.15

    private func startedState() throws -> AccountsState {
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { false })
        state.start()
        return state
    }

    func testTheEngineTickCoalescesItsWakeups() throws {
        let timer = try XCTUnwrap(startedState().tickTimerForTesting)
        XCTAssertGreaterThan(timer.tolerance, 0,
                             "tolerance 0 이면 이 타이머만 유휴 wakeup 을 혼자 낸다")
        XCTAssertLessThanOrEqual(timer.tolerance, AccountsState.tickInterval * worstCaseStretch,
                                 "tolerance 는 늦게만 발화시킨다 — 키우면 그만큼 전환이 늦어진다")
    }

    func testTheExternalAppSafetyNetCoalescesItsWakeups() throws {
        let timer = try XCTUnwrap(startedState().externalAppWatchTimerForTesting)
        XCTAssertGreaterThan(timer.tolerance, 0)
        XCTAssertLessThanOrEqual(
            timer.tolerance, AccountsState.externalAppWatchInterval * worstCaseStretch)
    }

    /// 값이 아니라 **주기** 쪽 드리프트 가드 — 타이머를 리터럴로 다시 만들면 위 두 단언의
    /// 기준(이름 있는 상수)과 실제 타이머가 조용히 갈라진다.
    func testTheTimersRunAtTheirNamedIntervals() throws {
        let state = try startedState()
        XCTAssertEqual(try XCTUnwrap(state.tickTimerForTesting).timeInterval,
                       AccountsState.tickInterval, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.externalAppWatchTimerForTesting).timeInterval,
                       AccountsState.externalAppWatchInterval, accuracy: 0.001)
    }
}
