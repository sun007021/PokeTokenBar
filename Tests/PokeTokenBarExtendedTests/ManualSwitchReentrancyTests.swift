import XCTest
@testable import MobiusCore
@testable import PokeTokenBarExtended

/// `AccountsState.manualSwitch(to:)` 의 재진입 가드.
///
/// **결함**(코드 리뷰, #22): 두 계정을 빠르게 연속 클릭하면 각 클릭이 독립된 `Task` 를 띄우고,
/// 그 사이 자격증명을 스왑하는 데는 아무 직렬화도 없었다 — 나중에 끝난 쪽이 이겨서 사용자가
/// 마지막에 누른 계정과 최종 활성 계정이 달라질 수 있었고 안내도 없었다. `desktopSwitchTask`
/// 가 이미 같은 문제(Desktop 동시 전환)를 필드 하나로 막고 있었는데 `manualSwitch` 만 빠져 있었다.
@MainActor
final class ManualSwitchReentrancyTests: XCTestCase {

    /// 진행 중인 수동 전환이 있는 동안 두 번째 호출은 (a) 조용히 무시되지 않고 배너로 알리며,
    /// (b) 실제 전환을 건드리지 않아야 한다. 그리고 첫 전환이 끝나면 가드가 스스로 풀려야 한다 —
    /// 안 풀리면 "막았다"가 아니라 "전환 기능이 영구히 죽었다"는 더 나쁜 결함이 된다.
    func testSecondManualSwitchIsRejectedWhileFirstIsInFlightAndReleasesAfterward() async throws {
        let fixture = try MobiusCoexistenceGuardTests.SwitchFixture(
            test: self, externalMobiusRunning: { false })
        // fixture 기본값은 work.needsReauth == true(동기 분기). 이 테스트는 정확히 그 "동기
        // 즉시 전환" 분기와 "async 분기(Task 생성)" 분기 사이의 경합을 보려는 것이라, work 는
        // async 분기를 타도록 내리고 별도 계정을 동기 분기 대상으로 둔다.
        try fixture.state.store.update(fixture.work.id) { $0.needsReauth = false }
        let other = try fixture.state.store.upsertProfile(
            nickname: "other",
            snapshot: MobiusCoexistenceGuardTests.SwitchFixture.snapshot(email: "o@x.com", token: "O0"))
        try fixture.state.store.update(other.id) { $0.needsReauth = true }
        fixture.state.reload()
        XCTAssertNil(fixture.state.lastError, "fixture 가 이미 에러를 들고 있으면 아래 단언이 무의미하다")

        // 첫 클릭 — needsReauth == false 인 work 는 preflight(await)를 거치는 async 분기라
        // Task 를 만들고 그 자리에서 반환한다(본문은 아직 안 돈다 — 같은 동기 실행 구간 안).
        fixture.state.manualSwitch(to: fixture.work.id)
        let firstTask = try XCTUnwrap(fixture.state.manualSwitchTaskForTesting, """
            async 분기는 Task 생성 시점에 핸들을 동기적으로 필드에 남긴다 — nil 이면 이 테스트가
            노리는 경합 창 자체가 없다는 뜻이라 아래 단언들이 무의미하다.
            """)

        // 두 번째 클릭(다른 계정, 동기 즉시 전환 분기) — 첫 전환이 끝나기 전이다.
        fixture.state.manualSwitch(to: other.id)
        XCTAssertNotNil(fixture.state.lastError, """
            진행 중인 전환이 있는데 두 번째 클릭을 조용히 버리면 사용자에게는 아무 반응 없는
            것(고장)으로 보인다 — 배너로 알려야 한다.
            """)
        XCTAssertEqual(fixture.activeID, fixture.personal.id, """
            가드가 막지 못했다면 동기 분기(other, needsReauth 이미 마킹됨)가 그 자리에서 활성을
            바꿨을 것이다 — 이게 바로 리뷰가 지적한 경합이다.
            """)

        // 첫 전환이 실제로 끝날 때까지 기다린다(가짜 토큰이라 preflight 는 실패로 끝나지만,
        // 여기서 보려는 건 그 결과가 아니라 가드가 스스로 풀리는지다).
        await firstTask.value
        XCTAssertNil(fixture.state.manualSwitchTaskForTesting, """
            완료된 전환은 스스로 가드를 풀어야 한다 — 안 풀리면 이후 어떤 수동 전환도 영구히
            거절되는, 막은 것보다 더 나쁜 결함이 된다.
            """)

        // 가드가 풀린 뒤에는 평소처럼 동작해야 한다.
        fixture.state.lastError = nil
        fixture.state.manualSwitch(to: other.id)
        XCTAssertEqual(fixture.activeID, other.id, "가드가 풀린 뒤의 정상 호출은 전환을 완료해야 한다")
    }
}
