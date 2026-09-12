import XCTest
@testable import MobiusCore
@testable import PokeTokenBar

/// `UNUserNotificationCenter.current()` raises `NSInternalInconsistencyException`
/// ("bundleProxyForCurrentProcess is nil") whenever the process is not a bundled
/// `.app`. PokeTokenBar therefore keeps every notification touch behind
/// `AppEnv.isBundledApp` (`UsageStore`, `CompanionStore`, `AppLog`); the ported
/// Mobius code did not, and `-mobius.enabled YES ./.build/debug/PokeTokenBar`
/// died inside `AccountsState.start()` before the menu bar item appeared.
///
/// `swift test` is itself an unbundled process, so these tests hit the real
/// trigger: delete either guard and they raise, rather than merely asserting
/// that the word "isBundledApp" appears somewhere.
@MainActor
final class MobiusBundleGuardTests: XCTestCase {
    /// Every path is synthetic, and `localUser` is a name no keychain item carries,
    /// so the credential warm-up inside `start()` resolves to "item not found"
    /// (`security … -a <bogus>` exits 44) instead of reading the real login.
    /// Lifted to `MobiusTestSupport` once a second suite needed the same guarantee.
    private func isolatedState() throws -> AccountsState {
        try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
    }

    func testAppEnvReportsThisProcessAsUnbundled() {
        XCTAssertFalse(AppEnv.isBundledApp,
                       "the two tests below only reach the trigger while the test host is unbundled")
    }

    /// The reported crash: `start()` asked for notification authorization before
    /// installing the tick timer, so the app died on launch from a raw binary.
    func testStartSurvivesOutsideABundle() throws {
        let state = try isolatedState()
        state.start()
        state.stop()
    }

    /// The second site. All 22 notification call sites funnel through `notify`,
    /// so guarding it once covers `재로그인 필요`, `한도 소진`, external-change
    /// notices and the rest — each of which fires from a timer tick, i.e. without
    /// any user action.
    func testNotifySurvivesOutsideABundle() throws {
        let state = try isolatedState()
        state.notify(title: "guard", body: "must not reach UNUserNotificationCenter")
    }

    /// Future additions: a new `UNUserNotificationCenter` reference inside
    /// `Sources/PokeTokenBar/Mobius/` must sit behind the same gate. The two
    /// tests above only cover the functions they call; this covers the class.
    func testEveryNotificationCenterUseInMobiusSourcesIsGuarded() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar/Mobius")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var checked = 0

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (index, line) in lines.enumerated() {
                guard line.contains("UNUserNotificationCenter"), !Self.isComment(line) else { continue }
                checked += 1
                if !Self.isGuardedByBundleCheck(lines: lines, useIndex: index) {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }

        XCTAssertGreaterThan(checked, 0, "the scan found no notification use — did the sources move?")
        XCTAssertTrue(offenders.isEmpty, """
            UNUserNotificationCenter raises outside a bundled .app, which kills the raw-binary \
            dev run (`swift run`) on launch. Put these behind AppEnv.isBundledApp, the same gate \
            UsageStore/CompanionStore/AppLog use: \(offenders.joined(separator: ", "))
            """)
    }

    /// Walk back to the enclosing `func` and require the gate somewhere between
    /// it and the use. Scanning the whole file would pass on an unrelated guard
    /// in a neighbouring function.
    private static func isGuardedByBundleCheck(lines: [String], useIndex: Int) -> Bool {
        var index = useIndex
        while index >= 0 {
            let line = lines[index]
            if index != useIndex, !isComment(line), line.contains("AppEnv.isBundledApp") { return true }
            if line.contains("func "), !isComment(line) { return false }
            index -= 1
        }
        return false
    }

    private static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }
}
