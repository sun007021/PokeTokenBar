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
}
