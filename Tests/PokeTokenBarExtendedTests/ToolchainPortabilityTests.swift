import XCTest

/// The local dev toolchain and CI's `macos-15` runner drift out of sync (see
/// `docs/reference/defect-log.md` §빌드·도구체인 — a Sendable-conformance gap already broke CI once
/// this way). `isolated deinit` on a non-actor class is the sharpest recurrence of that class: it
/// only compiles from Swift 6.2 onward, so it type-checks on a newer local Xcode while failing on
/// CI's older one with an isolation error that looks unrelated to the toolchain (the report was
/// "call to main actor-isolated instance method … in a synchronous nonisolated context").
///
/// `AccountsState.swift` used to carry one as a safety net for `stop()`. It was removed once
/// dead-code analysis showed the safety net never actually fired on any reachable path (the sole
/// production instance lives for the app's whole run, and every test path already calls `stop()`
/// before the local var goes out of scope) — see the removal's comment there. This guard keeps a
/// future reintroduction of the same pattern from silently reopening the CI gap: it is caught here,
/// at the exact toolchain-sensitive construct, rather than only by pushing and waiting on CI.
final class ToolchainPortabilityTests: XCTestCase {
    func testSourcesDoNotUseIsolatedDeinit() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarExtendedTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
        let sourcesDir = repoRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sourcesDir, includingPropertiesForKeys: nil))

        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("isolated deinit") else { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertGreaterThan(scanned, 0, "the scan found no Swift sources — did Sources/ move?")
        XCTAssertTrue(offenders.isEmpty, """
            `isolated deinit` only compiles on Swift 6.2+; CI's macos-15 runner ships an older \
            toolchain and will fail with an isolation error at the call site instead of a clear \
            "unavailable" diagnostic. Restructure the deinit to stay nonisolated (touch only \
            nonisolated stored state, or drop it if `stop()`/an equivalent teardown already covers \
            every reachable deallocation path): \(offenders.joined(separator: ", "))
            """)
    }
}
