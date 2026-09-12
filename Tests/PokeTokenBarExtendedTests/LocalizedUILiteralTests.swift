import XCTest
@testable import PokeTokenBarExtended

/// Routing guard: `LocalizationInterpolationTests` only checks strings that already go through
/// `L(_:)` — a literal that never reaches the table is structurally invisible to it. #210 shipped
/// three Korean literals straight into `Text(...)`/`Button(...)`, so every non-Korean user would
/// have read Korean. Scan the UI sources instead and require Hangul to live in `Localization.swift`.
/// (Korean *comments* are the house style and stay allowed — only string literals are offenders.)
final class LocalizedUILiteralTests: XCTestCase {
    /// `Mobius/` 가 함께 걸려 있는 이유: Phase 7 이 계정 전환 문구를 `L` 로 옮겼는데, 그 계층은
    /// **뷰가 아니라서** 새 문구를 더할 때 `companion.l` 이 눈앞에 없다(미러
    /// `AccountsState.localizationLanguage` 를 거쳐야 한다). 그만큼 리터럴로 되돌아가기 쉬운
    /// 자리라 `UI/` 와 같은 검사를 건다.
    private static let scannedDirectories = [
        "Sources/PokeTokenBarExtended/UI",
        "Sources/PokeTokenBarExtended/Mobius",
    ]

    func testNoHangulStringLiteralsInUISources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarExtendedTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
        var offenders: [String] = []

        for relative in Self.scannedDirectories {
            let directory = root.appendingPathComponent(relative)
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let lines = try String(contentsOf: url, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                for (index, line) in lines.enumerated() where Self.hasHangulStringLiteral(line) {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            User-facing copy must be routed through Localization.swift so every AppLanguage gets it.
            Move these Hangul literals into an `L` property and reference it: \
            \(offenders.joined(separator: ", "))
            """)
    }

    /// 스캐너가 **실제로 무언가를 잡는지** — 통과만 보면 아무것도 안 보는 스캔과 구별할 수 없다.
    /// 로그 제외가 표시 문구까지 함께 통과시키지 않는지도 여기서 본다.
    func testTheScannerCatchesCopyButNotCommentsOrLogs() {
        XCTAssertTrue(Self.hasHangulStringLiteral(#"Text("계정 추가")"#))
        XCTAssertFalse(Self.hasHangulStringLiteral("// 계정 추가 버튼"))
        XCTAssertFalse(Self.hasHangulStringLiteral(#"AppLog.write("전환 실패")"#))
        XCTAssertFalse(Self.hasHangulStringLiteral(#"NSLog("Claude Desktop 경로가 비정상")"#))
        // 로그 호출이 같은 줄에 있어도 표시 문구는 통과시키지 않는다.
        XCTAssertTrue(Self.hasHangulStringLiteral(
            #"if bad { lastError = "전환 실패"; NSLog("switch failed") }"#))
    }

    /// 진단 로그(`AppLog.write`/`NSLog`)는 사용자 노출이 아니라 현지화 대상이 아니다. 다만 제외를
    /// "줄에 로그 호출이 있으면 통째로 통과"로 두면 같은 줄의 표시 문구까지 숨는다 → 리터럴이
    /// **하나뿐인** 줄에서만 건너뛴다.
    private static let logSinks = ["AppLog.write(", "NSLog("]

    /// Character walk rather than a regex: it has to tell a `//` inside a string literal apart from
    /// a real trailing comment, or Korean comments (house style) would all read as offenders.
    private static func hasHangulStringLiteral(_ line: String) -> Bool {
        if logSinks.contains(where: { line.contains($0) }), stringLiteralCount(line) <= 1 {
            return false
        }
        var inString = false
        var escaped = false
        var previous: Character?
        for character in line {
            if escaped { escaped = false; previous = character; continue }
            if character == "\\" && inString { escaped = true; previous = character; continue }
            if character == "\"" { inString.toggle(); previous = character; continue }
            if !inString && character == "/" && previous == "/" { return false }  // trailing comment
            if inString && Self.isHangul(character) { return true }
            previous = character
        }
        return false
    }

    /// 이 줄이 여는 문자열 리터럴의 수. 위 로그 제외의 폭을 좁히는 데만 쓴다.
    private static func stringLiteralCount(_ line: String) -> Int {
        var count = 0
        var inString = false
        var escaped = false
        for character in line {
            if escaped { escaped = false; continue }
            if character == "\\" && inString { escaped = true; continue }
            if character == "\"" {
                if !inString { count += 1 }
                inString.toggle()
            }
        }
        return count
    }

    private static func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)     // syllables
                || (0x1100...0x11FF).contains(scalar.value)   // jamo
                || (0x3130...0x318F).contains(scalar.value)   // compatibility jamo
        }
    }
}
