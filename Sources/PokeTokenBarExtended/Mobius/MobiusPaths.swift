import Foundation

/// Where this app keeps the account-switching state it inherited from Mobius.
///
/// It is a subdirectory of this app's own state directory, never
/// `~/Library/Application Support/Mobius` — two processes writing the same `accounts.json`,
/// secret snapshots and Keychain entries is exactly the credential-corruption race Mobius's
/// failure log is built around. `MobiusDataMigration` copies an existing Mobius.app user's data
/// here once, leaving the original untouched so that app keeps working.
enum MobiusPaths {
    /// Injected into `MobiusEnvironment.appSupportDirOverride`, which makes `accounts.json`,
    /// `secrets/` and `desktop-profiles/` resolve under this directory.
    static func stateDirectory() -> URL {
        AppStatePaths.directory().appendingPathComponent("mobius")
    }
}
