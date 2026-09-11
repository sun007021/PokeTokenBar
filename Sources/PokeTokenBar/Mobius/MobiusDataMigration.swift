import Foundation

/// One-time copy of an existing Mobius.app user's data into PokeTokenBar's own state directory.
///
/// PokeTokenBar keeps its Mobius integration data under `AppStatePaths.directory()/mobius/`
/// rather than sharing `~/Library/Application Support/Mobius/` with Mobius.app itself — running
/// both apps against the same files risks the credential-corruption races Mobius's own history
/// records (concurrent writers to `accounts.json` / Keychain). This migration only ever *copies*;
/// it never touches the original Mobius.app data, so that app keeps working unmodified.
///
/// See `docs/reference/mobius-integration.md` for the data-preservation invariants this follows.
enum MobiusDataMigration {

    enum Outcome: Equatable {
        /// Files were copied. `fileCount` counts files only (not directories).
        case migrated(fileCount: Int)
        /// `destination` already existed — a prior run already migrated this data (or found
        /// nothing to migrate and left `destination` alone, in which case a later run with
        /// real data to migrate will still see `destination` absent and proceed normally).
        case alreadyMigrated
        /// `source` does not exist — the user has never run Mobius.app, not an error.
        case noSourceData
        /// `source` exists but held none of accounts.json / secrets/ / desktop-profiles — e.g.
        /// Mobius.app was installed and launched but the user never added an account, or a
        /// crash left a fresh Mobius state directory with no data in it yet. Nothing was
        /// copied and `destination` was deliberately left uncreated (see `migrate` below), so
        /// this is not conflated with `.migrated(fileCount: 0)`, which would claim a migration
        /// happened when nothing actually moved.
        case nothingToMigrate
    }

    /// Pure core: takes explicit source/destination URLs and a `FileManager` so it can be
    /// exercised against temp directories in tests without touching the real home directory.
    ///
    /// Atomicity: everything is assembled in a sibling staging directory first, then moved into
    /// `destination` with a single `moveItem` (an atomic rename on the same volume). If anything
    /// throws before that final move, `destination` was never touched — it either doesn't exist
    /// yet or still holds whatever a previous successful migration left there. The staging
    /// directory is best-effort cleaned up via `defer` in both the success and failure paths (on
    /// success it no longer exists at that path, so the cleanup is a harmless no-op).
    static func migrate(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> Outcome {
        var isSourceDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isSourceDirectory),
              isSourceDirectory.boolValue
        else {
            return .noSourceData
        }

        // `destination` is only ever created below when there was at least one file to move
        // (see the `fileCount > 0` guard before `moveItem`), so its mere existence — not
        // specifically `destination/accounts.json` — is what "already migrated" means. Keying
        // this off `accounts.json` alone let a `destination` that existed without it (an empty
        // migration, or a source whose secrets/ was staged without an accounts.json — e.g. a
        // crash between AccountStore writing a secret and saving accounts.json) slip past this
        // guard, so the next run tried to `moveItem` into a `destination` that was already
        // there and threw "already exists" on every subsequent launch.
        if fileManager.fileExists(atPath: destination.path) {
            return .alreadyMigrated
        }

        let destinationParent = destination.deletingLastPathComponent()
        let staging = destinationParent.appendingPathComponent(".mobius-migration-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        var fileCount = 0

        let accountsSource = source.appendingPathComponent("accounts.json")
        if fileManager.fileExists(atPath: accountsSource.path) {
            let accountsStaging = staging.appendingPathComponent("accounts.json")
            fileCount += try copyPreservingPermissions(
                from: accountsSource, to: accountsStaging, fileManager: fileManager)
            // accounts.json holds account metadata (not raw secrets) but Mobius still keeps it
            // at 0600 in practice — enforce that explicitly rather than trust the mirrored mode.
            try forcePermissions(0o600, onto: accountsStaging, fileManager: fileManager)
        }

        let secretsSource = source.appendingPathComponent("secrets")
        var isSecretsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: secretsSource.path, isDirectory: &isSecretsDirectory),
           isSecretsDirectory.boolValue {
            let secretsStaging = staging.appendingPathComponent("secrets")
            fileCount += try copyPreservingPermissions(
                from: secretsSource, to: secretsStaging, fileManager: fileManager)
            // These files are raw credential snapshots. Mirroring the source's permissions
            // (above) should already produce 0700/0600, but this is the one invariant that must
            // never regress silently — a secret landing at 0644 is readable by every other local
            // account on the Mac. Verify and force explicitly rather than trust the mirror alone.
            try forcePermissions(0o700, onto: secretsStaging, fileManager: fileManager)
            let secretFiles = try fileManager.contentsOfDirectory(
                at: secretsStaging, includingPropertiesForKeys: nil)
            for secretFile in secretFiles {
                try forcePermissions(0o600, onto: secretFile, fileManager: fileManager)
            }
        }

        let desktopProfilesSource = source.appendingPathComponent("desktop-profiles")
        var isDesktopProfilesDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: desktopProfilesSource.path, isDirectory: &isDesktopProfilesDirectory),
           isDesktopProfilesDirectory.boolValue {
            fileCount += try copyPreservingPermissions(
                from: desktopProfilesSource,
                to: staging.appendingPathComponent("desktop-profiles"),
                fileManager: fileManager)
        }

