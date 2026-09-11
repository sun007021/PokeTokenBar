import XCTest
@testable import PokeTokenBar

/// 앱 시작 시 Mobius 초기화 **순서**를 못 박는다.
///
/// 순서 단언만 하는 테스트는 "왜 그 순서여야 하는지"를 증명하지 못하므로, 여기서는 각 순서를
/// **실제 파일 연산으로 재생**하고 데이터가 실제로 넘어왔는지를 본다:
///   - 레거시 이름변경은 프로덕션 함수 `AppDelegate.migrateLegacyStorageIfNeeded(base:)`
///   - Mobius 데이터 이전은 프로덕션 함수 `MobiusDataMigration.migrateIfNeeded(source:)`
///   - 상태 디렉터리 생성은 프로덕션 함수 `AppStatePaths.directory()` (호출만으로 디렉터리가 생긴다)
/// 이 셋은 `PTB_STATE_DIR` 로 임시 디렉터리에 격리해 돌린다 — 실제
/// `~/Library/Application Support` 는 건드리지 않는다.
final class MobiusLaunchSequenceTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var appSupport: URL!
    private var mobiusSource: URL!

    private var legacyDir: URL { appSupport.appendingPathComponent("TokenMac") }
    private var stateDir: URL { appSupport.appendingPathComponent("PokeTokenBar") }
    private var migratedPokedex: URL { stateDir.appendingPathComponent("companion-state.json") }
    private var migratedAccounts: URL { stateDir.appendingPathComponent("mobius/accounts.json") }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MobiusLaunchSequenceTests-\(UUID().uuidString)")
        appSupport = root.appendingPathComponent("Application Support")
        mobiusSource = appSupport.appendingPathComponent("Mobius")
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        // 상류 PokeTokenBar(구 TokenMac) 사용자의 도감 — 이름변경 단계가 살려야 하는 데이터.
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try Data("pokedex".utf8).write(to: legacyDir.appendingPathComponent("companion-state.json"))

        // 독립 Mobius.app 사용자의 계정 — 데이터 이전 단계가 살려야 하는 데이터.
        try fm.createDirectory(at: mobiusSource.appendingPathComponent("secrets"),
                               withIntermediateDirectories: true)
        try Data("{\"accounts\":[]}".utf8)
            .write(to: mobiusSource.appendingPathComponent("accounts.json"))
        try Data("secret-a".utf8)
            .write(to: mobiusSource.appendingPathComponent("secrets/a.json"))

        // AppStatePaths.directory() 가 여기에 상태 디렉터리를 만든다(= 프로덕션 기본 경로와 같은 모양).
        setenv("PTB_STATE_DIR", stateDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("PTB_STATE_DIR")
        try? fm.removeItem(at: root)
        root = nil
        appSupport = nil
        mobiusSource = nil
    }

    /// 한 단계를 프로덕션과 같은 연산으로 재생한다.
    private func perform(_ step: MobiusLaunchSequence.Step) {
        switch step {
        case .legacyStorageRename:
            AppDelegate.migrateLegacyStorageIfNeeded(base: appSupport, fileManager: fm)
        case .mobiusDataMigration:
            _ = try? MobiusDataMigration.migrateIfNeeded(source: mobiusSource, fileManager: fm)
        case .accountStateCreation:
            // `AccountsState` 생성이 하는 일 중 **순서에 영향을 주는 부분**만 재생한다:
            // 상태 디렉터리 확보(AppStatePaths.directory())와 그 하위 `mobius/` 로의 첫 저장
            // (AccountStore.save()/writeSecretFile 이 `createDirectory` 로 만든다).
            let dir = AppStatePaths.directory()
            let mobius = dir.appendingPathComponent("mobius")
            try? fm.createDirectory(at: mobius, withIntermediateDirectories: true)
            try? Data("{\"accounts\":[]}".utf8).write(to: mobius.appendingPathComponent("accounts.json"))
        }
    }

    private func runLaunch(_ steps: [MobiusLaunchSequence.Step]) {
        for step in steps { perform(step) }
    }

    // MARK: 계약

    func testDeclaredOrderCoversEveryStepExactlyOnce() {
        XCTAssertEqual(Set(MobiusLaunchSequence.order), Set(MobiusLaunchSequence.Step.allCases),
                       "새 단계를 더했으면 order 배열에 자리를 정해 넣어야 한다")
        XCTAssertEqual(MobiusLaunchSequence.order.count, MobiusLaunchSequence.Step.allCases.count,
                       "같은 단계를 두 번 돌리면 안 된다")
    }

    func testRunExecutesStepsInTheDeclaredOrder() {
        var executed: [MobiusLaunchSequence.Step] = []
        MobiusLaunchSequence.run { executed.append($0) }
        XCTAssertEqual(executed, MobiusLaunchSequence.order,
                       "run 은 하드코딩된 호출 순서가 아니라 order 를 따라야 한다")
    }

    /// 계약 순서로 돌리면 **두 데이터가 모두** 넘어온다.
    /// `MobiusLaunchSequence.order` 를 뒤집으면 이 테스트가 빨간불이 된다(주입 검증 완료).
    func testDeclaredOrderMigratesBothLegacyPokedexAndMobiusAccounts() throws {
        runLaunch(MobiusLaunchSequence.order)

        XCTAssertEqual(try Data(contentsOf: migratedPokedex), Data("pokedex".utf8),
                       "TokenMac 시절 도감이 PokeTokenBar 로 넘어와야 한다")
        XCTAssertFalse(fm.fileExists(atPath: legacyDir.path), "이름변경이면 원본은 남지 않는다")
        XCTAssertEqual(try Data(contentsOf: migratedAccounts), Data("{\"accounts\":[]}".utf8),
                       "기존 Mobius.app 계정이 PokeTokenBar/mobius 로 넘어와야 한다")
        XCTAssertEqual(
            try Data(contentsOf: stateDir.appendingPathComponent("mobius/secrets/a.json")),
            Data("secret-a".utf8), "비밀 스냅샷도 함께 넘어와야 한다")
    }

    // MARK: 함정 1 — 상태 디렉터리를 먼저 만들면 레거시 도감이 영영 안 넘어온다

    /// Mobius 데이터 이전이 레거시 이름변경보다 **먼저** 돌면, 그 안의
    /// `AppStatePaths.directory()` 가 `PokeTokenBar/` 를 만들어 버려
    /// `migrateLegacyStorageIfNeeded` 의 `!fileExists(atPath: new.path)` 게이트가 통째로 걸린다.
    func testRunningMobiusMigrationFirstStrandsTheLegacyPokedex() throws {
        runLaunch([.mobiusDataMigration, .legacyStorageRename, .accountStateCreation])

        XCTAssertTrue(fm.fileExists(atPath: legacyDir.appendingPathComponent("companion-state.json").path),
                      "TokenMac 데이터가 원본 자리에 갇힌다")
        XCTAssertFalse(fm.fileExists(atPath: migratedPokedex.path),
                       "도감이 새 위치로 오지 못한다 — 사용자에겐 '진행이 날아갔다'로 보인다")
        // 대조군: 이 순서에서도 Mobius 계정 이전 자체는 성공한다 — 유실은 레거시 도감 쪽뿐이다.
        XCTAssertTrue(fm.fileExists(atPath: migratedAccounts.path))
        XCTAssertEqual(MobiusLaunchSequence.order.first, .legacyStorageRename,
                       "그래서 계약은 레거시 이름변경을 맨 앞에 둔다")
    }

    // MARK: 함정 2 — AccountsState 를 먼저 만들면 기존 Mobius 계정이 영영 안 넘어온다

    /// `AccountsState`(AccountStore) 가 먼저 `mobius/` 를 만들면 `alreadyMigrated` 판정
    /// (=대상 디렉터리 존재)이 걸려 이전이 조용히 건너뛰어진다.
    func testCreatingAccountStateBeforeMigrationStrandsMobiusAccounts() throws {
        runLaunch([.legacyStorageRename, .accountStateCreation, .mobiusDataMigration])

        XCTAssertFalse(fm.fileExists(atPath: stateDir.appendingPathComponent("mobius/secrets/a.json").path),
                       "기존 Mobius 비밀 스냅샷이 넘어오지 못한다")
        XCTAssertEqual(
            try MobiusDataMigration.migrate(from: mobiusSource,
                                            to: stateDir.appendingPathComponent("mobius"),
                                            fileManager: fm),
            .alreadyMigrated,
            "대상이 이미 있어 다음 실행에서도 영영 건너뛴다 — 자가 복구되지 않는다")
        // 대조군: 이 순서에서도 레거시 도감은 무사하다 — 유실은 Mobius 계정 쪽뿐이다.
        XCTAssertTrue(fm.fileExists(atPath: migratedPokedex.path))
        XCTAssertLessThan(
            MobiusLaunchSequence.order.firstIndex(of: .mobiusDataMigration)!,
            MobiusLaunchSequence.order.firstIndex(of: .accountStateCreation)!,
            "그래서 계약은 데이터 이전을 AccountsState 생성보다 앞에 둔다")
    }
}
