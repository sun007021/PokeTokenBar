import XCTest
@testable import MobiusCore
@testable import PokeTokenBar

/// Shared way to build an `AccountsState` that touches nothing real.
///
/// Every path is synthetic and `localUser` is a name no keychain item carries, so the credential
/// warm-up inside `start()` resolves to "item not found" (`security … -a <bogus>` exits 44)
/// instead of reading the developer's real login. Without this, a test that merely *renders* a
/// view holding `AccountsState` would read `~/Library/Application Support/PokeTokenBar/mobius`.
///
/// `MobiusBundleGuardTests` grew the same helper first; it is lifted here because the settings
/// tests — and `SessionKeySettingsRenderingTests`, which now has to supply the environment object
/// `SettingsView` requires — need the identical guarantee.
enum MobiusTestSupport {
    /// - Parameter keychain: 기본값은 프로덕션과 같은 `SystemKeychain` — 단 위 `localUser` 가
    ///   가짜라 어떤 항목도 찾지 못한다. 실제 전환 경로를 돌려야 하는 테스트만
    ///   `InMemoryKeychain` 을 넣는다.
    /// - Parameter externalMobiusRunning: **기본값이 "안 돌고 있다"인 것이 의도**다. 진짜
    ///   `NSRunningApplication` 조회를 그대로 두면 개발자 Mac 에 Mobius.app 이 떠 있는지에
    ///   따라 `start()` 가 엔진을 올리기도, 안 올리기도 해 스위트 전체가 환경에 좌우된다.
    ///   가드 자체는 `MobiusCoexistenceGuardTests` 가 양쪽 값을 주입해 검증한다.
    @MainActor
    static func isolatedAccountsState(
        cleanupWith test: XCTestCase,
        keychain: (any KeychainClient)? = nil,
        externalMobiusRunning: @escaping @MainActor () -> Bool = { false }
    ) throws -> AccountsState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MobiusTestSupport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let env = MobiusEnvironment(
            home: root.appendingPathComponent("home"),
            localUser: "poketokenbar-test-\(UUID().uuidString)",
            codexHome: root.appendingPathComponent("codex"),
            appSupportDirOverride: root.appendingPathComponent("state"))
        let state = AccountsState(env: env, keychain: keychain ?? SystemKeychain(),
                                  externalMobiusRunning: externalMobiusRunning)
        // A test that forgets `stop()` would otherwise leave a 3-second timer running for the
        // rest of the process and keep scanning synthetic roots — and, until `stop()` learned to
        // cancel them, the work `start()` launches immediately would outlive the test too.
        test.addTeardownBlock { @MainActor in state.stop() }
        return state
    }

    /// Source of a repo-relative path, by line — for the tests that check *structure* rather than
    /// behaviour (`AccountsTabLayoutTests` and `MobiusBundleGuardTests` do the same).
    static func sourceLines(of relativePath: String, from testFile: StaticString = #filePath)
        throws -> [String]
    {
        let url = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Keeps a source scan from counting the comment that *explains* a rule as a violation of it —
    /// otherwise the rule can only be enforced by deleting its own documentation.
    static func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*")
    }
}
