import XCTest
@testable import PokeTokenBarExtended

/// 개명(`PokeTokenBar` → `PokeTokenBarExtended`, 번들 ID 포함)이 **기존 사용자 데이터를
/// 그대로 들고 오는가.** 두 갈래가 있고 둘 다 빠지면 사용자에겐 "진행이 날아갔다"로 보인다.
///
/// 1. Application Support 디렉터리 — 도감·사용량 캐시·스프라이트·계정(`mobius/`)
/// 2. `UserDefaults` 도메인 — 난이도·갱신 주기·메뉴바 표시·플로팅 펫·계정 전환 토글
final class RenameMigrationTests: XCTestCase {

    private let fm = FileManager.default
    private var base: URL!

    override func setUpWithError() throws {
        base = fm.temporaryDirectory
            .appendingPathComponent("RenameMigrationTests-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: base)
        base = nil
    }

    // MARK: - (A) Application Support 디렉터리 체인

    private func seed(_ name: String, marker: String) throws {
        let dir = base.appendingPathComponent(name)
        try fm.createDirectory(at: dir.appendingPathComponent("mobius/secrets"),
                               withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: dir.appendingPathComponent("companion-state.json"))
        try Data(marker.utf8).write(to: dir.appendingPathComponent("mobius/accounts.json"))
    }

    private func marker(in name: String, file: String = "companion-state.json") throws -> String {
        let url = base.appendingPathComponent(name).appendingPathComponent(file)
        return String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
    }

    private var current: String { StateDirectoryMigration.currentName }

    /// 체인의 앞 항목을 지우면 그 세대 사용자의 데이터가 영영 도착하지 못한다.
    func testChainKeepsEveryGenerationWithTheCurrentNameLast() {
        XCTAssertEqual(StateDirectoryMigration.names,
                       ["TokenMac", "PokeTokenBar", "PokeTokenBarExtended"],
                       "개명 이름은 끝에만 추가한다 — 앞 항목을 지우면 그 세대가 유실된다")
        XCTAssertEqual(current, "PokeTokenBarExtended")
    }

    /// 이름이 두 곳에 따로 적히면 다음 개명에서 조용히 어긋난다.
    func testStatePathsUsesTheChainsCurrentName() throws {
        let dir = base.appendingPathComponent("state-dir-probe")
        setenv("PTB_STATE_DIR", dir.path, 1)
        defer { unsetenv("PTB_STATE_DIR") }
        XCTAssertEqual(AppStatePaths.directory().standardizedFileURL, dir.standardizedFileURL)

        let source = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Core/AppStatePaths.swift")
        XCTAssertTrue(source.contains { $0.contains("StateDirectoryMigration.currentName") },
                      "상태 디렉터리 이름은 개명 체인 한 곳에서만 온다")
    }

    func testFreshInstallHasNothingToMove() {
        XCTAssertNil(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm))
        XCTAssertFalse(fm.fileExists(atPath: base.appendingPathComponent(current).path),
                       "옮길 것이 없으면 디렉터리를 만들지도 않는다")
    }

