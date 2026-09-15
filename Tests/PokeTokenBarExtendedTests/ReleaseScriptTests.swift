import XCTest

/// `scripts/release.sh` 는 릴리스 머신에서만 끝까지 돈다 — 서명 신원·공증 자격이 없는 CI 에서
/// 실행으로는 못 잡는 결함을 소스 스캔으로 막는다 (`docs/reference/defect-log.md` §빌드·도구체인).
final class ReleaseScriptTests: XCTestCase {
    private func releaseScript() throws -> [String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarExtendedTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
        return try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// Developer ID 신원 이름에는 항상 `(TEAMID)` 괄호가 들어간다. awk `~` 는 그 괄호를 정규식
    /// 그룹으로 읽어 유효한 신원을 "없음"으로 판정한다(v1.0.0 릴리스가 3/9 단계에서 멈춘 원인).
    func testSigningIdentityLookupMatchesTheNameLiterally() throws {
        let lookups = try releaseScript().enumerated()
            .filter { $0.element.contains("find-identity") && $0.element.contains("awk") }

        XCTAssertFalse(lookups.isEmpty, "no signing identity lookup found — did release.sh change shape?")
        for (index, line) in lookups {
            XCTAssertFalse(
                line.contains("~ id"),
                "release.sh:\(index + 1) matches the identity as a regex; `(TEAMID)` becomes a group — use index($0, id)")
            XCTAssertTrue(
                line.contains("index($0, id)"),
                "release.sh:\(index + 1) should match the identity literally with index($0, id)")
        }
    }

    /// `set -o pipefail` 아래에서 파이프 끝 reader 가 입력을 다 읽기 전에 끝나면(`grep -q`,
    /// `awk '… exit'`) 앞 명령이 SIGPIPE(141)로 죽고 파이프라인 전체가 실패가 된다 — hardened
    /// runtime 이 켜진 앱을 "꺼져 있다"로 판정해 v1.0.0 릴리스가 5/9 단계에서 멈춘 원인.
    func testPipelineReadersConsumeAllInputUnderPipefail() throws {
        let lines = try releaseScript()
        XCTAssertTrue(
            lines.contains { $0.hasPrefix("set -") && $0.contains("pipefail") },
            "release.sh no longer sets pipefail — revisit whether this guard still applies")

        let earlyExitReader = try NSRegularExpression(
            pattern: #"\|\s*(grep\s+-[A-Za-z]*q|awk\b.*\bexit\b)"#)
        var offenders: [String] = []
        for (index, line) in lines.enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if earlyExitReader.firstMatch(in: line, range: range) != nil {
                offenders.append("release.sh:\(index + 1)")
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            a pipeline reader stops before EOF, so the writer dies with SIGPIPE and pipefail \
            reports a false failure. Use `grep … >/dev/null` or an awk flag instead of `exit`: \
            \(offenders.joined(separator: ", "))
            """)
    }
}
