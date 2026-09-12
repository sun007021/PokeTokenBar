import Foundation

/// 앱 시작 시 Mobius 관련 초기화가 도는 **순서 계약**.
///
/// 이 순서는 취향이 아니라 데이터 보존이다 — 네 단계가 모두 "대상이 이미 있으면 건너뛴다"는
/// 판정을 쓰기 때문에, **뒤 단계가 먼저 돌아 대상을 만들어 버리면 앞 단계는 영원히 안 돈다.**
/// 두 경우 모두 사용자에게는 "데이터가 날아갔다"로 보인다.
///
/// 1. `.legacyDefaultsDomainCopy` — 구 번들 ID 의 `UserDefaults` 도메인을 현재 도메인으로
///    1회 복사. 뒤 단계들과 그 다음에 만들어지는 `UsageStore`·`CompanionStore` 가 전부
///    `UserDefaults` 를 **읽는** 쪽이라, 복사가 늦으면 그 실행에서는 설정이 전부 초기값으로
///    보인다. 특히 `.accountStateCreation` 은 `mobius.enabled` 를 읽어 엔진을 켤지 정하므로,
///    늦으면 자동 전환이 켜져 있는데도 그 실행에서는 안 돈다.
/// 2. `.legacyStorageRename` — `TokenMac`/`PokeTokenBar` → `PokeTokenBarExtended`
///    디렉터리 이름변경. `!fileExists(atPath: new.path)` 로 게이트하는데,
///    `AppStatePaths.directory()` 는 **호출만 해도** 현재 이름의 디렉터리를 만든다
///    (`createDirectory(withIntermediateDirectories:)`). 그러니 상태 디렉터리를 건드리는
///    어떤 코드도 이 단계보다 먼저 돌면 안 된다 — 옛 이름 시절 도감·토큰이 영영
///    이전되지 않는다.
/// 3. `.mobiusDataMigration` — `~/Library/Application Support/Mobius`
///    → `PokeTokenBarExtended/mobius`.
///    `alreadyMigrated` 판정이 **대상 디렉터리 존재**라서, `AccountStore` 가 먼저 저장해
///    (`save()` / `writeSecretFile`) `mobius/` 를 만들면 기존 Mobius.app 사용자의 계정·토큰
///    스냅샷이 영영 안 넘어온다.
/// 4. `.accountStateCreation` — `AccountsState` 생성, 그리고 토글이 켜졌을 때만 `start()`.
///
/// `run(_:)` 은 하드코딩된 호출 순서가 아니라 `order` 배열을 그대로 따른다 — 그래야 순서가
/// 한 곳에만 적히고, 테스트가 그 한 곳을 검증하면 프로덕션 경로까지 같이 고정된다.
enum MobiusLaunchSequence {

    enum Step: String, CaseIterable {
        /// 구 번들 ID 도메인 → 현재 도메인 `UserDefaults` 1회 복사
        case legacyDefaultsDomainCopy
        /// `TokenMac` → `PokeTokenBar` → `PokeTokenBarExtended` 디렉터리 이름변경 체인
        case legacyStorageRename
        /// 독립 Mobius.app 데이터 1회 복사
        case mobiusDataMigration
        /// `AccountsState` 생성 + 조건부 `start()`
        case accountStateCreation
    }

    /// 단일 진실. 새 단계를 더하면 여기에 자리를 정해 넣어야 한다
    /// (`MobiusLaunchSequenceTests` 가 `Step.allCases` 전수 포함을 강제한다).
    static let order: [Step] = [
        .legacyDefaultsDomainCopy, .legacyStorageRename, .mobiusDataMigration, .accountStateCreation,
    ]

    static func run(_ perform: (Step) -> Void) {
        for step in order { perform(step) }
    }
}