    func testMovesThePreviousGeneration() throws {
        try seed("PokeTokenBar", marker: "ptb")

        XCTAssertEqual(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm),
                       "PokeTokenBar")
        XCTAssertEqual(try marker(in: current), "ptb")
        XCTAssertEqual(try marker(in: current, file: "mobius/accounts.json"), "ptb",
                       "계정 데이터는 mobius/ 하위라 디렉터리와 함께 따라와야 한다")
        XCTAssertFalse(fm.fileExists(atPath: base.appendingPathComponent("PokeTokenBar").path),
                       "이름변경이면 원본은 남지 않는다")
    }

    /// 아주 오래된 사용자 — `TokenMac` 이후로 앱을 한 번도 안 켠 경우. 한 번에 건너뛴다.
    func testMovesTheOldestGenerationWhenItIsTheOnlyOne() throws {
        try seed("TokenMac", marker: "tokenmac")

        XCTAssertEqual(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm),
                       "TokenMac")
        XCTAssertEqual(try marker(in: current), "tokenmac",
                       "TokenMac → PokeTokenBarExtended 로 곧장 와야 한다")
    }

    /// 두 세대가 남아 있을 수 있다 — 첫 이전이 "대상이 이미 있으면 건너뛴다" 로 게이트돼
    /// 원본을 남겼기 때문이다. 그때 오래된 쪽을 고르면 **살아 있는 진행이 옛 진행으로 되돌아간다.**
    func testPrefersTheNewestGenerationWhenSeveralRemain() throws {
        try seed("TokenMac", marker: "tokenmac")
        try seed("PokeTokenBar", marker: "ptb")

        XCTAssertEqual(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm),
                       "PokeTokenBar")
        XCTAssertEqual(try marker(in: current), "ptb")
        XCTAssertEqual(try marker(in: "TokenMac"), "tokenmac",
                       "더 오래된 세대는 건드리지 않는다 — 되돌릴 여지를 남긴다")
    }

    func testNeverOverwritesAnExistingCurrentDirectoryAndIsIdempotent() throws {
        try seed("PokeTokenBar", marker: "ptb")
        try seed(current, marker: "live")

        XCTAssertNil(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm))
        XCTAssertEqual(try marker(in: current), "live", "살아 있는 데이터를 덮으면 안 된다")

        try fm.removeItem(at: base.appendingPathComponent(current))
        XCTAssertEqual(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm),
                       "PokeTokenBar")
        XCTAssertNil(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm),
                     "두 번째 호출은 아무것도 하지 않는다")
        XCTAssertEqual(try marker(in: current), "ptb")
    }

    /// 옮기지 못하면 원본을 그대로 둔다 — 반쪽 이전(원본은 사라졌는데 대상은 없음)보다 낫고,
    /// 다음 실행에 다시 시도할 수 있다.
    func testLeavesTheSourceAloneWhenTheMoveFails() throws {
        try seed("PokeTokenBar", marker: "ptb")
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: base.path)
        addTeardownBlock { [base] in
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: base!.path)
        }

        XCTAssertNil(StateDirectoryMigration.migrateIfNeeded(base: base, fileManager: fm))
        XCTAssertEqual(try marker(in: "PokeTokenBar"), "ptb", "원본이 사라지면 복구할 길이 없다")
    }

    // MARK: - (B) UserDefaults 도메인

    private func suiteNames() -> (legacy: String, current: String) {
        let id = UUID().uuidString
        return ("ptb.rename.legacy.\(id)", "ptb.rename.current.\(id)")
    }

    private func withSuites(
        _ body: (_ defaults: UserDefaults, _ legacy: String, _ current: String) throws -> Void
    ) rethrows {
        let names = suiteNames()
        let legacyDefaults = UserDefaults(suiteName: names.legacy)!
        let currentDefaults = UserDefaults(suiteName: names.current)!
        defer {
            legacyDefaults.removePersistentDomain(forName: names.legacy)
            currentDefaults.removePersistentDomain(forName: names.current)
        }
        // 실측된 설정 중 대표 — 난이도(정수)·표시 토글(불리언)·계정 전환(mobius 접두)·
        // 사용량 캐시(Data)·메뉴바 아이콘 자리(시스템 관리 키).
        legacyDefaults.set(3, forKey: "growthDifficulty")
        legacyDefaults.set(false, forKey: "showCostInMenu")
        legacyDefaults.set(true, forKey: "mobius.enabled")
        legacyDefaults.set(Data("cache".utf8), forKey: "mobius.usageCacheV1")
        legacyDefaults.set(-142.5, forKey: "NSStatusItem Preferred Position Item-0")
        try body(currentDefaults, names.legacy, names.current)
    }

    func testCopiesEveryLegacySettingIntoTheNewDomain() throws {
        try withSuites { defaults, legacy, current in
            let copied = LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current)

            XCTAssertEqual(copied, ["NSStatusItem Preferred Position Item-0", "growthDifficulty",
                                    "mobius.enabled", "mobius.usageCacheV1", "showCostInMenu"])
            XCTAssertEqual(defaults.integer(forKey: "growthDifficulty"), 3)
            XCTAssertFalse(defaults.bool(forKey: "showCostInMenu"),
                           "false 도 '설정된 값'이다 — 기본값으로 되돌아가면 안 된다")
            XCTAssertTrue(defaults.bool(forKey: "mobius.enabled"))
            XCTAssertEqual(defaults.data(forKey: "mobius.usageCacheV1"), Data("cache".utf8))
        }
    }

    /// 메뉴바 아이콘 자리는 "시스템이 관리하는 키"지만 값의 의미는 **사용자가 끌어다 놓은
    /// 자리**다. 빼면 개명 후 아이콘이 메뉴바 끝으로 튄다.
    func testCarriesTheMenuBarIconPosition() throws {
        try withSuites { defaults, legacy, current in
            LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current)
            XCTAssertEqual(defaults.double(forKey: "NSStatusItem Preferred Position Item-0"), -142.5)
        }
    }

    func testNeverOverwritesAValueTheUserAlreadySetInTheNewDomain() throws {
        try withSuites { defaults, legacy, current in
            defaults.set(1, forKey: "growthDifficulty")

            let copied = LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current)

            XCTAssertFalse(copied.contains("growthDifficulty"))
            XCTAssertEqual(defaults.integer(forKey: "growthDifficulty"), 1,
                           "새 도메인에서 이미 고른 값이 옛 값으로 되돌아가면 안 된다")
            XCTAssertTrue(defaults.bool(forKey: "mobius.enabled"), "나머지 키는 그대로 온다")
        }
    }

    func testRunsOnlyOnceEvenAfterTheUserClearsAKey() throws {
        try withSuites { defaults, legacy, current in
            let first = LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current)
            XCTAssertFalse(first.isEmpty)

            XCTAssertEqual(LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current), [],
                "두 번째 실행은 아무것도 복사하지 않는다")

            defaults.removeObject(forKey: "mobius.enabled")
            XCTAssertEqual(LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current), [],
                "사용자가 지운 값이 다음 실행에 되살아나면 안 된다 — 부재 검사만으로는 못 막는다")
            XCTAssertFalse(defaults.bool(forKey: "mobius.enabled"))
        }
    }

    func testLeavesTheLegacyDomainIntact() throws {
        try withSuites { defaults, legacy, current in
            LegacyDefaultsDomainMigration.migrateIfNeeded(
                defaults: defaults, from: legacy, into: current)

            let remaining = defaults.persistentDomain(forName: legacy) ?? [:]
            XCTAssertEqual(remaining["growthDifficulty"] as? Int, 3,
                           "구 도메인은 지우지 않는다 — 구 번들로 되돌릴 여지를 남긴다")
            XCTAssertNil(remaining[LegacyDefaultsDomainMigration.markerKey],
                         "마커는 새 도메인에만 쓴다")
        }
    }

    func testDoesNothingWhenThereIsNoLegacyDomain() throws {
        let names = suiteNames()
        let defaults = UserDefaults(suiteName: names.current)!
        defer { defaults.removePersistentDomain(forName: names.current) }

        XCTAssertEqual(LegacyDefaultsDomainMigration.migrateIfNeeded(
            defaults: defaults, from: names.legacy, into: names.current), [])
    }

    /// 프로덕션이 읽는 구 도메인이 실제로 개명 전 번들 ID 여야 한다 — 오타면 조용히 0개 복사된다.
    func testLegacyDomainIsThePreRenameBundleIdentifier() {
        XCTAssertEqual(LegacyDefaultsDomainMigration.legacyDomainName,
                       "io.github.chattymin.poketokenbar")
    }
}
