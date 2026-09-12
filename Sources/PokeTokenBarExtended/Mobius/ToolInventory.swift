import AppKit
import Foundation

enum ToolInventory {
    struct AppInfo: Equatable { var path: String; var version: String }

    static func appBundle(bundleID: String) -> AppInfo? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let version = Bundle(url: url)?
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return AppInfo(path: url.path, version: version)
    }

    static var mobiusCandidatePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/usr/local/bin/mobius", "\(home)/.local/bin/mobius"]
    }

    static func mobiusInstallations() -> [String] {
        mobiusCandidatePaths.filter { path in
            FileManager.default.fileExists(atPath: path)
                || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
        }
    }

    /// 설치 스크립트처럼 **PATH 해석이 필요 없는** 명령을 로그인 셸에서 돌린다. CLI 실행파일을
    /// 찾는 용도로는 쓰지 마라 — `-lc`(비대화형)는 `.zshrc` 를 안 읽어 nvm·mise 처럼 거기서만
    /// PATH 를 얻는 설치를 못 본다. 경로 해석은 `BinaryLocator.resolve` 한 곳이다(§부류 스윕).
    static func runLoginShellAsync(_ command: String) async -> (Int32, String)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do { try proc.run() } catch {
                    continuation.resume(returning: nil); return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                continuation.resume(returning:
                    (proc.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
