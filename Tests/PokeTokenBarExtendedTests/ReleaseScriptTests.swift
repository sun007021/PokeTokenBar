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
}
