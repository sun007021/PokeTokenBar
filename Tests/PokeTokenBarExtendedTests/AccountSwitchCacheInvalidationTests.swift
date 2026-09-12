import XCTest
@testable import MobiusCore
@testable import PokeTokenBarExtended

/// 계정을 바꾼 뒤 PokeTokenBar 의 Claude 한도가 **이전 계정 값에 얼어붙는** 것을 막는 배선.
///
/// `OAuthAccessTokenCache` 는 자격증명을 인메모리로 들고 있어, 전환 후에도 옛 토큰으로 조회가
/// **성공한다.** 그래서 증상이 "한도가 안 나온다"가 아니라 "A 계정 숫자가 B 계정 게이지로
/// 그려진다"이고, 화면만 봐서는 틀렸다는 것을 알 수 없다 — `CredentialSwitchCacheTests` 가 같은
/// 부류(#227)를 CLI 쪽 in-place 재로그인에 대해 잠근 것과 짝을 이룬다.
@MainActor
final class AccountSwitchCacheInvalidationTests: XCTestCase {

    // MARK: - 프로바이더 구분 (순수)

    func testClaudeSwitchInvalidatesTheClaudeLimitCache() {
        XCTAssertTrue(MobiusSwitchSideEffects.invalidatesClaudeLimitCache(.claude))
    }

    /// PokeTokenBar 의 Codex 한도는 `~/.codex/sessions` 로그에서 온다 — 이 캐시를 거치지 않는다.
    /// 구분하지 않으면 Codex 카드를 누를 때마다 쓸모없는 Claude 한도 재조회가 따라붙는다.
    func testCodexSwitchLeavesTheClaudeLimitCacheAlone() {
        XCTAssertFalse(MobiusSwitchSideEffects.invalidatesClaudeLimitCache(.codex))
    }

    // MARK: - 수동 전환이 실제로 콜백을 지나는가

    /// 진짜 전환 경로(`Switcher.switchTo`)를 인메모리 키체인과 임시 홈으로 돌린다. 콜백이
    /// **전환이 성사된 뒤에** 그 프로바이더로 오는지까지 본다.
    func testAManualSwitchNotifiesTheHostWithTheSwitchedProvider() throws {
        let fixture = try MobiusCoexistenceGuardTests.SwitchFixture(
            test: self, externalMobiusRunning: { false })
        var notified: [Provider] = []
        fixture.state.onSwitched = { notified.append($0) }

        fixture.state.manualSwitch(to: fixture.work.id)

        XCTAssertEqual(fixture.activeID, fixture.work.id, "전환 자체가 안 됐으면 아래 단언은 무의미하다")
        XCTAssertEqual(notified, [.claude], """
            수동 전환이 호스트에 알리지 않는다 — 한도 게이지가 이전 계정 숫자에 얼어붙는다.
            """)
    }

    /// 전환이 실패하면 알리지 않는다 — 실패한 전환에 캐시를 버리면 멀쩡한 토큰을 버리고
    /// 불필요한 재조회를 부른다(이 기능의 비용이 정확히 그 재조회다).
    func testAFailedSwitchDoesNotNotifyTheHost() throws {
        let fixture = try MobiusCoexistenceGuardTests.SwitchFixture(
            test: self, externalMobiusRunning: { false })
        var notified: [Provider] = []
        fixture.state.onSwitched = { notified.append($0) }

        // 대상 기록(라이브 Keychain write)만 실패시킨다 — `Switcher` 가 롤백하고 throw 한다.
        fixture.keychain.failWritesForService = fixture.state.env.claudeKeychainService
        fixture.state.manualSwitch(to: fixture.work.id)

        XCTAssertEqual(fixture.activeID, fixture.personal.id, "롤백됐으니 활성은 그대로여야 한다")
        XCTAssertTrue(notified.isEmpty, "성사되지 않은 전환까지 알리면 캐시를 공연히 버린다")
    }

    // MARK: - 자동 전환 경로 + 호스트 배선 (소스)

