import AppKit

/// 기존 **Mobius.app 과의 공존 판정.**
///
/// 계정 전환이 건드리는 것들 — Keychain `Claude Code-credentials`, `~/.claude.json`,
/// `~/.claude/.credentials.json`, `~/.codex/auth.json` — 은 전부 **전역 자원**이다. 이 포크는
/// 자기 상태(`accounts.json`·비밀 스냅샷)만 `PokeTokenBar/mobius/` 로 갈라 놓았을 뿐,
/// 스왑 대상은 원본 Mobius.app 과 **같은 파일·같은 키체인 항목**이다.
///
/// 두 프로세스가 그 자원을 동시에 스왑하면 원본의 '실패 기록 1' 이 그대로 재현된다 —
/// 토큰(Keychain)과 이메일(`~/.claude.json`)이 서로 다른 시점에 갱신되는 찰나를 상대가 읽어
/// **낡은 토큰 + 최신 이메일**이 한 프로필에 짝지어지고, 사용자의 라이브 로그인까지 오염된다.
/// 실패가 예외나 에러 메시지로 나타나지 않는 것이 이 부류의 핵심이다 — 조용히 망가진 다음
/// `claude` 가 `Login expired` 를 뱉을 때에야 드러난다.
///
/// 그래서 **감지되면 이 앱이 물러난다**(`SingleInstance` 와 같은 방향의 결정: 동시 접근은
/// 조정하는 것이 아니라 하나로 줄인다). 어느 쪽이 먼저 떴는지는 보지 않는다 — 원본 Mobius.app
/// 에는 이 협상에 참여할 코드가 없으므로, 양보를 아는 쪽이 항상 양보해야 한 명만 남는다.
enum MobiusCoexistence {
    /// 원본 Mobius.app 의 번들 ID (`Scripts/make-app.sh` 기준).
    static let mobiusBundleID = "dev.chussum.mobius"

    /// 판정의 입력. `NSRunningApplication` 을 테스트에서 만들 수 없어(실제 프로세스가 필요하다)
    /// 판정이 쓰는 두 필드만 값으로 옮긴다 — `SingleInstance.shouldYield(myStartTime:…)` 가
    /// 커널 조회와 판정을 갈라 둔 것과 같은 분리다.
    struct ExternalInstance: Equatable {
        let bundleID: String
        let isTerminated: Bool
    }

    /// 순수 판정 — 살아 있는 Mobius.app 인스턴스가 하나라도 있으면 막는다.
    ///
    /// `isTerminated` 를 보는 이유: `NSRunningApplication` 객체는 프로세스가 죽은 뒤에도
    /// 잠시 살아 있고 그때 `isTerminated == true` 가 된다. 그걸 세면 Mobius.app 을 종료한
    /// 사용자가 "왜 아직도 멈춰 있나"를 겪는다 — **자동 재개가 이 한 줄에 달려 있다.**
    static func isBlocked(by instances: [ExternalInstance]) -> Bool {
        instances.contains { $0.bundleID == mobiusBundleID && !$0.isTerminated }
    }

    /// 판정의 입력을 실제로 읽어 온다 — `SingleInstance.shouldYieldToRunningInstance()` 와 같은
    /// `NSRunningApplication` 경로. 런치 서비스가 프로세스 목록을 캐시하므로 값싸다(주기 호출용).
    @MainActor
    static func runningInstances() -> [ExternalInstance] {
        NSRunningApplication.runningApplications(withBundleIdentifier: mobiusBundleID)
            .map { ExternalInstance(bundleID: $0.bundleIdentifier ?? mobiusBundleID,
                                    isTerminated: $0.isTerminated) }
    }

    /// `AccountsState` 가 주입받는 기본 감지기.
    @MainActor
    static func isExternalMobiusRunning() -> Bool {
        isBlocked(by: runningInstances())
    }

    /// `NSWorkspace` 실행/종료 알림이 우리가 지켜보는 앱에 대한 것인가 — 시스템의 모든 앱
    /// 실행·종료마다 LaunchServices 를 다시 조회하지 않기 위한 값싼 사전 필터다.
    ///
    /// ★ 번들 ID 를 못 읽으면 **보수적으로 참**이다. 이 필터가 틀리는 두 방향의 대가가 대칭이
    /// 아니다 — 남의 앱 때문에 한 번 더 조회하는 비용은 무의미하지만, Mobius.app 알림을
    /// 놓치면 두 앱이 같은 Keychain·`~/.claude.json` 을 스왑해 라이브 로그인이 **에러 없이**
    /// 오염된다.
    static func notificationConcernsMobius(bundleID: String?) -> Bool {
        bundleID == nil || bundleID == mobiusBundleID
    }
}
