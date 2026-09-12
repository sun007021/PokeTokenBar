import Foundation

/// Application Support state directory for PokeTokenBarExtended files.
/// `PTB_STATE_DIR` overrides the default for development/QA isolation.
enum AppStatePaths {
    static func directory() -> URL {
        let override = (ProcessInfo.processInfo.environment["PTB_STATE_DIR"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir: URL
        if !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                // 이름은 `StateDirectoryMigration` 이 단일 진실 — 개명 체인의 마지막 항목이다.
                .appendingPathComponent(StateDirectoryMigration.currentName)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
