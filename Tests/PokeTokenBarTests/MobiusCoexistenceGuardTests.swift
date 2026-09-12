import XCTest
@testable import MobiusCore
@testable import PokeTokenBar

/// 이중 writer 가드 — 기존 Mobius.app 이 실행 중이면 이 앱은 계정 전환을 하지 않는다.
///
/// 막으려는 사고는 **에러로 나타나지 않는다.** Keychain(토큰)과 `~/.claude.json`(이메일)은
/// 서로 다른 시점에 갱신되므로, 두 프로세스가 같은 자원을 스왑하면 낡은 토큰과 최신 이메일이
/// 한 프로필에 짝지어져 사용자의 라이브 로그인이 조용히 오염된다(원본 Mobius '실패 기록 1').
/// 그래서 "타이머가 nil 이다" 같은 간접 관찰이 아니라 **전환이 실제로 일어나지 않았는지**를
/// 활성 계정으로 확인한다.
@MainActor
final class MobiusCoexistenceGuardTests: XCTestCase {

    // MARK: - 판정 (순수)

    private func instance(_ id: String, terminated: Bool = false) -> MobiusCoexistence.ExternalInstance {
        .init(bundleID: id, isTerminated: terminated)
    }

    func testBlocksWhenAMobiusInstanceIsAlive() {
        XCTAssertTrue(MobiusCoexistence.isBlocked(by: [instance(MobiusCoexistence.mobiusBundleID)]))
    }

    func testDoesNotBlockWhenNothingIsRunning() {
        XCTAssertFalse(MobiusCoexistence.isBlocked(by: []))
    }

    /// 자동 재개가 이 한 줄에 달려 있다 — `NSRunningApplication` 객체는 프로세스가 죽은 뒤에도
    /// 잠시 남고, 그걸 세면 Mobius.app 을 종료한 사용자가 영영 풀리지 않는 정지를 겪는다.
    func testDoesNotBlockOnATerminatedInstance() {
        XCTAssertFalse(MobiusCoexistence.isBlocked(
            by: [instance(MobiusCoexistence.mobiusBundleID, terminated: true)]))
    }

    func testIgnoresOtherApplications() {
        XCTAssertFalse(MobiusCoexistence.isBlocked(by: [instance("io.github.chattymin.poketokenbar")]))
    }

    func testBlocksWhenOneOfSeveralInstancesIsAlive() {
        XCTAssertTrue(MobiusCoexistence.isBlocked(by: [
            instance(MobiusCoexistence.mobiusBundleID, terminated: true),
            instance(MobiusCoexistence.mobiusBundleID),
        ]))
    }

    /// 판정의 **입력**을 실제로 읽어낼 수 있는지 — `SingleInstanceTests` 가 커널 시작 시각에
    /// 대해 같은 층을 잠그는 이유와 같다(첫 구현이 무효였던 원인이 판정이 아니라 입력이었다).
    /// 값 자체는 환경에 따라 다르므로 단언하지 않고, 조회가 터지거나 남의 앱을 섞어 오지
    /// 않는지만 본다.
    func testRunningInstancesOnlyReportsMobius() {
        for instance in MobiusCoexistence.runningInstances() {
            XCTAssertEqual(instance.bundleID, MobiusCoexistence.mobiusBundleID)
        }
    }

    // MARK: - 엔진이 실제로 안 도는가

