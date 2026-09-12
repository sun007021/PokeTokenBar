import Foundation

/// `claude` 실행파일의 위치·설치 여부.
///
/// 해석은 호스트 앱의 `BinaryLocator` **한 곳**에 위임한다. Mobius 에서 이식해 온 코드는
/// `zsh -lc`(비대화형)로 `command -v` 를 돌리고 출력의 첫 줄을 경로로 삼았는데, 둘 다 틀렸다 —
/// `-lc` 는 `.zshrc` 를 안 읽어 **nvm·mise 처럼 거기서만 PATH 를 받는 설치를 통째로 못 보고**
/// (실측: `~/.nvm/versions/node/<ver>/bin/claude` 를 쓰는 Mac 에서 계정 추가가
/// "Claude Code CLI 가 필요합니다" 로 막혔다), 첫 줄 파싱은 rc 가 stdout 에 찍는 장식 문구를
/// 경로로 읽는다. `BinaryLocator` 는 대화형 로그인 셸(`-ilc`)로 찾고 결과를 마커로 감싸
/// 두 함정을 구조적으로 피한다 — Codex 쪽(`CodexRateLimitsProvider`)은 이미 그 경로를 써서
/// 같은 Mac 에서 정상 동작했다.
enum ClaudeCLI {
    /// 셸을 거치지 않고 바로 잡히는 표준 설치 위치. 버전 디렉터리가 끼는 설치(nvm 의
    /// `~/.nvm/versions/node/<ver>/bin`)는 **일부러 넣지 않는다** — 버전이 올라갈 때마다
    /// 경로가 바뀌어 하드코딩이 조용히 낡는다. 그런 설치는 셸 해석이 맞는 답이다.
    static var standardPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude"]
            + BinaryLocator.commonNodeToolPaths("claude")
    }

    /// `name`·`staticPaths` 는 **테스트 주입 전용**이다 — 프로덕션 호출부는 인자를 주지 않는다.
    static func resolvedPath(name: String = "claude", staticPaths: [String]? = nil) -> String? {
        BinaryLocator.resolve(name, staticPaths: staticPaths ?? standardPaths)
    }

    static var isInstalled: Bool { resolvedPath() != nil }

    static func install(_ l: L) async -> String? {
        let script = "curl -fsSL https://claude.ai/install.sh | bash"
        guard let (code, output) = await ToolInventory.runLoginShellAsync(script) else {
            return l.accountsErrorInstallLaunchFailed
        }
        // 설치 직후 경로가 바뀌었을 수 있다 — 미탐지 캐시(TTL 10분)를 비우고 다시 본다.
        BinaryLocator.reset()
        if code == 0, isInstalled { return nil }
        let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
        return l.accountsErrorInstallFailed(code: code, detail: tail)
    }
}
