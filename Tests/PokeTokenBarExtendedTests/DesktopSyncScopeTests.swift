import XCTest
@testable import MobiusCore
@testable import PokeTokenBarExtended

/// Regression tests for the "Desktop sync fires on every manual Claude switch" defect.
///
/// `AccountsFile.desktopSyncEnabled` is a persisted field whose default is **`true`**
/// (`MobiusCore/Models.swift`) — a decision Mobius itself made, not this fork. This fork ships no
/// UI to turn it off: `AccountsState.setDesktopSync`/`setDesktopAutoSwitch` have no caller anywhere
/// in the view layer (confirmed by grep across `Sources/PokeTokenBarExtended/UI`). So a user who
/// never touched this setting still has `desktopSyncEnabled == true` — either because a fresh
/// `AccountStore` seeds `AccountsFile()` with that default, or because it was already written to
/// disk by an old `Mobius.app` and carried over by the migration. Either way, before the fix,
/// **every manual Claude account switch** called `switchDesktopIfPossible`, which can terminate and
/// log out the real Claude Desktop app with no warning and no way back (`docs/reference/
/// mobius-integration.md` §결정 사항 excludes this from v1 scope — it was never supposed to run).
///
/// `MobiusFeature.desktopSyncInScope` now gates both call sites (`AccountsState.performSwitch` and
/// `apply`) independently of the stored/default value, so this is safe regardless of what's on
/// disk.
///
/// ★ These tests never let `DesktopCoordinator.switchDesktop` actually run. `DesktopCoordinator`
/// operates on the **real** `com.anthropic.claudefordesktop` bundle via `NSRunningApplication` —
/// nothing about it is sandboxed by `MobiusEnvironment`. A test that exercised it for real could
/// terminate whatever real Claude Desktop happens to be running on the machine executing this
/// suite. So instead of asserting "Desktop wasn't touched" after the fact, the behavioural tests
/// below assert `switchDesktopIfPossible` was never **entered**
/// (`desktopSwitchAttemptsForTesting`), which is decided before any real system call — the counter
/// increments at the very top of the function, before it's even reachable, so it proves the outer
/// gate rather than the inner ones. The automatic-switch path (`apply`) is instead covered by a
/// source scan (below) since driving a real engine decision to exhaustion isn't worth the added
/// surface for a guard this direct.
@MainActor
final class DesktopSyncScopeTests: XCTestCase {

    /// Locks the scope decision itself. If this ever needs to flip to `true` it must happen
    /// alongside real UI to turn the feature off (`docs/reference/mobius-integration.md`), not by
    /// itself — flipping it alone reopens this defect.
    func testDesktopSyncIsStillOutOfScope() {
        XCTAssertFalse(MobiusFeature.desktopSyncInScope,
                       "flipping this without shipping the UI to disable it reopens the defect")
    }

    /// The actual reported defect: a fresh `AccountStore` (no accounts.json on disk yet) already
    /// carries `desktopSyncEnabled == true` because that's `AccountsFile`'s default. A manual
    /// switch must not enter the Desktop path anyway.
    func testManualSwitchDoesNotAttemptDesktopSyncWithTheDefaultStoredValue() throws {
        let fixture = try Fixture(test: self)
        XCTAssertTrue(fixture.state.store.file.desktopSyncEnabled,
                      "the fixture must reproduce the real default — otherwise this test proves nothing")

        fixture.state.manualSwitch(to: fixture.work.id)

        XCTAssertEqual(fixture.activeID, fixture.work.id, "the credential switch itself must still work")
        XCTAssertEqual(fixture.state.desktopSwitchAttemptsForTesting, 0,
                       "switchDesktopIfPossible must never be entered while Desktop sync is out of scope")
    }

    /// Same defect, but with the value explicitly re-affirmed as `true` through the store API —
    /// covering the "an old Mobius.app already wrote `desktopSyncEnabled: true` to this user's
    /// accounts.json, and the migration carried it over" path the report described. Functionally
    /// indistinguishable from a decoded `true` (it's the same `AccountsFile.desktopSyncEnabled`
    /// flag either way), but this makes the precondition explicit rather than incidental.
    func testManualSwitchDoesNotAttemptDesktopSyncWithAnExplicitlyStoredTrue() throws {
        let fixture = try Fixture(test: self)
        try fixture.state.store.setDesktopSync(true)
        XCTAssertTrue(fixture.state.store.file.desktopSyncEnabled)

        fixture.state.manualSwitch(to: fixture.work.id)

        XCTAssertEqual(fixture.activeID, fixture.work.id)
        XCTAssertEqual(fixture.state.desktopSwitchAttemptsForTesting, 0)
    }

