import Foundation

/// 계정 전환(Mobius) 기능의 마스터 토글 — **기본 꺼짐**.
///
/// 꺼져 있으면 `AccountsState.start()` 를 부르지 않는다. `start()` 가 타이머·세션 로그 스캔·
/// Keychain 워밍업·알림 권한 요청·외부 변경 옵저버의 **유일한** 진입점이므로, 꺼진 상태의
/// 런타임 동작은 기능을 넣기 전과 같다.
///
/// 토글 UI 는 Phase 5 다. 지금은 키를 읽기만 한다 —
/// `defaults write io.github.chattymin.poketokenbar mobius.enabled -bool YES` 로 수동 확인 가능.
enum MobiusFeature {
    static let enabledKey = "mobius.enabled"

    /// 미설정이면 `false` (`UserDefaults.bool(forKey:)` 의 기본값).
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }
}