        guard fileCount > 0 else {
            // Nothing was staged (source exists but is empty of anything this migration
            // understands) — leave `destination` uncreated. `staging` is removed by the
            // `defer` above; there is nothing to move.
            return .nothingToMigrate
        }

        try fileManager.moveItem(at: staging, to: destination)
        return .migrated(fileCount: fileCount)
    }

    /// Thin real-path wrapper — not called from anywhere yet. Wiring this into the app lifecycle
    /// is Phase 3; for now only the code and its tests exist, so runtime behavior is unchanged.
    /// 독립 Mobius.app 의 기본 데이터 위치.
    static var defaultSource: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mobius")
    }

    /// ★ `source` 는 **테스트 주입 전용**이다 — 실제 `~/Library/Application Support/Mobius` 에
    /// 대고 테스트를 돌리지 않기 위한 것. 대상 경로 유도(`AppStatePaths.directory()` 호출이
    /// 상태 디렉터리를 **만든다**)는 주입하지 않는다: 그게 순서 계약의 함정 당사자라
    /// `MobiusLaunchSequenceTests` 가 프로덕션과 같은 경로로 밟아야 한다.
    static func migrateIfNeeded(
        source: URL? = nil, fileManager: FileManager = .default
    ) throws -> Outcome {
        let destination = AppStatePaths.directory().appendingPathComponent("mobius")
        return try migrate(from: source ?? defaultSource, to: destination, fileManager: fileManager)
    }

    /// Recursively copies `source` to `destination`, mirroring the source's POSIX permissions on
    /// every file and directory it creates along the way. Returns the number of files (not
    /// directories) copied.
    @discardableResult
    private static func copyPreservingPermissions(
        from source: URL, to destination: URL, fileManager: FileManager
    ) throws -> Int {
        let sourceAttributes = try fileManager.attributesOfItem(atPath: source.path)
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try mirrorPermissions(sourceAttributes, onto: destination, fileManager: fileManager)
            var count = 0
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            for child in children {
                count += try copyPreservingPermissions(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    fileManager: fileManager)
            }
            return count
        } else {
            try fileManager.copyItem(at: source, to: destination)
            try mirrorPermissions(sourceAttributes, onto: destination, fileManager: fileManager)
            return 1
        }
    }

    private static func mirrorPermissions(
        _ sourceAttributes: [FileAttributeKey: Any], onto url: URL, fileManager: FileManager
    ) throws {
        guard let permissions = sourceAttributes[.posixPermissions] else { return }
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private static func forcePermissions(_ mode: Int, onto url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