    // MARK: - source scan (covers the automatic-switch call site in `apply`)

    /// Both call sites (`apply`'s automatic path and `performSwitch`'s manual path) must gate on
    /// `MobiusFeature.desktopSyncInScope` before touching the stored flag — not just one of them.
    /// The manual path is proven behaviourally above; this closes the loop on the automatic one
    /// without driving a real `AutoSwitchEngine` decision (which would need a fabricated exhaustion
    /// history and buys little over reading the guarded condition directly).
    func testBothDesktopSyncCallSitesAreGatedByScope() throws {
        let lines = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Mobius/AccountsState.swift")
        let autoSite = Self.gatedConditionWindow(around: "store.file.desktopAutoSwitchEnabled", in: lines)
        let manualSite = Self.gatedConditionWindow(around: "store.file.desktopSyncEnabled", in: lines)

        XCTAssertNotNil(autoSite, "couldn't find the automatic Desktop-sync call site — scan is stale")
        XCTAssertNotNil(manualSite, "couldn't find the manual Desktop-sync call site — scan is stale")
        XCTAssertTrue(autoSite?.contains("MobiusFeature.desktopSyncInScope") ?? false,
                     "apply()'s Desktop-sync branch must check the scope gate, not just the stored flag")
        XCTAssertTrue(manualSite?.contains("MobiusFeature.desktopSyncInScope") ?? false,
                     "performSwitch()'s Desktop-sync branch must check the scope gate, not just the stored flag")
    }

    /// Proves the scan above actually catches a regression rather than passing on anything
    /// (defect protocol #3) — feed it the exact *pre-fix* shape of one call site and confirm it's
    /// flagged as ungated.
    func testGatedConditionWindowRejectsTheUngatedPreFixShape() {
        let preFixLines = [
            "            // Desktop 자동 Fallback (Claude 전용): 옵션 켬 + 대상 스냅샷 존재 시에만",
            "            if provider == .claude, store.file.desktopAutoSwitchEnabled {",
            "                switchDesktopIfPossible(from: fromID, to: id)",
            "            }",
        ]
        let window = Self.gatedConditionWindow(around: "store.file.desktopAutoSwitchEnabled",
                                               in: preFixLines)
        XCTAssertNotNil(window)
        XCTAssertFalse(window?.contains("MobiusFeature.desktopSyncInScope") ?? true,
                       "the pre-fix shape has no scope gate — if this passes, the scan can't tell gated from ungated")
    }

    /// A multi-line `if` can spread its clauses across two or three source lines (both real call
    /// sites do), so "does the flag's own line mention the gate" isn't enough. This joins a small
    /// window around the match — from the nearest preceding `if`/comment run down through the line
    /// that opens the block — and lets the caller search that joined text instead.
    private static func gatedConditionWindow(around needle: String, in lines: [String]) -> String? {
        guard let hit = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
        var start = hit
        while start > 0, !lines[start].contains("if ") { start -= 1 }
        var end = hit
        while end < lines.count - 1, !lines[end].contains("{") { end += 1 }
        return lines[start...end].joined(separator: "\n")
    }

    // MARK: - fixture

    /// Two Claude accounts, active is `personal`. `work` is marked `needsReauth` so `manualSwitch`
    /// skips the network preflight (OAuth refresh) and goes straight through the real switch gate —
    /// same trick `MobiusCoexistenceGuardTests.SwitchFixture` uses, for the same reason.
    @MainActor
    private struct Fixture {
        let state: AccountsState
        let personal: AccountProfile
        let work: AccountProfile

        var activeID: UUID? { state.store.file.activeByProvider[.claude] }

        init(test: XCTestCase) throws {
            state = try MobiusTestSupport.isolatedAccountsState(
                cleanupWith: test, keychain: InMemoryKeychain())
            try FileManager.default.createDirectory(at: state.env.claudeDir,
                                                    withIntermediateDirectories: true)
            personal = try state.store.upsertProfile(
                nickname: "personal", snapshot: Self.snapshot(email: "p@x.com", token: "P0"))
            work = try state.store.upsertProfile(
                nickname: "work", snapshot: Self.snapshot(email: "w@x.com", token: "W0"))
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
