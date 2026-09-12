import Foundation

/// Application Support 디렉터리를 앱 이름이 바뀔 때마다 따라 옮긴다.
///
/// 이 앱은 두 번 개명했다: `TokenMac` → `PokeTokenBar` → `PokeTokenBarExtended`.
/// 개명은 디렉터리를 통째로 갈라놓기 때문에, 새 이름으로 그냥 시작하면 도감·사용량 캐시·
/// 스프라이트·계정 데이터가 파일로는 남아 있는데 사용자에게는 **"진행이 날아갔다"** 로 보인다.
///
/// ## 체인
///
/// `names` 는 오래된 것부터 새 것 순이고 마지막이 현재 이름이다. 새 이름을 더할 때는
/// **배열 끝에 붙이기만 한다** — 앞 항목을 지우면 그 세대에 머물러 있던(= 그 이후로 앱을
/// 한 번도 안 켠) 사용자의 데이터가 영영 도착하지 못한다. 그래서 `TokenMac` 은 두 번째
/// 개명 뒤에도 남아 있다.
///
/// 여러 세대가 동시에 남아 있을 수 있다 — 앞선 이전이 "대상이 이미 있으면 건너뛴다" 로
/// 게이트돼 있어 원본이 그 자리에 남기 때문이다. 그때는 **가장 최근 세대가 이긴다**:
/// 뒤에서부터 훑어 처음 만난 원본을 옮기고 더 오래된 것은 건드리지 않는다.
enum StateDirectoryMigration {

    /// 오래된 이름 → 현재 이름. 끝에만 추가한다(위 §체인).
    static let names = ["TokenMac", "PokeTokenBar", "PokeTokenBarExtended"]

    /// 현재 상태 디렉터리 이름. `AppStatePaths` 가 이 값을 쓴다 — 두 곳이 따로 리터럴을
    /// 들고 있으면 다음 개명에서 조용히 어긋난다.
    static var currentName: String { names[names.count - 1] }

    /// 현재 이름의 디렉터리가 없고 옛 이름의 디렉터리가 있으면 이름을 바꾼다(이동).
    ///
    /// - Returns: 실제로 옮겨 온 옛 이름. 옮길 것이 없었으면 `nil`.
    @discardableResult
    static func migrateIfNeeded(base: URL, fileManager fm: FileManager = .default) -> String? {
        let destination = base.appendingPathComponent(currentName)
        // 대상이 이미 있으면 아무것도 안 한다 — 멱등이자, 살아 있는 데이터를 덮지 않는 가드.
        guard !fm.fileExists(atPath: destination.path) else { return nil }

        for name in names.dropLast().reversed() {
            let source = base.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            do {
                try fm.moveItem(at: source, to: destination)
                return name
            } catch {
                return nil   // 옮기지 못하면 그대로 둔다 — 반쪽 이전보다 낫다.
            }
        }
        return nil
    }

    /// 프로덕션 기본 경로(`~/Library/Application Support`)에 대고 실행.
    @discardableResult
    static func migrateIfNeeded(fileManager fm: FileManager = .default) -> String? {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return migrateIfNeeded(base: base, fileManager: fm)
    }
}
