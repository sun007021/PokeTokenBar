import XCTest
@testable import PokeTokenBar

/// Exercises `MobiusDataMigration.migrate` purely against temp directories — never the real
/// `~/Library/Application Support/Mobius/` or `AppStatePaths.directory()`. See
/// `docs/reference/mobius-integration.md` for why this migration only ever copies.
final class MobiusDataMigrationTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MobiusMigrationTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("Mobius")
        destination = root.appendingPathComponent("PokeTokenBar/mobius")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        root = nil
        source = nil
        destination = nil
    }

    // MARK: - Fixture helpers

    private func writeSourceFixture() throws {
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{\"accounts\":[]}".utf8).write(to: source.appendingPathComponent("accounts.json"))
        try fm.setAttributes([.posixPermissions: 0o600],
                              ofItemAtPath: source.appendingPathComponent("accounts.json").path)

        let secrets = source.appendingPathComponent("secrets")
        try fm.createDirectory(at: secrets, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try Data("secret-a".utf8).write(to: secrets.appendingPathComponent("a.json"))
        try Data("secret-b".utf8).write(to: secrets.appendingPathComponent("b.json"))
        try Data("stale-secret".utf8).write(to: secrets.appendingPathComponent("a.json.bak"))
        for name in ["a.json", "b.json", "a.json.bak"] {
            try fm.setAttributes([.posixPermissions: 0o600],
                                  ofItemAtPath: secrets.appendingPathComponent(name).path)
        }
    }

    // MARK: - Tests

    func testFreshMigrationCopiesFilesWithMatchingContent() throws {
        try writeSourceFixture()

        let outcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        XCTAssertEqual(outcome, .migrated(fileCount: 4))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("accounts.json")),
            try Data(contentsOf: source.appendingPathComponent("accounts.json")))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("secrets/a.json")),
            Data("secret-a".utf8))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("secrets/b.json")),
            Data("secret-b".utf8))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("secrets/a.json.bak")),
            Data("stale-secret".utf8))
    }

    func testPermissionsArePreservedOnCopiedSecrets() throws {
        try writeSourceFixture()

        _ = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        let secretsDir = destination.appendingPathComponent("secrets")
        let dirAttrs = try fm.attributesOfItem(atPath: secretsDir.path)
        XCTAssertEqual((dirAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        for name in ["a.json", "b.json", "a.json.bak"] {
            let attrs = try fm.attributesOfItem(atPath: secretsDir.appendingPathComponent(name).path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600, "\(name) permissions")
        }

        let accountsAttrs = try fm.attributesOfItem(
            atPath: destination.appendingPathComponent("accounts.json").path)
        XCTAssertEqual((accountsAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testSecondRunIsANoOpAndDoesNotOverwriteDestination() throws {
        try writeSourceFixture()

        _ = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        // Mutate the destination copy so a second run overwriting it would be observable.
        try Data("mutated-by-user".utf8).write(to: destination.appendingPathComponent("secrets/a.json"))

        let secondOutcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        XCTAssertEqual(secondOutcome, .alreadyMigrated)
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("secrets/a.json")),
            Data("mutated-by-user".utf8))
    }

    func testMissingSourceIsANoOp() throws {
        // `source` was never created by this test.
        let outcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        XCTAssertEqual(outcome, .noSourceData)
        XCTAssertFalse(fm.fileExists(atPath: destination.path))
    }

    func testSourceIsNeverModified() throws {
        try writeSourceFixture()
        let accountsSourcePath = source.appendingPathComponent("accounts.json").path
        let beforeAttrs = try fm.attributesOfItem(atPath: accountsSourcePath)

        _ = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: accountsSourcePath))
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("secrets/a.json").path))
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("secrets/a.json.bak").path))
        let afterAttrs = try fm.attributesOfItem(atPath: accountsSourcePath)
        XCTAssertEqual(afterAttrs[.posixPermissions] as? NSNumber, beforeAttrs[.posixPermissions] as? NSNumber)
    }

    func testDesktopProfilesDirectoryIsCopiedWhenPresent() throws {
        try writeSourceFixture()
        let desktopProfiles = source.appendingPathComponent("desktop-profiles")
        try fm.createDirectory(at: desktopProfiles, withIntermediateDirectories: true)
        try Data("identity".utf8).write(to: desktopProfiles.appendingPathComponent("profile-1.json"))

        let outcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        XCTAssertEqual(outcome, .migrated(fileCount: 5))
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("desktop-profiles/profile-1.json")),
            Data("identity".utf8))
    }

    func testEmptySourceDirectoryDoesNotThrowOnRerun() throws {
        // Simulates a user who installed/ran Mobius.app but never added an account: the state
        // directory exists (Mobius created it on first launch) but holds none of accounts.json,
        // secrets/, or desktop-profiles/. The old `alreadyMigrated` guard was keyed off
        // `destination/accounts.json`, so if the first run still created `destination` (even
        // empty), the second run's guard never tripped and `moveItem` threw because
        // `destination` already existed.
        try fm.createDirectory(at: source, withIntermediateDirectories: true)

        let firstOutcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)
        XCTAssertEqual(firstOutcome, .nothingToMigrate)
        XCTAssertFalse(fm.fileExists(atPath: destination.path), "nothing to migrate must not create destination")

        let secondOutcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)
        XCTAssertEqual(secondOutcome, .nothingToMigrate, "repeated runs against an untouched empty source stay idempotent")
    }

    func testSourceWithOnlySecretsAndNoAccountsFileDoesNotThrowOnRerun() throws {
        // Simulates a crash between `AccountStore.upsertProfile` writing the secret snapshot
        // and its subsequent `save()` writing accounts.json (see AccountStore.swift — secret
        // write happens before `save()`): `secrets/` holds a file but `accounts.json` was never
        // written. The old `alreadyMigrated` guard only ever looked at
        // `destination/accounts.json`, so a first run here would migrate `secrets/` into a
        // freshly created `destination` that still has no `accounts.json` in it — and every
        // later run would try (and fail) to migrate again since the guard never tripped.
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let secrets = source.appendingPathComponent("secrets")
        try fm.createDirectory(at: secrets, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try Data("orphaned-secret".utf8).write(to: secrets.appendingPathComponent("a.json"))
        try fm.setAttributes([.posixPermissions: 0o600],
                              ofItemAtPath: secrets.appendingPathComponent("a.json").path)

        let firstOutcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)
        XCTAssertEqual(firstOutcome, .migrated(fileCount: 1))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("accounts.json").path))

        let secondOutcome = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)
        XCTAssertEqual(secondOutcome, .alreadyMigrated, "a destination without accounts.json is still already migrated")
    }

    func testNoStagingLeftoverAfterSuccessfulMigration() throws {
        try writeSourceFixture()

        _ = try MobiusDataMigration.migrate(from: source, to: destination, fileManager: fm)

        let leftovers = try fm.contentsOfDirectory(
            at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertEqual(leftovers.map(\.lastPathComponent), ["mobius"])
    }
}
