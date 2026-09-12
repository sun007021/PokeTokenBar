import XCTest
@testable import PokeTokenBar

/// `claude` 실행파일 탐색 — 계정 추가가 "Claude Code CLI 가 필요합니다" 로 막힌 결함의 회귀 가드.
///
/// 결함의 조건은 **버전매니저 설치**다: `~/.nvm/versions/node/<ver>/bin/claude` 는 고정 후보
/// 목록에 없고, 그 디렉터리를 PATH 에 넣는 것은 `.zshrc` 뿐이다. 이식된 구현이
/// `zsh -lc`(비대화형, `.zshrc` 미소싱)를 썼기 때문에 설치돼 있는 claude 가 없는 것으로 보였다.
/// 여기서는 그 조건을 **셸 스텁**으로 재현한다 — 개발자 Mac 의 실제 설치·실제 `.zshrc` 에
/// 의존하면 머신마다 판정이 갈려 아무것도 못 지킨다.
final class ClaudeCLIResolutionTests: XCTestCase {

    private var savedShell: String?

    override func setUp() {
        super.setUp()
        savedShell = ProcessInfo.processInfo.environment["SHELL"]
        BinaryLocator.reset()
    }

    override func tearDown() {
        if let savedShell { setenv("SHELL", savedShell, 1) } else { unsetenv("SHELL") }
        BinaryLocator.reset()
        super.tearDown()
    }

    // MARK: 픽스처

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-cli-resolution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    @discardableResult
    private func writeExecutable(_ url: URL, _ body: String) throws -> URL {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// `.zshrc` 가 하는 두 가지를 흉내 내는 셸: (1) PATH 에 버전매니저 디렉터리를 더하고,
    /// (2) stdout 에 장식 문구를 찍는다(사용자 실측 출력이 ANSI 색이 들어간 `exec zsh` 였다).
    /// 인자 규약은 `BinaryLocator` 가 쓰는 `-ilc <script> sh <args...>` 그대로다.
    private func installStubShell(pathDir: URL?, decorate: Bool = true) throws {
        let dir = try makeTempDir()
        let shell = dir.appendingPathComponent("stub-zsh")
        let exportLine = pathDir.map { "PATH=\"\($0.path):$PATH\"; export PATH\n" } ?? ""
        let decoration = decorate ? "printf '\\033[32mexec zsh\\033[39m\\n'\n" : ""
        try writeExecutable(shell, """
        #!/bin/sh
        \(decoration)\(exportLine)shift
        script=$1
        shift
        exec /bin/sh -c "$script" "$@"
        """)
        setenv("SHELL", shell.path, 1)
    }

    // MARK: 결함 재현

    func testFindsACLIThatOnlyTheInteractiveLoginShellPATHExposes() throws {
        let installDir = try makeTempDir()
        let name = "ptb-fake-cli-\(UUID().uuidString.prefix(8))"
        let binary = try writeExecutable(installDir.appendingPathComponent(name),
                                         "#!/bin/sh\nexit 0\n")
        try installStubShell(pathDir: installDir)

        // 고정 후보 목록에는 없다(nvm 처럼 버전 디렉터리가 끼는 설치) — 셸 해석만이 답이다.
        XCTAssertEqual(ClaudeCLI.resolvedPath(name: name, staticPaths: []), binary.path,
                       "`.zshrc` 에서만 PATH 를 받는 설치를 못 보면 설치된 CLI 가 '없음' 이 된다")
    }

    func testProfileDecorationOnStdoutIsNotMistakenForThePath() throws {
        let installDir = try makeTempDir()
        let name = "ptb-fake-cli-\(UUID().uuidString.prefix(8))"
        let binary = try writeExecutable(installDir.appendingPathComponent(name),
                                         "#!/bin/sh\nexit 0\n")
        try installStubShell(pathDir: installDir, decorate: true)

        let resolved = ClaudeCLI.resolvedPath(name: name, staticPaths: [])
        XCTAssertEqual(resolved, binary.path)
        XCTAssertFalse(resolved?.contains("exec zsh") ?? false,
                       "rc 장식 문구가 경로로 읽히면 실행 불가 경로가 나와 CLI 가 '없음' 이 된다")
    }

    func testStandardInstallPathIsFoundWithoutConsultingTheShell() throws {
        let installDir = try makeTempDir()
        let name = "ptb-fake-cli-\(UUID().uuidString.prefix(8))"
        let binary = try writeExecutable(installDir.appendingPathComponent(name),
                                         "#!/bin/sh\nexit 0\n")
        // 셸을 물으면 실패하는 스텁 — 고정 경로로 끝나는 흔한 경로가 셸 비용을 안 문다는 보증.
        let dir = try makeTempDir()
        let shell = dir.appendingPathComponent("failing-shell")
        try writeExecutable(shell, "#!/bin/sh\nexit 1\n")
        setenv("SHELL", shell.path, 1)

        XCTAssertEqual(ClaudeCLI.resolvedPath(name: name, staticPaths: [binary.path]), binary.path)
    }

    func testMissingCLIStillResolvesToNil() throws {
        let name = "ptb-fake-cli-\(UUID().uuidString.prefix(8))"
        try installStubShell(pathDir: nil)   // PATH 에 아무것도 더하지 않는다

        XCTAssertNil(ClaudeCLI.resolvedPath(name: name, staticPaths: []),
                     "없는 CLI 를 있다고 하면 로그인 창이 뜬 채 아무 일도 안 일어난다")
    }

    // MARK: 부류 스윕 — 같은 해석기를 쓰는지

    func testAccountSwitchingResolvesBinariesThroughTheSharedLocator() throws {
        for file in ["Sources/PokeTokenBar/Mobius/ClaudeCLI.swift",
                     "Sources/PokeTokenBar/Mobius/LoginFlow.swift",
                     "Sources/PokeTokenBar/Mobius/ToolInventory.swift"] {
            let lines = try MobiusTestSupport.sourceLines(of: file)
            for (index, line) in lines.enumerated() where !MobiusTestSupport.isComment(line) {
                XCTAssertFalse(line.contains("command -v"),
                               "\(file):\(index + 1) — 실행파일 탐색은 BinaryLocator 한 곳이다")
            }
        }
    }
}
