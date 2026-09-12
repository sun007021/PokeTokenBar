import XCTest
@testable import PokeTokenBarExtended

/// Phase 7 — 계정 전환 문구가 `L` 로 이관된 뒤의 불변식.
///
/// 이 기능의 문구는 **뷰 밖**(알림·배너·실패 사유)에서 만들어져 화면 테스트가 못 본다.
/// 그래서 (a) 에러 타입 → 사용자 문구 매핑, (b) ko·en 만 번역하는 규칙, (c) 언어 미러 배선을
/// 여기서 잠근다.
final class AccountsLocalizationTests: XCTestCase {

    // MARK: 에러 타입 → 사용자 문구

    /// `LoginFlowError`/`DesktopCoordinatorError` 는 더 이상 `LocalizedError` 가 아니다 —
    /// `errorDescription` 은 언어를 받을 수 없기 때문이다. 매핑이 어긋나면 "The operation
    /// couldn't be completed. (PokeTokenBar.LoginFlowError error 0.)" 가 그대로 노출된다.
    /// 언어는 `allCases` 로 돈다 — 리터럴 목록은 언어가 늘어난 순간 조용히 커버를 멈춘다.
    func testAccountErrorMessagesAreLocalizedNotRawSwiftText() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let mapped: [(Error, String)] = [
                (LoginFlowError.claudeNotFound, l.accountsErrorClaudeCLINotFound),
                (LoginFlowError.urlNotFound, l.accountsErrorLoginURLNotFound),
                (LoginFlowError.timeout, l.accountsErrorLoginTimeout),
                (LoginFlowError.canceled, l.accountsErrorLoginCanceled),
                (DesktopCoordinatorError.switchInProgress, l.accountsErrorDesktopSwitchInProgress),
            ]
            for (error, expected) in mapped {
                let message = l.accountsErrorMessage(error)
                XCTAssertEqual(message, expected, "\(lang) / \(error)")
                XCTAssertFalse(message.contains("Error error"), "원문 노출: \(message)")
                XCTAssertFalse(message.contains("couldn't be completed"), "원문 노출: \(message)")
            }
        }
        // 그 외 오류는 시스템 문구로 폴백(파일 읽기 실패 등).
        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertEqual(L(.en).accountsErrorMessage(other), other.localizedDescription)
    }

    /// 매핑을 안 거치면 무엇이 노출되는지 — 위 테스트가 진짜로 무언가를 지키는지 보여준다.
    /// (이 타입이 다시 `LocalizedError` 가 되면 여기서 먼저 빨간불이 난다.)
    func testWithoutTheMappingTheRawSwiftTextWouldLeak() {
        let raw = (LoginFlowError.timeout as Error).localizedDescription
        XCTAssertTrue(raw.contains("LoginFlowError"),
                      "매핑을 거치지 않으면 사용자에게 이 문자열이 뜬다: \(raw)")
    }

    // MARK: ko·en 만 번역하는 규칙 (docs/reference/mobius-integration.md §다국어 규칙)

    /// 이 기능의 새 문구는 ko·en 만 쓰고 ja/es/fr/pt/de 슬롯에는 en 을 그대로 넣는다.
    /// 규칙이 지켜지는지 대표 항목으로 확인한다 — 어긋나면 반쯤 번역된 슬롯이 생긴다.
    func testAccountSwitchingCopyFallsBackToEnglishOutsideKoreanAndEnglish() {
        let samples: [(String, (L) -> String)] = [
            ("accountsNotifyReauthTitle", { $0.accountsNotifyReauthTitle }),
            ("accountsNotifyAllExhaustedBody", { $0.accountsNotifyAllExhaustedBody }),
            ("accountsErrorSyncStalled", { $0.accountsErrorSyncStalled }),
            ("accountsErrorSwitchFailed", { $0.accountsErrorSwitchFailed("boom") }),
            ("accountsExternalAppTitle", { $0.accountsExternalAppTitle }),
        ]
        let english = L(.en)
        for (name, value) in samples {
            XCTAssertNotEqual(value(L(.ko)), value(english), "\(name): ko 가 en 과 같으면 미번역이다")
            for lang in AppLanguage.allCases where lang != .ko && lang != .en {
                XCTAssertEqual(value(L(lang)), value(english),
                               "\(name): \(lang) 슬롯에는 en 값이 들어가야 한다")
            }
        }
    }

    /// 반대편 못 — Phase 4~5 에서 **이미 7개 언어로 번역된** 항목은 되돌리지 않는다는 결정.
    /// 되돌리는 건 순수한 손실이고, 각 슬롯은 독립적으로 읽히므로 혼재는 무해하다.
    func testAlreadyTranslatedAccountStringsKeepTheirSevenLanguages() {
        let samples: [(String, (L) -> String)] = [
            ("accountsSettingsEnable", { $0.accountsSettingsEnable }),
            ("accountsSettingsShowGauges", { $0.accountsSettingsShowGauges }),
        ]
        for (name, value) in samples {
            for lang in [AppLanguage.ja, .es, .fr, .pt, .de] {
                XCTAssertNotEqual(value(L(lang)), value(L(.en)),
                                  "\(name): \(lang) 번역을 en 으로 되돌리지 않는다")
            }
        }
    }

    // MARK: 언어 미러 배선

    /// `AccountsState` 는 뷰가 아니라 `companion.l` 에 닿지 못해 언어를 미러로 받는다
    /// (`UsageStore.localizationLanguage` 와 같은 관례). 미러가 실제로 문구를 가른다.
    @MainActor
    func testStateMirrorSelectsTheLanguageOfItsCopy() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        XCTAssertEqual(state.localizationLanguage, .systemDefault,
                       "시드 전 기본값은 시스템 언어 — 실행 순서와 무관하게 안전해야 한다")
        state.localizationLanguage = .ko
        XCTAssertEqual(L(state.localizationLanguage).accountsNotifyReauthTitle,
                       L(.ko).accountsNotifyReauthTitle)
        state.localizationLanguage = .de
        XCTAssertEqual(L(state.localizationLanguage).accountsNotifyReauthTitle,
                       L(.en).accountsNotifyReauthTitle, "de 슬롯에는 en 값이 들어 있다")
    }

    /// 미러는 **켜는 자리와 고치는 자리가 둘**이다(기동 시드 + 언어 픽커). 둘 중 하나가 빠지면
    /// 증상이 서로 다르게 나타난다 — 시드가 없으면 앱 언어와 무관하게 시스템 언어로 나오고,
    /// 픽커 갱신이 없으면 언어를 바꿔도 알림만 옛 언어로 남는다. 어느 쪽도 화면 테스트로는
    /// 안 잡히므로 배선 자체를 소스에서 확인한다.
    func testTheHostSeedsAndUpdatesTheLanguageMirror() throws {
        let app = try MobiusTestSupport.sourceLines(of: "Sources/PokeTokenBarExtended/PokeTokenBarExtendedApp.swift")
            .filter { !MobiusTestSupport.isComment($0) }
            .joined(separator: "\n")
        XCTAssertTrue(app.contains("accounts.localizationLanguage = companion.language"),
                      "시드가 없으면 계정 알림이 앱 언어를 따르지 않는다")

        let settings = try MobiusTestSupport.sourceLines(of: "Sources/PokeTokenBarExtended/UI/SettingsView.swift")
            .filter { !MobiusTestSupport.isComment($0) }
            .joined(separator: "\n")
        XCTAssertTrue(settings.contains("accounts.localizationLanguage = $0"),
                      "언어를 바꿔도 미러가 그대로면 알림·배너만 옛 언어로 남는다")
    }

    /// 위 갱신 지점이 **유일한** 언어 변경 경로라는 전제를 잠근다. `setLanguage` 호출부가 늘면
    /// 그 경로만 미러를 안 고쳐 같은 결함이 조용히 되살아난다.
    func testLanguageChangesGoThroughASinglePlace() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBarExtended")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil))
        var callSites: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).split(
                separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated()
            where line.contains("companion.setLanguage(") && !MobiusTestSupport.isComment(line) {
                callSites.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(callSites.count, 1, """
            언어 변경 경로가 늘었다. 새 경로에서도 `store.localizationLanguage` 와 \
            `accounts.localizationLanguage` 를 함께 갱신한 뒤 이 개수를 고쳐라: \
            \(callSites.joined(separator: ", "))
            """)
        XCTAssertTrue(callSites.first?.hasPrefix("SettingsView.swift:") == true,
                      "언어 픽커가 옮겨졌다면 미러 갱신도 따라갔는지 확인하라: \(callSites)")
    }
}