    func testStartInstallsNoEngineWhileMobiusIsRunning() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { true })
        state.start()

        XCTAssertTrue(state.blockedByExternalApp, "막힌 상태는 화면에 보여야 하므로 상태로 남는다")
        XCTAssertNil(state.tickTimerForTesting, "틱 타이머가 서면 3초마다 자동 전환 판단이 돈다")
        XCTAssertNil(state.tickTaskForTesting,
                     "start() 는 타이머와 별개로 즉시 한 틱을 띄운다 — 그 틱도 없어야 한다")
        XCTAssertFalse(state.isObservingExternalChangesForTesting)
    }

    /// 막힌 동안에도 **감시만은** 살아 있어야 한다. 여기가 비면 자동 재개의 동력이 없어져
    /// 사용자가 앱을 재시작해야 복구된다.
    func testTheExternalAppWatchKeepsRunningWhileBlocked() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { true })
        state.start()

        let watch = try XCTUnwrap(state.externalAppWatchTimerForTesting,
                                  "감시 타이머가 없으면 Mobius.app 이 꺼져도 영영 못 살아난다")
        XCTAssertTrue(watch.isValid)
    }

    /// 자동 재개 — 감시가 다음번에 보는 값이 바뀌면 엔진이 뜬다. 타이머의 5초를 기다리는 대신
    /// 그 타이머가 부르는 함수를 직접 불러 시계 의존성을 없앤다.
    func testTheEngineResumesByItselfWhenMobiusQuits() throws {
        var mobiusRunning = true
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { mobiusRunning })
        state.start()
        XCTAssertNil(state.tickTimerForTesting)

        mobiusRunning = false
        state.reevaluateExternalApp()

        XCTAssertFalse(state.blockedByExternalApp)
        let timer = try XCTUnwrap(state.tickTimerForTesting,
                                  "Mobius.app 이 종료됐는데도 엔진이 안 뜨면 사용자는 앱을 재시작해야 한다")
        XCTAssertTrue(timer.isValid)
    }

    /// 반대 방향 — 켜고 잘 돌던 중에 Mobius.app 이 뜨면 그 자리에서 물러난다.
    func testTheEngineStandsDownWhenMobiusAppearsLater() throws {
        var mobiusRunning = false
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { mobiusRunning })
        state.start()
        let timer = try XCTUnwrap(state.tickTimerForTesting)
        let tick = try XCTUnwrap(state.tickTaskForTesting)

        mobiusRunning = true
        state.reevaluateExternalApp()

        XCTAssertTrue(state.blockedByExternalApp)
        XCTAssertNil(state.tickTimerForTesting)
        XCTAssertFalse(timer.isValid, "필드만 비우고 무효화하지 않으면 틱은 계속 돈다")
        XCTAssertTrue(tick.isCancelled, "이미 떠 있던 틱은 취소되지 않으면 끝까지 가서 계정을 바꾼다")
        XCTAssertTrue(state.isObservingExternalChangesForTesting == false)
    }

    /// 기능을 끄면 엔진뿐 아니라 **감시까지** 걷힌다 — "끄면 아무것도 안 돈다"에는 이 타이머도
    /// 포함된다.
    func testStopAlsoTearsDownTheExternalAppWatch() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(
            cleanupWith: self, externalMobiusRunning: { true })
        state.start()
        let watch = try XCTUnwrap(state.externalAppWatchTimerForTesting)

        state.stop()
        XCTAssertNil(state.externalAppWatchTimerForTesting)
        XCTAssertFalse(watch.isValid)
        XCTAssertFalse(state.blockedByExternalApp, "꺼진 기능에 대한 '막혔어요' 안내는 거짓말이다")
    }

    // MARK: - 전환이 실제로 일어나지 않는가 (가드의 본론)

    /// 타이머가 없다는 것만으로는 부족하다 — 사용자가 카드를 누르는 **수동** 전환도 같은
    /// 전역 자격증명을 쓴다. 진짜 전환 경로(`Switcher.switchTo`)를 인메모리 키체인과 임시
    /// 홈으로 돌려, 막힌 동안에는 활성 계정이 **바뀌지 않는지**를 본다.
    func testAManualSwitchIsRefusedWhileMobiusIsRunning() throws {
        var mobiusRunning = true
        let fixture = try SwitchFixture(test: self, externalMobiusRunning: { mobiusRunning })

        fixture.state.manualSwitch(to: fixture.work.id)
        XCTAssertEqual(fixture.activeID, fixture.personal.id, """
            막힌 동안 전환이 성사됐다 — 두 앱이 같은 Keychain·~/.claude.json 을 스왑하면 \
            낡은 토큰과 최신 이메일이 짝지어져 라이브 로그인이 에러 없이 오염된다.
            """)

        // 같은 fixture 로 반대 브랜치도 본다: 가드가 풀리면 그 전환은 실제로 된다.
        // (이게 없으면 위 단언은 "전환 자체가 원래 안 되는 fixture" 와 구별되지 않는다.)
        mobiusRunning = false
        fixture.state.manualSwitch(to: fixture.work.id)
        XCTAssertEqual(fixture.activeID, fixture.work.id,
                       "Mobius.app 이 없으면 같은 호출이 성사돼야 한다 — 아니면 위 단언은 무의미하다")
    }

    /// 계정 추가도 라이브 자격증명을 바꾼다(`claude auth login` → adopt). 막힌 동안 로그인
    /// 창이 뜨면 상대 앱이 그 변경을 흡수해 두 앱의 프로필이 갈라진다.
    ///
    /// "로그인 창이 안 떴다"만 보면 부족하다 — 가드를 지우면 `claude` CLI 가 없는 머신에서는
    /// 로그인 대신 "CLI 를 설치하세요" 로 빠져 그 단언이 그대로 통과한다(주입으로 확인했다).
    /// **아무 일도 일어나지 않았다**를 보려면 그 안내까지 없어야 한다.
    func testAddingAnAccountIsRefusedWhileMobiusIsRunning() throws {
        let fixture = try SwitchFixture(test: self, externalMobiusRunning: { true })
        XCTAssertNil(fixture.state.lastError, "fixture 가 이미 에러를 들고 있으면 아래 단언이 무의미하다")

        fixture.state.addAccount()

        XCTAssertFalse(fixture.state.isLoginFlowActiveForTesting,
                       "막힌 동안 로그인 플로우가 뜨면 상대 앱과 자격증명을 두고 경합한다")
        XCTAssertNil(fixture.state.lastError,
                     "가드는 즉시 물러나야 한다 — 여기까지 왔다면 로그인 경로에 들어간 것이다")
    }

    // MARK: - fixture

    /// 실제 전환을 돌릴 수 있는 최소 구성 — 계정 둘, 활성은 `personal`.
    ///
    /// `work` 를 `needsReauth` 로 표시하는 이유는 오직 하나다: 그러면 `manualSwitch` 가
    /// preflight(OAuth refresh **네트워크** 호출)를 건너뛰고 곧바로 전환 관문으로 간다.
    /// 테스트가 네트워크에 손대지 않으면서 프로덕션 경로를 그대로 밟는 방법이다.
    @MainActor
    struct SwitchFixture {
        let state: AccountsState
        let personal: AccountProfile
        let work: AccountProfile
        /// 전환을 **실패시키는** 주입 지점(`failWritesForService`). 성공 경로만 테스트하면
        /// "성사되지 않은 전환에서는 뒤처리를 하지 않는다" 같은 순서 계약을 확인할 수 없다.
        let keychain: InMemoryKeychain

        var activeID: UUID? { state.store.file.activeByProvider[.claude] }

        init(test: XCTestCase, externalMobiusRunning: @escaping @MainActor () -> Bool) throws {
            let keychain = InMemoryKeychain()
            self.keychain = keychain
            state = try MobiusTestSupport.isolatedAccountsState(
                cleanupWith: test, keychain: keychain,
                externalMobiusRunning: externalMobiusRunning)
            try FileManager.default.createDirectory(at: state.env.claudeDir,
                                                    withIntermediateDirectories: true)
            personal = try state.store.upsertProfile(nickname: "personal",
                                                     snapshot: Self.snapshot(email: "p@x.com", token: "P0"))
            work = try state.store.upsertProfile(nickname: "work",
                                                 snapshot: Self.snapshot(email: "w@x.com", token: "W0"))
            try state.io.writeLiveSnapshot(Self.snapshot(email: "p@x.com", token: "P0"))
            try state.store.setActive(personal.id)
            try state.store.update(work.id) { $0.needsReauth = true }
            state.reload()
        }

        static func snapshot(email: String, token: String) -> CredentialsSnapshot {
            CredentialsSnapshot(
                keychainBlob: Data(#"{"tok":"\#(token)"}"#.utf8),
                credentialsFileData: Data(#"{"tok":"\#(token)"}"#.utf8),
                oauthAccountJSON: Data(#"{"emailAddress":"\#(email)","organizationName":"O"}"#.utf8))
        }
    }
}
