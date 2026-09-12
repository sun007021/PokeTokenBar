import AppKit
import SwiftUI
import XCTest
import MobiusCore
@testable import PokeTokenBar

/// 설정 > '계정 전환' 섹션과, 그 섹션이 켜고 끄는 엔진의 접점.
///
/// 세 가지를 잰다: ① 토글 on↔off 가 타이머·옵저버를 정확히 한 번만 만들고 확실히 멈추는지,
/// ② advisory(미리 전환) 게이트가 UI 와 엔진에서 **같은 정의**인지, ③ 7개 언어에서 행이 360pt
/// 팝오버 안에 들어가는지. 진행 중인 비동기 작업까지 걷히는지는
/// `AccountsEngineLifecycleTests` 가 본다.
@MainActor
final class AccountSwitchingSettingsTests: XCTestCase {

    // MARK: - 토글 on ↔ off

    func testStartInstallsTheTickTimerAndTheExternalChangeObserver() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        XCTAssertNil(state.tickTimerForTesting, "생성만으로는 아무것도 돌지 않아야 한다")
        XCTAssertFalse(state.isObservingExternalChangesForTesting)

        state.start()
        let timer = try XCTUnwrap(state.tickTimerForTesting, "start() 가 3초 틱 타이머의 유일한 진입점이다")
        XCTAssertTrue(timer.isValid)
        XCTAssertTrue(state.isObservingExternalChangesForTesting,
                      "옵저버가 없으면 CLI 쪽 전환을 못 따라간다")
    }

    /// `invalidate()` 없이 필드만 비우면 타이머는 **런루프에 남아 계속 발화한다** — 그래서
    /// "nil 이 됐다"가 아니라 타이머 객체가 죽었는지를 본다.
    func testStopInvalidatesTheTimerAndRemovesTheObserver() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        state.start()
        let timer = try XCTUnwrap(state.tickTimerForTesting)

        state.stop()
        XCTAssertNil(state.tickTimerForTesting)
        XCTAssertFalse(timer.isValid, "필드만 비우고 무효화하지 않으면 틱은 3초마다 계속 돈다")
        XCTAssertFalse(state.isObservingExternalChangesForTesting,
                       "옵저버가 남으면 외부 변경마다 reload 가 돌아 '끄면 아무것도 안 돈다'가 깨진다")
    }

    /// 설정 토글은 `onChange` 로만 움직이지만, 두 번 켜지는 경로(뷰 재생성 등)가 생기면 타이머가
    /// 겹쳐 틱이 쌓인다(상류 이슈 #15 의 되먹임).
    func testStartIsIdempotent() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        state.start()
        let first = try XCTUnwrap(state.tickTimerForTesting)
        state.start()
        XCTAssertTrue(state.tickTimerForTesting === first,
                      "두 번째 start() 가 새 타이머를 만들면 3초마다 틱이 두 개씩 돈다")
    }

    /// 켜기 → 끄기 → 켜기: 살아 있는 타이머는 늘 하나여야 한다.
    func testTogglingOffAndOnAgainLeavesExactlyOneLiveTimer() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        state.start()
        let first = try XCTUnwrap(state.tickTimerForTesting)
        state.stop()
        state.start()
        let second = try XCTUnwrap(state.tickTimerForTesting)

        XCTAssertFalse(first === second, "stop() 이 타이머를 비웠으니 다시 켜면 새 타이머여야 한다")
        XCTAssertFalse(first.isValid, "이전 타이머가 살아 있으면 틱이 두 배로 돈다")
        XCTAssertTrue(second.isValid)
    }

    /// 설정 UI 가 실제로 이 두 함수를 부르는지 — 토글만 그려 두고 배선을 잊으면 값은 저장되는데
    /// 아무것도 시작·정지하지 않는다(다음 앱 실행에서야 반영되므로 눈에 잘 안 띈다).
    func testTheMasterToggleIsWiredToStartAndStop() throws {
        let ui = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBar/UI/AccountSwitchingSettingsSection.swift")
        let wiring = ui.filter { !MobiusTestSupport.isComment($0) }
            .joined(separator: "\n")
        XCTAssertTrue(wiring.contains("onChange(of: accountsEnabled)"),
                      "마스터 토글 값 변화를 듣는 자리가 없다")
        XCTAssertTrue(wiring.contains("accounts.start()") && wiring.contains("accounts.stop()"),
                      "토글이 엔진을 켜고 끄지 않으면 설정은 다음 실행에서야 반영된다")
    }

    // MARK: - advisory 게이트: UI 와 엔진이 같은 정의를 쓰는가

    /// '한도 차기 전 미리 전환'은 'Claude 자동 전환'의 **하위 옵션**이다 — 둘 다 켜져야 동작한다.
    func testAdvisoryIsEffectiveOnlyWhenBothTogglesAreOn() {
        XCTAssertTrue(AccountsState.advisoryIsEffective(switchEnabled: true,
                                                        claudeAutoSwitchEnabled: true))
        XCTAssertFalse(AccountsState.advisoryIsEffective(switchEnabled: true,
                                                         claudeAutoSwitchEnabled: false),
                       "부모(Claude 자동 전환)가 꺼져 있으면 미리 전환도 안 돈다")
        XCTAssertFalse(AccountsState.advisoryIsEffective(switchEnabled: false,
                                                         claudeAutoSwitchEnabled: true))
        XCTAssertFalse(AccountsState.advisoryIsEffective(switchEnabled: false,
                                                         claudeAutoSwitchEnabled: false))
    }

    /// 이 게이트가 두 곳에 따로 적히면 한쪽만 바뀌었을 때 **"표시는 꺼졌는데 5분 폴링은 돈다"**
    /// 가 된다. 그 상태는 화면 어디에도 안 나타나므로 사용자가 신고할 수조차 없다 — 그래서
    /// "조건을 다시 적지 않았다"를 소스에서 직접 확인한다.
    func testTheAdvisoryGateIsDefinedInExactlyOnePlace() throws {
        let engine = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBar/Mobius/AccountsState.swift")
        let ui = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBar/UI/AccountSwitchingSettingsSection.swift")

        XCTAssertEqual(Self.callSites(of: "advisoryIsEffective(", in: engine), 1,
                       "엔진(advisoryEffectivelyEnabled)이 이 함수를 부르는 자리는 하나여야 한다")
        XCTAssertEqual(Self.callSites(of: "AccountsState.advisoryIsEffective(", in: ui), 1,
                       "설정 UI 가 자기 조건을 쓰지 않고 같은 함수를 부르는지")

        let inlined = Self.linesCombiningTheAdvisoryFlag(in: engine + ui)
        XCTAssertTrue(inlined.isEmpty, """
            advisory 토글을 다른 조건과 직접 결합한 줄이 있다: \(inlined.joined(separator: " / ")). \
            결합은 advisoryIsEffective 안에서만 한다.
            """)
    }

    /// 위 확인도 주입으로 검증한다 — 조건을 손으로 다시 적은 줄을 먹여 잡히는지 본다.
    func testAdvisoryGateScanRejectsAnInlinedCondition() {
        let offending = ["        if advisorySwitchEnabled && store.file.isAutoSwitchEnabled(.claude) {"]
        XCTAssertEqual(Self.linesCombiningTheAdvisoryFlag(in: offending).count, 1)
        XCTAssertTrue(
            Self.linesCombiningTheAdvisoryFlag(in: ["        // advisorySwitchEnabled && 부모 설명 주석"])
                .isEmpty,
            "주석까지 잡으면 규칙을 설명하는 글을 못 쓰게 된다")
    }

    // MARK: - 레이아웃: 7개 언어가 360pt 팝오버에 들어가는가

    private func size(_ view: some View, proposing width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 900))
    }

    /// **폭으로는 잴 수 없다.** 행은 `Spacer(minLength: 0)` 를 물고 있어 이상적 폭이 무한이고,
    /// 제안 폭(332pt)으로 재면 `Text` 가 그 안으로 접혀 들어가므로 어떤 번역이 와도 332pt 가
    /// 나온다 — 두 측정 다 늘 통과하는 장식이다. 실제로 나타나는 증상은 **줄이 늘어나는 것**
    /// 이므로(라벨에 `lineLimit(1)` 이 없다) 좁은 폭과 넉넉한 폭의 **높이**를 비교한다.
    private func wrapsAtPopoverWidth(_ view: some View) -> Bool {
        abs(size(view, proposing: PopoverMetrics.contentWidth).height
            - size(view, proposing: 900).height) > 0.5
    }

    private func rows(_ language: AppLanguage) -> AccountSwitchingSettingsRows {
        AccountSwitchingSettingsRows(l: L(language))
    }

    /// 캡션(hint)은 접히라고 있는 것이라 제외하고, **한 줄로 남아야 하는 라벨**만 잰다.
    private func singleLineLabels(_ l: L) -> [String] {
        [l.accountsSettingsEnable,
         l.accountsSettingsAutoSwitch(Provider.claude.displayName),
         l.accountsSettingsAutoSwitch(Provider.codex.displayName),
         l.accountsSettingsAdvisory,
         l.accountsSettingsShowGauges]
    }

    func testEverySettingsRowLabelStaysOnOneLineInEveryLanguage() {
        for language in AppLanguage.allCases {
            let view = rows(language)
            for label in singleLineLabels(L(language)) {
                let row = view.toggleRow(label, isOn: .constant(true))
                XCTAssertFalse(wrapsAtPopoverWidth(row), """
                    \(language.rawValue): "\(label)" 행이 \(PopoverMetrics.contentWidth)pt 에서 \
                    접힌다(높이 \(size(row, proposing: PopoverMetrics.contentWidth).height) vs \
                    \(size(row, proposing: 900).height)). 라벨은 캡션이 아니라 행의 제목이라 \
                    두 줄이 되면 스위치와 세로 중심이 어긋나고 행 높이가 들쭉날쭉해진다.
                    """)
            }
        }
    }

    /// advisory 행만은 토글 옆에 임계값 픽커까지 달고 나온다(부모·자식이 모두 켜졌을 때).
    /// 라벨 + 스위치 + 픽커가 한 줄에 들어가는지는 이 조합으로만 확인할 수 있다.
    func testTheAdvisoryRowFitsEvenWithTheThresholdPicker() {
        for language in AppLanguage.allCases {
            let view = rows(language)
            let row = view.toggleRow(L(language).accountsSettingsAdvisory,
                                     isOn: .constant(true),
                                     trailing: { view.thresholdPicker })
            XCTAssertFalse(wrapsAtPopoverWidth(row),
                           "\(language.rawValue): 임계값 픽커가 붙으면 advisory 라벨이 접힌다")
        }
    }

    /// 위 두 측정이 **넓은 라벨을 실제로 거부하는지**(결함 프로토콜 3) — 통과만 보면 아무것도 안
    /// 재는 측정과 구별할 수 없다. 같은 함수에 일부러 긴 라벨을 먹인다.
    func testTheRowWrapGuardActuallyRejectsAnOverlongLabel() {
        let view = rows(.ko)
        let overlong = "Enable automatic account switching for Claude and Codex right now"
        XCTAssertTrue(wrapsAtPopoverWidth(view.toggleRow(overlong, isOn: .constant(true))),
                      "긴 라벨이 접히는 것을 못 잡으면 위 가드는 무엇도 막지 못한다")
    }

    /// 섹션 전체(마스터 토글 + 캡션 + 전 행)를 제안 폭 332pt 로 실제 렌더한다 — 어딘가에 고정
    /// `frame` 이 섞여 들어오면 여기서 넘친다. 캡션은 접혀도 되므로 높이는 재지 않는다.
    func testTheWholeSectionRendersInsideThePopoverWidthInEveryLanguage() throws {
        try withAccountsEnabled {
            let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
            for language in AppLanguage.allCases {
                let width = size(rows(language).environmentObject(state),
                                 proposing: PopoverMetrics.contentWidth).width
                XCTAssertLessThanOrEqual(width, PopoverMetrics.contentWidth,
                                         "\(language.rawValue): 섹션 폭 \(width)pt")
            }
        }
    }

    // MARK: - 헬퍼

    /// 마스터 토글이 꺼져 있으면 섹션은 한 줄짜리다 — 전 행을 렌더하려면 켠 상태가 필요하다.
    /// 테스트 프로세스의 standard 도메인만 건드리고 곧바로 되돌린다.
    private func withAccountsEnabled(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: MobiusFeature.enabledKey)
        defaults.set(true, forKey: MobiusFeature.enabledKey)
        defer {
            if let previous { defaults.set(previous, forKey: MobiusFeature.enabledKey) }
            else { defaults.removeObject(forKey: MobiusFeature.enabledKey) }
        }
        try body()
    }

    static func callSites(of needle: String, in lines: [String]) -> Int {
        lines.filter {
            !MobiusTestSupport.isComment($0) && $0.contains(needle) && !$0.contains("static func ")
        }.count
    }

    /// advisory 토글을 다른 조건과 **직접** 결합한 줄 — 게이트를 손으로 다시 적은 자리다.
    static func linesCombiningTheAdvisoryFlag(in lines: [String]) -> [String] {
        lines.filter {
            !MobiusTestSupport.isComment($0) && $0.contains("advisorySwitchEnabled")
                && $0.contains("&&")
        }.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
