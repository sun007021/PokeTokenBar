import XCTest
@testable import MobiusCore

final class SwitcherTests: XCTestCase {
    var tmp: URL!; var env: MobiusEnvironment!; var kc: InMemoryKeychain!
    var store: AccountStore!; var io: ClaudeConfigIO!; var switcher: Switcher!
    var personal: AccountProfile!; var work: AccountProfile!

    func snap(email: String, tok: String) -> CredentialsSnapshot {
        CredentialsSnapshot(
            keychainBlob: Data(#"{"tok":"\#(tok)"}"#.utf8),
            credentialsFileData: Data(#"{"tok":"\#(tok)"}"#.utf8),
            oauthAccountJSON: Data(#"{"emailAddress":"\#(email)","organizationName":"O"}"#.utf8))
    }

    /// 실제 Claude blob 형태(refreshToken 포함) — 딱지 해제 판정이 읽는 필드가 들어 있다.
    func oauthSnap(email: String, access: String, refresh: String) -> CredentialsSnapshot {
        let blob = Data(#"{"claudeAiOauth":{"accessToken":"\#(access)","refreshToken":"\#(refresh)"}}"#.utf8)
        return CredentialsSnapshot(
            keychainBlob: blob, credentialsFileData: blob,
            oauthAccountJSON: Data(#"{"emailAddress":"\#(email)","organizationName":"O"}"#.utf8))
    }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mobius-sw-\(UUID().uuidString)")
        env = MobiusEnvironment(home: tmp, localUser: "tester")
        try FileManager.default.createDirectory(at: env.claudeDir, withIntermediateDirectories: true)
        kc = InMemoryKeychain()
        store = try AccountStore(env: env, keychain: kc)
        io = ClaudeConfigIO(env: env, keychain: kc)
        switcher = Switcher(env: env, keychain: kc, store: store, io: io)
        personal = try store.upsertProfile(nickname: "personal", snapshot: snap(email: "p@x.com", tok: "P0"))
        work = try store.upsertProfile(nickname: "work", snapshot: snap(email: "w@x.com", tok: "W0"))
        try io.writeLiveSnapshot(snap(email: "p@x.com", tok: "P0")) // 현재 personal 로그인 상태
        try store.setActive(personal.id)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testSwitchWritesTargetAndResavesCurrent() throws {
        // CLI가 refresh 토큰을 갱신했다고 가정: 라이브에는 P1
        try io.writeLiveSnapshot(snap(email: "p@x.com", tok: "P1"))
        try switcher.switchTo(work.id)
        // 라이브는 work
        XCTAssertEqual(try io.liveEmail(), "w@x.com")
        XCTAssertEqual(store.file.activeAccountID, work.id)
        // personal 프로필에는 최신 P1이 되저장됨
        XCTAssertEqual(try store.secret(for: personal.id)?.keychainBlob,
                       Data(#"{"tok":"P1"}"#.utf8))
    }

    func testRollbackOnFailure() throws {
        // 대상 기록 단계에서만 실패 주입: 되저장은 Mobius-account-* 서비스라 통과하고,
        // 라이브 서비스로의 첫 write(대상 기록)가 실패 → catch의 롤백 write가 실행된다.
        // failWritesForService는 1회 소모형이라 롤백 write 자체는 통과한다.
        kc.failWritesForService = env.claudeKeychainService
        XCTAssertThrowsError(try switcher.switchTo(work.id))
        XCTAssertEqual(try io.liveEmail(), "p@x.com") // 복구됨
        XCTAssertEqual(store.file.activeAccountID, personal.id)
        // 롤백이 실제로 실행됨: 라이브 Keychain 항목이 원래 blob으로 되돌아옴
        XCTAssertEqual(try kc.read(service: env.claudeKeychainService,
                                   account: env.claudeKeychainAccount),
                       Data(#"{"tok":"P0"}"#.utf8))
    }

    func testSwitchToUnknownAccountThrows() throws {
        XCTAssertThrowsError(try switcher.switchTo(UUID())) { error in
            XCTAssertEqual(error as? SwitcherError, .unknownAccount)
        }
    }

    func testReconcileDetectsExternalLogin() async throws {
        // 사용자가 앱 밖에서 work로 직접 재로그인한 상황
        try io.writeLiveSnapshot(snap(email: "w@x.com", tok: "W-ext"))
        try await switcher.reconcile()
        XCTAssertEqual(store.file.activeAccountID, work.id)
        // 외부 로그인으로 생긴 최신 토큰이 프로필에 흡수됨
        XCTAssertEqual(try store.secret(for: work.id)?.keychainBlob,
                       Data(#"{"tok":"W-ext"}"#.utf8))
    }

    func testReconcileUnknownEmailDoesNothing() async throws {
        try io.writeLiveSnapshot(snap(email: "stranger@x.com", tok: "S"))
        try await switcher.reconcile()
        XCTAssertEqual(store.file.activeAccountID, personal.id) // 그대로
    }

    // MARK: refreshActiveSnapshotIfStable — 신선도 계약(반환값)
    // 호출자는 true를 "저장 secret이 이번 사이클 기준 신선"으로 읽고 라이브 재읽기를 생략한다.
    // 따라서 세 경로(가드 실패 / 성공 / 저장 throw)가 각각 정직하게 보고되는지 못 박는다.

    func testRefreshActiveSnapshotReturnsFalseOnEmailMismatch() async throws {
        // 라이브가 등록되지 않은 이메일 → 첫 가드에서 탈락 (쓰기 없음).
        try io.writeLiveSnapshot(snap(email: "stranger@x.com", tok: "S"))
        let wrote = await switcher.refreshActiveSnapshotIfStable()
        XCTAssertFalse(wrote)
    }

    func testRefreshActiveSnapshotReturnsTrueOnSuccessfulWrite() async throws {
        // claude가 라이브 토큰을 P1으로 갱신한 상태 — 활성 계정이라 스냅샷에 반영돼야 한다.
        try io.writeLiveSnapshot(snap(email: "p@x.com", tok: "P1"))
        let wrote = await switcher.refreshActiveSnapshotIfStable()
        XCTAssertTrue(wrote)
        XCTAssertEqual(try store.secret(for: personal.id)?.keychainBlob,
                       Data(#"{"tok":"P1"}"#.utf8))
    }

    func testRefreshActiveSnapshotReturnsFalseWhenStoreWriteThrows() async throws {
        // 모든 가드는 통과시키고 **저장만** 실패시킨다: secrets 디렉토리 자리에 일반 파일을
        // 놓으면 writeSecretFile의 createDirectory가 throw한다. 구 `try?` 구현은 이 실패를
        // 삼켜 true(신선)로 보고했을 경로 — 그게 이 테스트가 지키는 지점이다.
        try io.writeLiveSnapshot(snap(email: "p@x.com", tok: "P1"))
        try FileManager.default.removeItem(at: env.secretsDir)
        try Data("not a directory".utf8).write(to: env.secretsDir)

        let wrote = await switcher.refreshActiveSnapshotIfStable()
        XCTAssertFalse(wrote)
    }

    // MARK: needsReauth 해제 — refresh 토큰 회전 (이슈 #14)
    // 딱지를 자동으로 내리는 경로가 usage 200 하나뿐이었고 그건 '사용량 게이지 표시' 토글에
    // 물려 있었다 → 게이지를 끄면 딱지가 일방향 래치가 된다. 라이브 스냅샷을 저장할 때
    // refresh 토큰이 실제로 교체됐으면(=재로그인/성공한 회전) 딱지를 내려 그 틈을 메운다.

    private func reauthFlag(_ id: UUID) -> Bool {
        store.file.accounts.first { $0.id == id }?.needsReauth ?? false
    }

    func testRefreshActiveSnapshotClearsReauthWhenRefreshTokenRotated() async throws {
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A0", refresh: "R0"))
        _ = await switcher.refreshActiveSnapshotIfStable()   // 저장 스냅샷을 R0로 맞춘다
        try store.setNeedsReauth(personal.id, true)          // 그 뒤 폐기 판정을 받은 상태

        // 사용자가 CLI에서 재로그인 → 라이브 refresh 토큰이 R1으로 교체됨
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A1", refresh: "R1"))
        let wrote = await switcher.refreshActiveSnapshotIfStable()

        XCTAssertTrue(wrote)
        XCTAssertFalse(reauthFlag(personal.id), "refresh 토큰이 교체됐으면 딱지를 내려야 한다")
    }

    func testRefreshActiveSnapshotKeepsReauthWhenTokenUnchanged() async throws {
        // ★ 회귀 가드: "저장 바이트가 바뀌면 해제"로 넓히면 여기서 딱지가 풀린다.
        //   활성 계정의 라이브 스냅샷은 5분마다 무조건 되저장되므로, 진짜 죽은 계정도
        //   같은 죽은 토큰이 계속 저장된다 → 딱지가 5분 이상 버티지 못하고 엔진이
        //   죽은 계정을 정상 후보로 취급하게 된다.
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A0", refresh: "R0"))
        _ = await switcher.refreshActiveSnapshotIfStable()
        try store.setNeedsReauth(personal.id, true)

        // access 토큰만 바뀌고 refresh 토큰은 그대로 = 살아있다는 증거가 아니다
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A1", refresh: "R0"))
        let wrote = await switcher.refreshActiveSnapshotIfStable()

        XCTAssertTrue(wrote)
        XCTAssertTrue(reauthFlag(personal.id), "refresh 토큰이 그대로면 딱지를 유지해야 한다")
    }

    func testReconcileClearsReauthOnExternalRelogin() async throws {
        // 딱지가 붙은 채 폴백으로 밀려난 계정(work)에 사용자가 앱 밖에서 재로그인한 상황
        try store.setSecret(oauthSnap(email: "w@x.com", access: "A0", refresh: "R0"), for: work.id)
        try store.setNeedsReauth(work.id, true)

        try io.writeLiveSnapshot(oauthSnap(email: "w@x.com", access: "A1", refresh: "R1"))
        try await switcher.reconcile()

        XCTAssertEqual(store.file.activeAccountID, work.id)
        XCTAssertFalse(reauthFlag(work.id))
    }

    func testLiveSaveSkipsPreviousSnapshotReadWhenNotFlagged() async throws {
        // 실패 기록 3b: 값싼 조건을 먼저. 딱지가 없는 정상 계정(대다수)은 이전 스냅샷을
        // 읽을 이유가 없다 — 비밀 파일이 없으면 secretData가 구버전 Keychain 항목까지
        // 찾아보므로(security subprocess), 조건 없이 읽으면 5분마다 그 비용을 낸다.
        let secretService = AccountStore.secretService(for: personal.id)
        try FileManager.default.removeItem(at: env.secretFile(for: personal.id))
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A1", refresh: "R1"))

        var wrote = await switcher.refreshActiveSnapshotIfStable()
        XCTAssertTrue(wrote)
        XCTAssertNil(kc.readsByService[secretService], "딱지가 없으면 이전 스냅샷을 읽지 않는다")

        // 딱지가 붙으면 그때만 읽는다 — 해제 판정에 이전 토큰이 필요하므로.
        try store.setNeedsReauth(personal.id, true)
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A2", refresh: "R2"))
        wrote = await switcher.refreshActiveSnapshotIfStable()
        XCTAssertTrue(wrote)
        XCTAssertFalse(reauthFlag(personal.id))
    }

    func testResaveOnSwitchClearsReauthOfOutgoingAccount() async throws {
        // 전환 직전 되저장 경로 — 떠나는 계정의 라이브 토큰이 그새 회전했다면 그것도 증거다.
        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A0", refresh: "R0"))
        _ = await switcher.refreshActiveSnapshotIfStable()
        try store.setNeedsReauth(personal.id, true)

        try io.writeLiveSnapshot(oauthSnap(email: "p@x.com", access: "A1", refresh: "R1"))
        try switcher.switchTo(work.id)

        XCTAssertEqual(store.file.activeAccountID, work.id)
        XCTAssertFalse(reauthFlag(personal.id))
    }

    // MARK: 표시용 플랜 자가 치유 (reconcile)

    /// 라이브 oauthAccount 를 그대로 쓴다 — 플랜 필드까지 든 실제 형태.
    private func writeLiveOAuth(email: String, type: String?, tier: String?) throws {
        var block: [String: Any] = ["emailAddress": email, "organizationName": "O"]
        if let type { block["organizationType"] = type }
        if let tier { block["organizationRateLimitTier"] = tier }
        let json: [String: Any] = ["oauthAccount": block]
        try JSONSerialization.data(withJSONObject: json).write(to: env.claudeJSON)
    }

    /// 저장된 `tierDescription` 은 등록 시점의 파생값이라, 플랜이 바뀌거나(Pro→Max) 표시 규칙이
    /// 고쳐져도 옛 문자열이 남는다. 라이브가 진실이므로 reconcile 이 따라가야 한다.
    func testReconcileRefreshesAStaleStoredPlan() async throws {
        try store.update(personal.id) { $0.tierDescription = "Ai" }
        try writeLiveOAuth(email: "p@x.com", type: "claude_pro", tier: "default_claude_ai")

        try await switcher.reconcile()

        XCTAssertEqual(store.file.accounts.first { $0.id == personal.id }?.tierDescription, "Pro")
    }

    /// ★ 이 테스트가 없으면 자가 치유는 **15초마다 accounts.json 을 다시 쓰는** 기능이 된다.
    /// 저장 여부는 파일을 지워 두고 다시 생겼는지로 본다 — mtime 해상도에 안 기댄다.
    func testReconcileDoesNotWriteWhenThePlanIsUnchanged() async throws {
        try writeLiveOAuth(email: "p@x.com", type: "claude_pro", tier: "default_claude_ai")
        try await switcher.reconcile()   // 1회차: 갱신 + 저장
        XCTAssertEqual(store.file.accounts.first { $0.id == personal.id }?.tierDescription, "Pro")

        try FileManager.default.removeItem(at: env.accountsFile)
        try await switcher.reconcile()   // 2회차: 값이 같다 → 저장이 없어야 한다

        XCTAssertFalse(FileManager.default.fileExists(atPath: env.accountsFile.path),
                       "값이 그대로인데 저장하면 정상 상태의 매 틱이 디스크 쓰기가 된다")
    }

    /// 바쁜 파일(`~/.claude.json`)에서 플랜 필드가 아직 없는 상태를 읽을 수 있다.
    /// 그때 멀쩡한 값을 빈 줄로 지우면 사용자에겐 그게 곧 결함이다.
    func testReconcileNeverBlanksAStoredPlanWithAnEmptyReading() async throws {
        try store.update(personal.id) { $0.tierDescription = "Max 20X" }
        try writeLiveOAuth(email: "p@x.com", type: nil, tier: nil)
        try FileManager.default.removeItem(at: env.accountsFile)

        try await switcher.reconcile()

        XCTAssertEqual(store.file.accounts.first { $0.id == personal.id }?.tierDescription,
                       "Max 20X")
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.accountsFile.path),
                       "정보 없는 읽기는 저장도 하지 않는다")
    }

    /// 라이브 이메일과 짝이 맞는 프로필만 건드린다 — 플랜은 계정마다 다르다.
    func testReconcileLeavesOtherAccountsAlone() async throws {
        try store.update(work.id) { $0.tierDescription = "Team" }
        try writeLiveOAuth(email: "p@x.com", type: "claude_max", tier: "default_claude_max_20x")

        try await switcher.reconcile()

        XCTAssertEqual(store.file.accounts.first { $0.id == personal.id }?.tierDescription,
                       "Max 20X")
        XCTAssertEqual(store.file.accounts.first { $0.id == work.id }?.tierDescription, "Team",
                       "라이브가 아닌 계정의 플랜을 라이브 값으로 덮으면 계정이 뒤섞인다")
    }
}
