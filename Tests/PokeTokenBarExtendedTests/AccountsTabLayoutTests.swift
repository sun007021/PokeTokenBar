import AppKit
import SwiftUI
import XCTest
import MobiusCore
@testable import PokeTokenBarExtended

/// 계정 탭은 430pt 팝오버(Mobius)에서 **360pt**(PokeTokenBar)로 옮겨온 UI 다. 폭이 좁아지면
/// 잘림은 컴파일도 기존 테스트도 못 잡고, 개발자 로케일(ko) 하나만 보면 더 긴 번역에서만
/// 터진다 — 그래서 세그먼트·카드·게이지를 **7개 언어 전부 실제로 렌더해** 폭과 줄수를 잰다.
@MainActor
final class AccountsTabLayoutTests: XCTestCase {

    // MARK: 렌더 헬퍼

    private func size(_ view: some View, proposing width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 800))
    }

    private func naturalWidth(_ view: some View) -> CGFloat {
        size(view, proposing: .greatestFiniteMagnitude).width
    }

    // MARK: 탭 노출 (토글 종속)

    func testAccountsTabIsAbsentUnlessTheFeatureIsEnabled() {
        XCTAssertEqual(PopoverTab.visible(accountsEnabled: false),
                       [.home, .shop, .bag, .collection],
                       "토글이 꺼져 있으면 팝오버는 기능 도입 전과 완전히 같은 4개 탭이어야 한다")
        XCTAssertFalse(PopoverTab.visible(accountsEnabled: false).contains(.accounts))
    }

    func testAccountsTabAppearsOnlyWhenEnabledAndKeepsTheExistingOrder() {
        XCTAssertEqual(PopoverTab.visible(accountsEnabled: true),
                       [.home, .shop, .bag, .collection, .accounts],
                       "계정 탭은 기존 탭 순서를 바꾸지 않고 맨 뒤에 붙는다")
    }

    /// 기본값이 꺼짐이어야 "지금 사용자에게 앱이 이전과 동일하게 보인다"가 성립한다.
    func testFeatureToggleDefaultsToOffOnAFreshDomain() throws {
        let suite = "AccountsTabLayoutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: MobiusFeature.enabledKey))
    }

    // MARK: 세그먼트 — 탭이 하나 늘어도 나머지 탭을 더 누르지 않나

    private func tabPicker(_ l: L, tabs: [PopoverTab]) -> some View {
        Picker("", selection: .constant(PopoverTab.home)) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab.title(l)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// `.pickerStyle(.segmented)` bridges to an AppKit `NSSegmentedControl` — unlike the plain
    /// SwiftUI `Text`/`HStack` layouts this file measures elsewhere (those pass in headless CI),
    /// this control needs a window server to compute its real per-segment width. Without one
    /// (headless CI, e.g. GitHub Actions macos-15 runners), `sizeThatFits` doesn't fail or return
    /// zero — it comes back with SwiftUI's "take all the space you want" sentinel instead: measured
    /// 2026-09-12 as `.greatestFiniteMagnitude` for the 4-tab bar and `.infinity` for the 5-tab bar.
    /// `.greatestFiniteMagnitude.isFinite == true`, so a plain finiteness check misses half the
    /// sentinel — this checks the *value* (implausibly large for any real pt width) rather than an
    /// environment variable, so it also catches other headless runs (e.g. an SSH session, a launchd
    /// daemon) that a `CI` env-var check would miss.
    private func skipIfUnmeasurable(_ widths: CGFloat...) throws {
        if let sentinel = widths.first(where: { !$0.isFinite || $0 >= 100_000 }) {
            throw XCTSkip("""
                Segmented Picker returned a sentinel width (\(sentinel)pt) instead of a real \
                measurement — this environment has no window server, so the AppKit-backed \
                NSSegmentedControl can't size itself. This assertion needs real segment widths; \
                it still runs normally on a real display (local dev, or an interactive CI runner).
                """)
        }
    }

    /// ★ 실측(2026-09-11)으로 정한 기준이다. macOS 세그먼트 픽커는 **모든 세그먼트를 가장 긴
    /// 라벨에 맞춰 같은 폭으로** 잡는다 — 7개 언어 전부에서 5탭 이상적 폭이 4탭의 정확히 1.25배로
    /// 나왔다(ko 220→275, en 328→410, ja 356→445, de 340→425 …). 그래서 "332pt 안에 들어오나"는
    /// 이 컨트롤에 물을 수 있는 질문이 아니다: 기준선인 **4탭도 ja(356)·de(340)는 이미 넘는다**.
    /// 물을 수 있는 건 "**내가 더 나쁘게 만들었나**"뿐이고, 계정 라벨이 그 언어의 최장 라벨보다
    /// 짧으면 세그먼트 폭 자체는 그대로다 = 기존 탭이 추가로 눌리지 않는다.
    func testAccountsLabelIsNeverTheWidestTabLabel() {
        for language in AppLanguage.allCases {
            let l = L(language)
            let accounts = naturalWidth(Text(l.accountsTab))
            let widestExisting = PopoverTab.visible(accountsEnabled: false)
                .map { naturalWidth(Text($0.title(l))) }.max() ?? 0
            XCTAssertLessThanOrEqual(
                accounts, widestExisting,
                "\(language.rawValue): 계정 라벨 \(accounts)pt 가 기존 최장 라벨 \(widestExisting)pt 보다 넓으면 세그먼트 폭이 그만큼 커져 나머지 탭까지 더 눌린다")
        }
    }

    /// 위 성질의 컨트롤 차원 확인 — 탭이 하나 늘어도 바의 이상적 폭은 **정확히 한 칸분**만
    /// 커져야 한다. 계정 라벨이 최장이 되면 이 비율이 1.25를 넘는다.
    func testAddingTheAccountsTabGrowsTheBarByExactlyOneEvenSegment() throws {
        for language in AppLanguage.allCases {
            let l = L(language)
            let four = naturalWidth(tabPicker(l, tabs: PopoverTab.visible(accountsEnabled: false)))
            let five = naturalWidth(tabPicker(l, tabs: PopoverTab.visible(accountsEnabled: true)))
            try skipIfUnmeasurable(four, five)
            XCTAssertEqual(five, four * 5 / 4, accuracy: 1,
                           "\(language.rawValue): 4탭 \(four)pt → 5탭 \(five)pt. 한 칸분(=\(four * 5 / 4)pt)을 넘으면 계정 라벨이 세그먼트 폭을 키운 것이다")
        }
    }

    /// 위 두 가드가 "넓은 라벨에 실제로 실패하는가" — 통과만 보면 아무것도 안 지키는 측정과
    /// 구별할 수 없다. 같은 측정 함수에 일부러 긴 라벨을 먹여 비율이 깨지는지 확인한다.
    func testTabWidthGuardActuallyRejectsALabelThatWidensTheSegment() throws {
        let l = L(.ko)
        let four = naturalWidth(tabPicker(l, tabs: PopoverTab.visible(accountsEnabled: false)))
        let overlong = Picker("", selection: .constant(4)) {
            Text(l.home).tag(0)
            Text(l.shop).tag(1)
            Text(l.bag).tag(2)
            Text(l.collection).tag(3)
            Text("Accounts and switching settings").tag(4)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        let overlongWidth = naturalWidth(overlong)
        try skipIfUnmeasurable(four, overlongWidth)
        XCTAssertGreaterThan(overlongWidth, four * 5 / 4 + 1,
                             "측정이 '세그먼트를 넓히는 라벨'을 감지하지 못하면 위 가드는 무의미하다")
    }

    // MARK: 계정 카드 — 332pt 안에 들어오나

    private func profile(
        nickname: String = "flosdor-workspace",
        email: String = "flosdor.longest.address@example-company.com",
        provider: Provider = .claude,
        needsReauth: Bool = false,
        rateLimit: RateLimitInfo? = nil
    ) -> AccountProfile {
        AccountProfile(id: UUID(), provider: provider, nickname: nickname, emailAddress: email,
                       organizationName: "Example Company", tierDescription: "Max 20x",
                       needsReauth: needsReauth, rateLimit: rateLimit)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(scoped: Int = 1, fetchedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourPercent: 100, fiveHourResetsAt: now.addingTimeInterval(3 * 3600 + 25 * 60),
            sevenDayPercent: 88, sevenDayResetsAt: now.addingTimeInterval(5 * 86_400 + 3 * 3600),
            scopedLimits: (0..<scoped).map {
                ScopedUsageLimit(label: "Fable \($0)", percent: 100,
                                 resetsAt: now.addingTimeInterval(6 * 86_400))
            },
            fetchedAt: fetchedAt ?? now)
    }

    /// 최악의 카드 — 긴 닉네임·이메일 + 기본 배지 + 재로그인 배지 + 소진 카운트다운 + 게이지 3줄
    /// + 활성 체크마크 + ⋯ 메뉴. 카드를 넓힐 수 있는 요소를 한 장에 모두 켠 상태다.
    private func worstCaseCard(
        _ l: L, statusBadges: [AccountCardView.StatusBadge]? = nil
    ) -> AccountCardView {
        AccountCardView(
            l: l,
            profile: profile(needsReauth: true,
                             rateLimit: RateLimitInfo(resetsAt: now.addingTimeInterval(3 * 3600),
                                                      recordedAt: now, modelScoped: false)),
            isActive: true, isPrimary: true, autoSwitchOn: true,
            usage: usage(), now: now,
            onDelete: {}, onSetPrimary: {}, onReauth: {},
            authSuspect: false, advisory: true,
            statusBadgesForTesting: statusBadges)
    }

    private func cardWidth(_ l: L, statusBadges: [AccountCardView.StatusBadge]? = nil) -> CGFloat {
        size(worstCaseCard(l, statusBadges: statusBadges),
             proposing: PopoverMetrics.contentWidth).width
    }

    func testWorstCaseAccountCardFitsPopoverContentWidthInEveryLanguage() {
        for language in AppLanguage.allCases {
            let width = size(worstCaseCard(L(language)),
                             proposing: PopoverMetrics.contentWidth).width
            XCTAssertLessThanOrEqual(
                width, PopoverMetrics.contentWidth,
                "\(language.rawValue): 카드 폭 \(width)pt 가 \(PopoverMetrics.contentWidth)pt 를 넘으면 팝오버에서 좌우로 잘린다")
        }
    }

    /// 위 가드가 **실제로 무언가를 막는지** 확인한다(결함 프로토콜 3) — 통과만 보면 아무것도 안
    /// 지키는 가드를 구별할 수 없다. 주입하는 결함은 `AccountCardView.statusBadge` 의 '심각도
    /// 순서로 하나만' 규칙을 지운 상태, 즉 재인증·인증확인·한도근접 배지를 **동시에** 그리는
    /// 카드다. 배지는 `fixedSize` 라 압축되지 않고 닉네임만 말줄임으로 줄어들므로, 닉네임이
    /// 최소 폭에 닿는 순간부터 배지 폭이 그대로 카드 폭이 된다.
    ///
    /// 실측(2026-09-12, 기본 배지 + 상태 배지 셋 = 캡슐 4개, 제안 폭 332pt):
    /// ko 332 / en 397 / ja 368 / es 440 / fr 497 / pt 439 / de 470pt.
    /// **모든 언어가 넘치지는 않는다** — ko 는 배지 번역이 짧아 넷이어도 그대로 들어간다. 그래서
    /// '어느 한 언어라도 넘는가'로 단언한다(가드 자신도 7개 언어를 돌며 하나라도 넘으면 실패한다).
    /// 여유가 3pt 라면 폰트 메트릭이 조금만 흔들려도 증명이 뒤집히므로, 가장 넓은 언어가
    /// **최소 60pt 초과**라는 것까지 함께 못 박는다(실측 최대치 fr 은 165pt 초과).
    ///
    /// 프로덕션 주석이 인용하는 `es 362 / fr 392 / pt 354 / de 373` 은 원본이 실제로 그렸던 조합
    /// (기본 + 재인증 + 한도근접 = 캡슐 3개)의 수치다. 여기서 하나를 더 켜는 이유는 규칙이 고를 수
    /// 있는 상태 배지 **전부**를 켜는 게 '규칙을 지운 상태'의 정의이기 때문이다.
    func testCardWidthGuardActuallyRejectsMoreThanOneStatusBadge() {
        let allBadges: [AccountCardView.StatusBadge] = [.reauthRequired, .authSuspect, .advisory]
        let widths = AppLanguage.allCases.map { ($0, cardWidth(L($0), statusBadges: allBadges)) }
        let report = widths.map { "\($0.rawValue) \($1)pt" }.joined(separator: " / ")

        let overflowing = widths.filter { $1 > PopoverMetrics.contentWidth }
        XCTAssertFalse(overflowing.isEmpty, """
            배지를 동시에 여럿 그려도 어느 언어에서도 \(PopoverMetrics.contentWidth)pt 를 넘지 \
            않는다면 위 폭 가드는 아무것도 안 지킨다 — \(report)
            """)
        XCTAssertGreaterThan(
            widths.map(\.1).max() ?? 0, PopoverMetrics.contentWidth + 60,
            "가장 넓은 언어가 60pt 넘게 초과하지 않으면 '우연히 몇 pt 넘었다'와 구별되지 않는다 — \(report)")
    }

    /// 위 주입이 프로덕션 경로를 건드리지 않는다는 확인 — 규칙이 살아 있는 한 배지는 하나뿐이고,
    /// 그 상태에서는 7개 언어 전부 332pt 에 정확히 들어간다(꽉 채우되 넘지 않는다).
    func testSeverityRuleKeepsExactlyOneStatusBadge() {
        XCTAssertEqual(AccountCardView.statusBadge(needsReauth: true, authSuspect: true,
                                                   advisory: true), .reauthRequired)
        XCTAssertEqual(AccountCardView.statusBadge(needsReauth: false, authSuspect: true,
                                                   advisory: true), .authSuspect)
        XCTAssertEqual(AccountCardView.statusBadge(needsReauth: false, authSuspect: false,
                                                   advisory: true), .advisory)
        XCTAssertNil(AccountCardView.statusBadge(needsReauth: false, authSuspect: false,
                                                 advisory: false))
        for language in AppLanguage.allCases {
            XCTAssertEqual(cardWidth(L(language)), PopoverMetrics.contentWidth, accuracy: 0.5,
                           "\(language.rawValue): 규칙이 살아 있는 카드는 제안 폭을 꽉 채우되 넘지 않는다")
        }
    }

    /// 게이지 행은 라벨·바·퍼센트·초기화 기간을 **한 줄**에 놓는다. 번역이 길어 줄이 접히면
    /// 카드 높이가 늘고 `List` 의 고정 frame 계산(실측 전 첫 프레임)이 어긋난다.
    func testGaugeRowsStayOnOneLineInEveryLanguage() {
        for language in AppLanguage.allCases {
            let card = worstCaseCard(L(language))
            let narrow = size(card, proposing: PopoverMetrics.contentWidth).height
            let wide = size(card, proposing: 900).height
            XCTAssertEqual(
                narrow, wide, accuracy: 0.5,
                "\(language.rawValue): 332pt 높이 \(narrow) 가 넉넉한 폭의 \(wide) 와 다르면 어딘가 줄이 접힌 것이다")
        }
    }

    /// 게이지 하나가 늘 때마다 카드가 커지는지 — 추정 높이(`estimatedHeight`)가 실제와 같은
    /// 방향으로 움직여야 첫 프레임이 잘리지 않는다.
    func testCardGrowsWithEachScopedGaugeAndEstimateKeepsUp() {
        let l = L(.en)
        func height(scoped: Int) -> CGFloat {
            let card = AccountCardView(
                l: l, profile: profile(), isActive: false, isPrimary: false, autoSwitchOn: true,
                usage: usage(scoped: scoped), now: now)
            return size(card, proposing: PopoverMetrics.contentWidth).height
        }
        XCTAssertGreaterThan(height(scoped: 3), height(scoped: 1))
        for scoped in [0, 1, 3] {
            let estimate = AccountCardView.estimatedHeight(hasUsage: true, scopedCount: scoped)
            let actual = height(scoped: scoped) + 6   // 행 인셋
            XCTAssertEqual(estimate, actual, accuracy: 24,
                           "scoped=\(scoped): 추정 \(estimate) 와 실측 \(actual) 이 크게 벌어지면 첫 프레임이 잘리거나 크게 점프한다")
        }
    }

    /// 게이지가 없는 카드(게이지 표시 끔 / Codex 대기)도 같은 폭 계약을 지켜야 한다. 안내 문구는
    /// 축소가 아니라 줄바꿈으로 처리하므로 높이는 최대 한 줄만 늘 수 있다.
    func testCardWithoutGaugesFitsAndWrapsTheCodexHintAtMostOnce() {
        for language in AppLanguage.allCases {
            let card = AccountCardView(
                l: L(language), profile: profile(provider: .codex), isActive: true,
                isPrimary: false, autoSwitchOn: false, usage: nil,
                codexAwaitingData: true, now: now, onDelete: {})
            let narrow = size(card, proposing: PopoverMetrics.contentWidth)
            let wide = size(card, proposing: 900)
            XCTAssertLessThanOrEqual(narrow.width, PopoverMetrics.contentWidth,
                                     "\(language.rawValue) codex 안내 카드 폭 \(narrow.width)pt")
            XCTAssertLessThanOrEqual(
                narrow.height, wide.height + 14,
                "\(language.rawValue): 높이 \(narrow.height) 가 넉넉한 폭의 \(wide.height) 보다 한 줄 넘게 크면 안내가 세 줄 이상으로 접힌 것이다")
            XCTAssertLessThanOrEqual(
                narrow.height,
                AccountCardView.estimatedHeight(hasUsage: false, codexHint: true) + 24,
                "\(language.rawValue): 안내 카드 높이 \(narrow.height) 가 추정치에서 크게 벗어나면 첫 프레임이 잘린다")
        }
    }

    // MARK: 리스트 구조 (실패 기록 17)

    /// 풀의 **전 계정**이 한 `List` 의 행이어야 한다 — 기본 카드를 List 밖 고정 슬롯에 두면
    /// 기본 계정 전환이 "행 삭제 + 행 삽입"으로 diff 돼 스크롤 오프셋이 어긋난 채 방치된다.
    /// 그 결함은 카드 높이가 전부 같을 때만 보여서 렌더 테스트로는 잡기 어렵다 — 구조를 소스에서
    /// 직접 확인한다(`LocalizedUILiteralTests`·`SwiftUIIsolationTests` 와 같은 방식).
    func testEveryAccountCardIsBuiltFromTheSingleListRowFactory() throws {
        let source = try String(contentsOf: accountsViewURL, encoding: .utf8)
        let constructions = source.components(separatedBy: "AccountCardView(").count - 1
        XCTAssertEqual(constructions, 1, """
            AccountCardView 를 두 군데 이상에서 만들면 기본 카드를 List 밖에 따로 그리는 구조가 \
            된다(실패 기록 17). 카드 생성은 List 행 팩토리 하나로만.
            """)
        XCTAssertTrue(source.contains(".moveDisabled(isPrimary)"),
                      "기본 행은 moveDisabled 여야 재정렬이 같은 id 집합 안의 '행 이동'으로 유지된다")
        XCTAssertTrue(source.contains("ForEach(accounts, id: \\.id)"),
                      "풀의 전 계정이 같은 ForEach 의 행이어야 한다")
    }

    private var accountsViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarExtendedTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBarExtended/UI/AccountsView.swift")
    }
}
