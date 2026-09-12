import Foundation

/// 번들 ID 가 바뀌면 `UserDefaults` 도메인이 통째로 갈린다 — 구 도메인의 값은 디스크에
/// 그대로 남지만 새 도메인에서는 하나도 안 보여, 사용자에게는 **설정이 전부 초기화된 것**
/// 으로 나타난다(난이도·갱신 주기·메뉴바 표시 항목·플로팅 펫·계정 전환 토글 등).
///
/// 그래서 개명 첫 실행에 구 도메인의 값을 새 도메인으로 **1회 복사**한다.
///
/// ## 규칙
///
/// - **덮어쓰지 않는다.** 새 도메인에 이미 값이 있는 키는 건너뛴다. 사용자가 새 앱에서
///   먼저 고친 값이 옛 값으로 되돌아가는 것보다, 옛 값 하나를 놓치는 편이 낫다.
/// - **구 도메인은 지우지 않는다.** 되돌릴 여지를 남긴다(구 번들을 다시 쓰면 그대로 보인다).
/// - **1회 마커**(`markerKey`)로 끝낸다. 키 부재 검사만으로도 멱등이지만, 그것만 쓰면
///   사용자가 새 도메인에서 어떤 키를 *지운* 뒤 다음 실행에 옛 값이 되살아난다.
/// - **키를 고르지 않고 전부 옮긴다.** `NSStatusItem Preferred Position …` 같은 시스템
///   관리 키도 포함한다 — 그건 "사용자가 메뉴바 아이콘을 끌어다 놓은 자리"이고, 빼면
///   아이콘 위치가 리셋된다. 이 도메인에 macOS 가 넣는 키(상태 아이템 위치, 창 프레임,
///   파일 패널 상태)는 어느 것도 앱 번들 경로나 코드 정체성을 담지 않아 그대로 유효하다.
///   화이트리스트를 두면 반대로 **설정을 하나 추가할 때마다 여기를 고쳐야** 하고,
///   빠뜨리면 조용히 유실된다.
enum LegacyDefaultsDomainMigration {

    /// 개명 전 번들 ID. 이 포크가 갈라져 나온 상류(`chattymin/PokeTokenBar`)의 도메인이다.
    static let legacyDomainName = "io.github.chattymin.poketokenbar"

    /// "이 이전은 이미 돌았다" 마커. `mobius.` 처럼 접두사를 붙여 상류 키와 섞이지 않게 한다.
    static let markerKey = "ptb.legacyDefaultsDomainMigratedV1"

    /// 순수 판정 — 실제로 복사할 키·값. IO 없이 단언할 수 있게 분리했다.
    static func pendingCopies(
        legacy: [String: Any], current: [String: Any]
    ) -> [String: Any] {
        guard current[markerKey] == nil else { return [:] }   // 이미 1회 돌았다
        var copies: [String: Any] = [:]
        for (key, value) in legacy where key != markerKey && current[key] == nil {
            copies[key] = value
        }
        return copies
    }

    /// 구 도메인 → 현재 도메인 1회 복사.
    ///
    /// - Parameters:
    ///   - defaults: 쓰기 대상. 프로덕션은 `.standard`, 테스트는 임시 suite.
    ///   - legacyDomainName: 읽어 올 구 도메인.
    ///   - currentDomainName: 현재 도메인(= 번들 ID, 테스트에서는 suite 이름).
    /// - Returns: 실제로 복사한 키(정렬). 아무것도 안 했으면 빈 배열.
    @discardableResult
    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        from legacyDomainName: String = legacyDomainName,
        into currentDomainName: String? = Bundle.main.bundleIdentifier
    ) -> [String] {
        guard let currentDomainName else { return [] }
        let current = defaults.persistentDomain(forName: currentDomainName) ?? [:]
        guard current[markerKey] == nil else { return [] }

        let legacy = defaults.persistentDomain(forName: legacyDomainName) ?? [:]
        let copies = pendingCopies(legacy: legacy, current: current)
        // 도메인 통째 교체(`setPersistentDomain`)가 아니라 키 단위 쓰기다 — 같은 순간
        // 다른 곳이 쓴 키를 되돌리지 않는다.
        for (key, value) in copies { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: markerKey)
        return copies.keys.sorted()
    }
}
