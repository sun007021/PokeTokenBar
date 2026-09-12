import Foundation

/// 계정 전환(Mobius) 기능의 마스터 토글 — **기본 꺼짐** — 과 그 하위 설정 키들.
///
/// 꺼져 있으면 `AccountsState.start()` 를 부르지 않는다. `start()` 가 타이머·세션 로그 스캔·
/// Keychain 워밍업·알림 권한 요청·외부 변경 옵저버의 **유일한** 진입점이므로, 꺼진 상태의
/// 런타임 동작은 기능을 넣기 전과 같다. 설정에서 끄면 `AccountsState.stop()` 이 같은 것들을
/// 도로 걷어간다 (`SettingsView.accountSwitchingGroup`).
///
/// 키를 여기 모아 두는 이유: 같은 키를 UI(`@AppStorage`)와 엔진(`UserDefaults.standard`)이
/// 각자 문자열 리터럴로 적으면 오타 하나가 **조용히** 설정 두 개로 갈라진다 — 토글은 꺼졌는데
/// 폴링은 도는 상태가 되고, 컴파일도 테스트도 그걸 못 잡는다.
enum MobiusFeature {
    /// 마스터 토글. 미설정이면 `false` (`UserDefaults.bool(forKey:)` 의 기본값).
    static let enabledKey = "mobius.enabled"
    /// 계정 카드에 사용량 게이지를 그릴지 — **미설정이면 켬**(아래 `showUsageGauges`).
    static let showUsageGaugesKey = "mobius.showUsageGauges"
    /// '한도 차기 전 미리 전환'. 켜면 활성 Claude 계정 usage 를 5분마다 폴링하므로 기본 꺼짐.
    static let advisorySwitchEnabledKey = "mobius.advisorySwitchEnabled"
    /// 위 기능의 임계값(%). 설정 UI 범위 50~95(step 5), 기본 90.
    static let advisoryThresholdPercentKey = "mobius.advisoryThresholdPercent"

    /// 미설정이면 `false`.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 게이지 표시 기본값은 **켬**이라 `bool(forKey:)` 하나로는 안 된다(미설정이 false 가 된다).
    static var showUsageGauges: Bool {
        UserDefaults.standard.object(forKey: showUsageGaugesKey) == nil
            || UserDefaults.standard.bool(forKey: showUsageGaugesKey)
    }

    /// 설정 픽커가 고를 수 있는 임계값 — 엔진 기본값(`advisoryThresholdDefault`)이 이 안에
    /// 있어야 미설정 상태에서 픽커가 '선택 없음'으로 열리지 않는다.
    static let advisoryThresholdChoices: [Int] = Array(stride(from: 50, through: 95, by: 5))
    static let advisoryThresholdDefault = 90

    /// Desktop 동시 전환은 1차 범위 밖이다 (`docs/reference/mobius-integration.md` §결정 사항 —
    /// "Desktop 동시 전환/멀티 Mac 동기화 UI 제외"). 이 상수가 `AccountsState.performSwitch`/
    /// `apply` 의 호출부를 **저장된 값과 무관하게** 막는다.
    ///
    /// ★ 반드시 이렇게 막아야 하는 이유: `AccountsFile.desktopSyncEnabled` 는 지속화 필드로
    /// 기본값이 **`true`** 다(Mobius 본체가 그렇게 설계했다). "UI 를 안 붙이면 꺼진 채로 잠든다"는
    /// 가정은 틀렸다 — 이 필드는 껐다 켜는 UI 가 아예 없어도 `true` 로 저장돼 있으면 수동 전환마다
    /// 실행된다. 실측: 이 저장소 사용자의 실제 `accounts.json` 에 이미 `desktopSyncEnabled: true`
    /// 가 들어 있었고(구 Mobius.app 이 그렇게 저장했다), Desktop 스냅샷(`desktop-profiles/`)은
    /// 하나도 캡처돼 있지 않았다 — 이 조합에서 계정 카드를 눌러 수동 전환하면
    /// `switchDesktopIfPossible` 이 미캡처 계정으로의 전환으로 읽어 **Claude Desktop 을 종료하고
    /// 로그아웃시킨다**(경고 없음, 되돌릴 UI 없음). `setDesktopSync(_:)`/`setDesktopAutoSwitch(_:)`
    /// 는 어떤 View 에서도 호출되지 않으므로 사용자에게는 끌 방법이 없었다.
    /// → 기본값을 바꾸거나 마이그레이션으로 껐다면 **이미 저장된 `true`** 는 그대로 남아 무력화되지
    /// 않는다. 호출부 자체를 이 상수로 막으면 저장값·기본값이 무엇이든(과거 파일도, 상류 재이식도)
    /// 안전하다. UI 와 함께 노출할 때는 이 상수 하나만 지우면 저장값이 그대로 되살아난다.
    static let desktopSyncInScope = false
}
