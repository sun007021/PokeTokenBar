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
    @MainActor
    static func isolatedAccountsState(cleanupWith test: XCTestCase) throws -> AccountsState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MobiusTestSupport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let env = MobiusEnvironment(
            home: root.appendingPathComponent("home"),
            localUser: "poketokenbar-test-\(UUID().uuidString)",
            codexHome: root.appendingPathComponent("codex"),
            appSupportDirOverride: root.appendingPathComponent("state"))
        let state = AccountsState(env: env)
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
