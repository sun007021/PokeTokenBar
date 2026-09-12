import Foundation

/// Claude Code CLI(`claude`) 설치 감지 및 설치. Mobius는 CLI로 로그인/전환하므로
/// CLI가 없으면 계정 추가를 못 한다 — 설정 '설치 현황'에서 상태를 보여주고 설치를 돕는다.
/// 감지 로직은 ToolInventory.locateCLI 공유 (로그인 셸 PATH + 알려진 경로 폴백).
enum ClaudeCLI {
    typealias Info = ToolInventory.CLIInfo

    static func locate() -> Info? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ToolInventory.locateCLI("claude", fallbackPaths: [
            "\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude",
        ])
    }

    static var isInstalled: Bool { locate() != nil }

    /// 공식 네이티브 설치 스크립트로 설치 (node 불필요, ~/.local/bin/claude에 설치).
    /// 성공 시 nil, 실패 시 에러 메시지.
    /// - Parameter l: 실패 문구용 현지화. 이 계층은 뷰가 아니라 `companion.l` 에 닿지 못하므로
    ///   호출부(뷰 또는 `AccountsState`)가 자기 `L` 을 넘긴다.
    static func install(_ l: L) async -> String? {
        // 설치 스크립트는 홈 아래에 쓰므로 관리자 권한 불필요.
        let script = "curl -fsSL https://claude.ai/install.sh | bash"
        guard let (code, output) = await ToolInventory.runLoginShellAsync(script) else {
            return l.accountsErrorInstallLaunchFailed
        }
        if code == 0, isInstalled { return nil }
        let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
        return l.accountsErrorInstallFailed(code: code, detail: tail)
    }
}
