import XCTest
@testable import MobiusCore
@testable import PokeTokenBar

/// 세션 로그 스캔 주기 — 틱 안에서 **유일하게 비용이 로그 트리 크기에 비례하는** 작업이라
/// 유휴 배터리의 지배 항이다. 게이트가 지켜야 하는 것은 둘이다: 유휴에는 실제로 덜 돌 것,
/// 그리고 **정확성은 하나도 안 내줄 것**(특히 전환 순간의 Codex 파일 격리 창).
@MainActor
final class MobiusScanCadenceTests: XCTestCase {

    private let window = AccountsState.idleSessionLogScanInterval
    private let activeWindow: TimeInterval = 600   // 워처의 recentWindow

    private func due(lastActivity: Date?, sinceScan: TimeInterval, activeChanged: Bool = false,
                     now: Date = Date()) -> Bool {
        AccountsState.sessionLogScanIsDue(
            now: now, lastActivity: lastActivity,
            lastScanAt: now.addingTimeInterval(-sinceScan),
            activeWindow: activeWindow, idleInterval: window, activeChanged: activeChanged)
    }

    // MARK: - 판정 (순수)

    /// 세션이 도는 동안은 매 틱 — 이 기능의 존재 이유(빠른 폴백)를 건드리면 안 된다.
    func testARunningSessionIsScannedEveryTick() {
        XCTAssertTrue(due(lastActivity: Date(), sinceScan: 0))
        XCTAssertTrue(due(lastActivity: Date().addingTimeInterval(-activeWindow + 1), sinceScan: 0))
    }

    /// 조용한 동안만 느려진다. 기준은 워처 자신의 `recentWindow` — 그 창 밖이면 직전 스캔이
    /// **구조적으로** 이벤트를 낼 수 없었다(파싱 대상에서 걸러진다).
    func testASilentLogIsScannedOnlyOnTheIdleInterval() {
        let silent = Date().addingTimeInterval(-activeWindow - 1)
        XCTAssertFalse(due(lastActivity: silent, sinceScan: window - 1))
        XCTAssertTrue(due(lastActivity: silent, sinceScan: window))
    }

    /// 첫 틱(아직 아무것도 못 본 상태)은 지연 없이 프라이밍된다 — 프라이밍이 늦으면 그만큼
    /// 추적 시작이 늦어지고, 그 사이의 append 는 tailOnly 정책에서 통째로 삼켜진다.
    func testTheFirstTickPrimesWithoutDelay() {
        let now = Date()
        XCTAssertTrue(AccountsState.sessionLogScanIsDue(
            now: now, lastActivity: nil, lastScanAt: .distantPast,
            activeWindow: activeWindow, idleInterval: window, activeChanged: false))
    }

    /// ★ 정확성 축. `CodexStatusRouter` 는 활성이 바뀐 순간의 `trackedFiles`(= 직전 스캔
    /// 완료 시점 스냅샷)로 전환 전 세션 파일을 격리한다. 그 스냅샷이 스캔 주기만큼 낡으면
    /// 전환 직전에 시작된 세션이 격리되지 않아 옛 계정의 사용량이 새 계정에 박히고,
    /// 그게 연쇄 전환(B→C→D)이 된다. 유휴여도 이 틱만은 스캔해야 창이 틱 주기로 유지된다.
    func testAnAccountChangeIsScannedEvenWhileIdle() {
        let silent = Date().addingTimeInterval(-activeWindow - 1)
        XCTAssertFalse(due(lastActivity: silent, sinceScan: 0))
        XCTAssertTrue(due(lastActivity: silent, sinceScan: 0, activeChanged: true))
    }

    // MARK: - 배선 (틱이 실제로 그 판정을 쓰는가)

    /// 판정만 잠그면 호출부가 게이트를 통째로 무시해도 초록불이다.
    func testConsecutiveIdleTicksScanOnlyOnce() async throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        await state.tick()
        XCTAssertEqual(state.sessionLogScanCountForTesting, 1, "첫 틱은 프라이밍이라 반드시 돈다")

        await state.tick()
        await state.tick()
        XCTAssertEqual(state.sessionLogScanCountForTesting, 1,
                       "조용한 로그를 매 틱 훑으면 유휴 CPU 가 로그 크기에 비례해 커진다")
    }

    /// 그리고 반대 방향 — 전환이 일어난 틱은 유휴여도 돈다(위 정확성 축의 배선).
    func testATickThatSeesAnAccountChangeScansAgain() async throws {
        let keychain = InMemoryKeychain()
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, keychain: keychain)
        let personal = try state.store.upsertProfile(
            nickname: "personal", snapshot: Self.snapshot(email: "p@x.com"))
        let work = try state.store.upsertProfile(
            nickname: "work", snapshot: Self.snapshot(email: "w@x.com"))
        try state.store.setActive(personal.id)

        await state.tick()
        let afterFirst = state.sessionLogScanCountForTesting
        await state.tick()
        XCTAssertEqual(state.sessionLogScanCountForTesting, afterFirst,
                       "활성이 그대로면 유휴 틱은 안 돈다 — 아니면 아래 단언이 무의미하다")

        try state.store.setActive(work.id)
        await state.tick()
        XCTAssertEqual(state.sessionLogScanCountForTesting, afterFirst + 1,
                       "전환 틱을 건너뛰면 라우터가 낡은 파일 목록으로 격리해 오귀인이 난다")
    }

    private static func snapshot(email: String) -> CredentialsSnapshot {
        CredentialsSnapshot(
            keychainBlob: Data(#"{"tok":"x"}"#.utf8),
            credentialsFileData: Data(#"{"tok":"x"}"#.utf8),
            oauthAccountJSON: Data(#"{"emailAddress":"\#(email)","organizationName":"O"}"#.utf8))
    }
}