    /// 자동 전환(`apply`)은 수동(`performSwitch`)과 **다른 경로**다 — 한쪽만 배선하면 그쪽
    /// 전환에서만 게이지가 낡고, 그 상태는 화면에 "틀린 숫자"로만 나타나 신고되지 않는다.
    /// 자동 경로는 엔진 결정(`Decision`)을 만들어야 도달하는데 그 결정을 테스트에서 합성하면
    /// 프로덕션 조건과 갈라지므로, **두 관문이 모두 콜백을 부르는지**를 소스에서 확인한다.
    func testBothSwitchChokepointsNotifyTheHost() throws {
        let lines = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Mobius/AccountsState.swift")
        for chokepoint in ["private func apply(", "private func performSwitch("] {
            XCTAssertTrue(Self.notifiesAfterSwitching(function: chokepoint, in: lines), """
                \(chokepoint) 이 전환 성공 뒤 onSwitched 를 부르지 않는다 — 이 경로로 계정이 \
                바뀌면 Claude 한도 게이지가 이전 계정 값에 남는다.
                """)
        }
    }

    /// 위 스캔이 **실제로 무언가를 잡는지** — 통과만 보면 아무것도 안 보는 스캔과 구별할 수 없다.
    func testTheChokepointScanRejectsASwitchThatDoesNotNotify() {
        let without = [
            "    private func performSwitch(to id: UUID) {",
            "        do {",
            "            try switcher.switchTo(id)",
            "            engines[provider]?.noteSwitched()",
            "        }",
        ]
        XCTAssertFalse(Self.notifiesAfterSwitching(function: "private func performSwitch(", in: without),
                       "콜백이 없는 함수를 통과시키면 이 스캔은 장식이다")
    }

    /// 콜백은 있는데 아무도 듣지 않으면 아무 일도 일어나지 않는다. 결합을 `AppDelegate` 에
    /// 두기로 한 결정(`AccountsState` 와 `UsageStore` 는 서로를 모른다)을 그 자리에서 잠근다.
    func testTheHostActuallyListensAndDropsTheCredentialCache() throws {
        let app = try MobiusTestSupport.sourceLines(of: "Sources/PokeTokenBarExtended/PokeTokenBarExtendedApp.swift")
            .filter { !MobiusTestSupport.isComment($0) }
            .joined(separator: "\n")
        XCTAssertTrue(app.contains("accounts.onSwitched ="),
                      "콜백을 아무도 듣지 않으면 전환 후 캐시가 그대로 남는다")
        XCTAssertTrue(app.contains("OAuthAccessTokenCache.shared.invalidate()"),
                      "캐시를 버리지 않으면 다음 조회가 이전 계정 토큰을 그대로 쓴다")
        XCTAssertTrue(app.contains("MobiusSwitchSideEffects.invalidatesClaudeLimitCache("),
                      "프로바이더를 안 가르면 Codex 전환마다 불필요한 Claude 재조회가 붙는다")
        XCTAssertTrue(app.contains("store.refresh()"),
                      "캐시만 버리면 게이지는 다음 주기 폴링까지 빈 채로 남는다")
    }

    // MARK: - 소스 스캐너 (순수 — 위 주입 테스트가 직접 먹인다)

    /// 해당 함수가 `switcher.switchTo` **성공 뒤** `onSwitched` 를 부르는지. 순서를 보는 이유는
    /// 전환이 throw 하면 알리면 안 되기 때문이다(위 `testAFailedSwitchDoesNotNotifyTheHost`).
    static func notifiesAfterSwitching(function: String, in lines: [String]) -> Bool {
        guard let start = lines.firstIndex(where: {
            !MobiusTestSupport.isComment($0) && $0.contains(function)
        }) else { return false }
        var sawSwitch = false
        for line in lines[(start + 1)...] where !MobiusTestSupport.isComment(line) {
            if line.contains("try switcher.switchTo(") { sawSwitch = true; continue }
            if sawSwitch && line.contains("onSwitched?(") { return true }
            // 다음 함수 선언까지만 본다 — 남의 함수에 있는 호출을 이 함수의 것으로 세지 않게.
            if line.contains("    func ") || line.contains("    private func ") { return false }
        }
        return false
    }
}
