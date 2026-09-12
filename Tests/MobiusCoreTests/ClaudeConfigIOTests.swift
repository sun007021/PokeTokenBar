import XCTest
@testable import MobiusCore

final class ClaudeConfigIOTests: XCTestCase {
    var tmp: URL!
    var env: MobiusEnvironment!
    var kc: InMemoryKeychain!
    var io: ClaudeConfigIO!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mobius-test-\(UUID().uuidString)")
        env = MobiusEnvironment(home: tmp, localUser: "tester")
        try FileManager.default.createDirectory(at: env.claudeDir,
                                                withIntermediateDirectories: true)
        kc = InMemoryKeychain()
        io = ClaudeConfigIO(env: env, keychain: kc)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func seedLive(email: String = "p@x.com") throws {
        try kc.write(service: env.claudeKeychainService, account: env.claudeKeychainAccount,
                     data: Data(#"{"tok":"secret-A"}"#.utf8))
        try Data(#"{"tok":"secret-A"}"#.utf8).write(to: env.credentialsFile)
        let claudeJSON = #"{"otherKey":42,"oauthAccount":{"emailAddress":"\#(email)","organizationName":"Org"}}"#
        try Data(claudeJSON.utf8).write(to: env.claudeJSON)
    }

    func testReadLiveSnapshot() throws {
        try seedLive()
        let snap = try XCTUnwrap(io.readLiveSnapshot())
        XCTAssertEqual(snap.keychainBlob, Data(#"{"tok":"secret-A"}"#.utf8))
        XCTAssertEqual(snap.credentialsFileData, Data(#"{"tok":"secret-A"}"#.utf8))
        XCTAssertEqual(try io.liveEmail(), "p@x.com")
    }

    func testReadReturnsNilWithoutKeychain() throws {
        XCTAssertNil(try io.readLiveSnapshot())
    }

    func testWritePreservesOtherKeys() throws {
        try seedLive()
        var snap = try XCTUnwrap(io.readLiveSnapshot())
        snap.keychainBlob = Data(#"{"tok":"secret-B"}"#.utf8)
        snap.credentialsFileData = Data(#"{"tok":"secret-B"}"#.utf8)
        snap.oauthAccountJSON = Data(#"{"emailAddress":"w@x.com"}"#.utf8)
        try io.writeLiveSnapshot(snap)

        XCTAssertEqual(try kc.read(service: env.claudeKeychainService,
                                   account: env.claudeKeychainAccount),
                       Data(#"{"tok":"secret-B"}"#.utf8))
        XCTAssertEqual(try Data(contentsOf: env.credentialsFile),
                       Data(#"{"tok":"secret-B"}"#.utf8))
        let dict = try JSONSerialization.jsonObject(
            with: Data(contentsOf: env.claudeJSON)) as! [String: Any]
        XCTAssertEqual(dict["otherKey"] as? Int, 42) // 다른 키 보존
        XCTAssertEqual((dict["oauthAccount"] as? [String: Any])?["emailAddress"] as? String,
                       "w@x.com")
        XCTAssertEqual(try io.liveEmail(), "w@x.com")
    }

    // MARK: 플랜 표시 — `organizationType` vs `organizationRateLimitTier`

    /// 두 필드는 다른 축이다. Pro 계정에서 rate-limit 티어는 플랜이 아니라 "claude.ai 개인
    /// 계정"(`default_claude_ai`)을 뜻해, 그걸 우선하면 카드에 `Ai` 가 찍힌다(사용자 리포트).
    /// 실측값 픽스처: 2026-09-12, `~/.claude.json` 의 `oauthAccount`.
    func testProPlanComesFromOrganizationTypeNotTheRateLimitTier() {
        let tier = ClaudeConfigIO.tierDescription(from: [
            "organizationType": "claude_pro",
            "organizationRateLimitTier": "default_claude_ai",
        ])
        XCTAssertEqual(tier, "Pro", "`default_claude_ai` 는 플랜이 아니다 — 그걸 쓰면 `Ai` 가 된다")
    }

    /// 반대 방향의 회귀: Max 에서는 티어가 플랜보다 **상세**하다. 우선순위를 그냥 뒤집으면
    /// 이 사용자가 "Max" 로 퇴화한다.
    func testMaxKeepsTheMoreDetailedRateLimitTier() {
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [
            "organizationType": "claude_max",
            "organizationRateLimitTier": "default_claude_max_20x",
        ]), "Max 20X")
    }

    func testMissingBothFieldsIsEmptyNotACrash() {
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [:]), "")
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: ["organizationName": "Org"]), "")
    }

    /// `organizationType` 이 없으면 티어가 유일한 신호다 — 플랜을 담았든 아니든 예전 그대로.
    func testRateLimitTierAloneKeepsItsPreviousRendering() {
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [
            "organizationRateLimitTier": "default_claude_max_20x",
        ]), "Max 20X")
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [
            "organizationRateLimitTier": "default_claude_ai",
        ]), "Ai")
    }

    /// 모르는 티어는 손대지 않는다 — 관찰한 일반값 하나만 걸러내므로 회귀 면적이 0이다.
    func testUnknownRateLimitTierStillWinsOverTheType() {
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [
            "organizationType": "claude_pro",
            "organizationRateLimitTier": "default_claude_team_premium",
        ]), "Team Premium")
    }

    func testEmptyStringsAreTreatedAsAbsent() {
        XCTAssertEqual(ClaudeConfigIO.tierDescription(from: [
            "organizationType": "claude_pro", "organizationRateLimitTier": "",
        ]), "Pro")
    }
}
