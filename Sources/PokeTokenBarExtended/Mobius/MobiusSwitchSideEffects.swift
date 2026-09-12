import MobiusCore

/// 계정 전환이 **호스트 앱** 에 남기는 뒤처리의 판정.
///
/// 전환 자체는 `AccountsState` 가 하지만, 그 결과로 낡아지는 것은 호스트 앱 쪽 캐시다 —
/// 두 세계가 서로를 모르는 채로 두기 위해 판정만 여기 값으로 꺼내 두고, 실행은 둘 다 들고 있는
/// `AppDelegate` 가 한다.
enum MobiusSwitchSideEffects {
    /// 이 전환이 호스트 앱의 Claude 자격증명 캐시(`OAuthAccessTokenCache`)를 낡게 만드는가.
    ///
    /// Claude 한도는 그 캐시가 들고 있는 액세스 토큰으로 조회한다. 전환 뒤 캐시를 그대로 두면
    /// **A 계정 숫자를 B 계정 게이지로 보여 주는 조용한 거짓말**이 된다 — 조회가 실패하는 것이
    /// 아니라 성공한 옛 값이 그대로 그려지므로 화면만 봐서는 알 수 없다.
    ///
    /// Codex 는 해당 없다: 호스트 앱의 Codex 한도는 `~/.codex/sessions` 로그에서 읽으므로
    /// 이 캐시를 거치지 않는다. 프로바이더를 안 가르면 Codex 카드를 누를 때마다 Claude 한도
    /// 재조회가 따라붙는다.
    static func invalidatesClaudeLimitCache(_ provider: Provider) -> Bool {
        provider == .claude
    }
}
