import SwiftUI
import MobiusCore

/// 계정 카드 1장 — 활성 표시·배지·사용량 게이지, 그리고 ⋯ 메뉴(기본 지정 / 재로그인 / 삭제).
///
/// 원본(Mobius, 430pt 팝오버)을 PokeTokenBar 의 **360pt** 팝오버로 재구성한 것이다.
/// 좁아진 폭(카드가 쓸 수 있는 공간 332pt)에 맞춰 바꾼 곳:
///  - 아바타 34→28, 카드 좌우 패딩 12→10, 열 간격 12→10
///  - 게이지 행의 "초기화 N시간 M분 후" 문장 → 시계 아이콘 + 기간만. 전체 문장은 `help` 툴팁으로
///    남겨 뜻이 사라지지 않게 한다
///  - 닉네임·이메일은 한 줄 말줄임 — 배지(기본/재로그인)가 밖으로 밀리는 대신 **이름이 줄어든다**
///  - Claude Desktop 동시 전환 진입점은 노출하지 않는다(1차 범위 밖 — 코드는 살아 있다)
///
/// 실제로 332pt 안에 들어오는지는 `AccountsTabLayoutTests` 가 7개 언어로 렌더해 확인한다.
@MainActor
struct AccountCardView: View {
    let l: L
    let profile: AccountProfile
    let isActive: Bool
    let isPrimary: Bool
    /// 이 풀의 자동 전환이 켜져 있나 — 꺼져 있으면 소진 카운트다운 대신 플랜 설명을 보여준다.
    let autoSwitchOn: Bool
    let usage: UsageSnapshot?
    /// 활성 Codex 계정인데 아직 사용량 데이터가 없을 때(세션 로그 in-band 라 codex 턴이 한 번
    /// 돌아야 생긴다) 빈 게이지 대신 안내를 띄운다. 리스트가 판정해 넘긴다.
    var codexAwaitingData: Bool = false
    let now: Date
    var onDelete: (() -> Void)? = nil
    /// fallback 카드에만 전달 — ⋯ 메뉴/우클릭에서 기본 계정으로 승격
    var onSetPrimary: (() -> Void)? = nil
    /// needsReauth/authSuspect 카드에만 전달 — 로그인 플로우 재실행(같은 계정 로그인 = 토큰 갱신)
    var onReauth: (() -> Void)? = nil
    /// 세션은 도는데 라이브 토큰이 만료돼 있다 — **의심**이지 확정이 아니다(AuthSuspicion).
    /// needsReauth(확정, 빨강)와 다른 문구·색으로 구분해 띄운다.
    var authSuspect: Bool = false
    /// 임계값 선제 경고 — **소진이 아니라 "곧 참"** 신호다. 소진(빨강)·재인증(주황)보다 낮은 심각도.
    var advisory: Bool = false
    /// 그릴 상태 배지. 프로덕션은 언제나 `nil` — 아래 심각도 규칙이 고른 **하나**만 그린다.
    /// **테스트 주입 전용**(마이그레이션 함수의 `base:`/`source:` 파라미터와 같은 성격): 규칙이
    /// 사라져 배지가 여러 개 그려지는 상태를 재현해, 폭 가드가 그걸 실제로 잡는지 확인한다.
    var statusBadgesForTesting: [StatusBadge]? = nil

    private let accent = Color(red: 0.35, green: 0.65, blue: 1.0)
    private let advisoryColor = Color.yellow

    /// 카드 1행이 List 에서 차지하는 높이(행 인셋 6pt 포함)의 **초기 추정치** — `AccountsView`
    /// 가 첫 프레임에만 쓰고, 이후엔 행별 실측 높이로 대체된다. 그래서 폰트/로케일/배지로
    /// 실제가 달라져도 잘리지 않는다.
    static func estimatedHeight(hasUsage: Bool, scopedCount: Int = 0,
                                codexHint: Bool = false) -> CGFloat {
        hasUsage ? 108 + CGFloat(scopedCount) * 16 : (codexHint ? 92 : 72)
    }

    var body: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                Text(profile.emailAddress)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                statusLine
                if let usage {
                    gauges(usage).padding(.top, 3)
                } else if codexAwaitingData {
                    // 폭이 모자라면 줄바꿈한다(축소가 아니라) — 10pt 를 더 줄이면 읽기 어렵고,
                    // 이 자리는 게이지가 들어올 자리라 두 줄까지는 카드가 커져도 여유가 있다.
                    Text(l.accountsCodexAwaitingData)
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent).font(.system(size: 15))
            }
            menu
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)))
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle().stroke(isActive ? accent : Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 28, height: 28)
            Text(String(profile.nickname.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? accent : .secondary)
        }
    }

    /// 카드 이름 옆에 띄우는 상태 배지. **한 번에 하나만** 띄운다.
    enum StatusBadge: Hashable {
        /// 확정 — 저장된 자격증명으로는 더 못 쓴다(빨강).
        case reauthRequired
        /// 의심 — 세션은 도는데 라이브 토큰이 만료됐다. 확정이 아니다(주황).
        case authSuspect
        /// 소진이 아니라 "곧 참"(노랑).
        case advisory
    }

    /// ★ 430pt 원본은 재인증·한도근접 배지를 나란히 띄웠지만 332pt 에서는 세 캡슐(기본 + 재인증
    /// + 한도근접)의 번역문이 카드를 밖으로 밀어낸다 — 실측 2026-09-11(2026-09-12 재현): 셋을
    /// 함께 그린 카드가 es 362 / fr 392 / pt 354 / de 373pt 로 `testWorstCaseAccountCardFits…` 를
    /// 빨갛게 만든다. ko 332 / en 332 / ja 332 는 배지 번역이 짧아 셋이어도 들어간다 — 이 규칙은
    /// **번역이 긴 언어 때문에** 있는 것이지 모든 언어에서 필요한 게 아니다.
    /// 그래서 심각도 순서로 하나만 고른다: 재인증은 사용자가 **지금 해야 할 일**이고, 한도 근접은
    /// 알림과 게이지가 이미 말하고 있다.
    /// 이 규칙이 지워지면 폭 가드가 잡는다 — `statusBadgesForTesting` 으로 그 상태를 주입해
    /// 가드가 실제로 빨갛게 뜨는지 `AccountsTabLayoutTests` 가 확인한다(결함 프로토콜 3).
    static func statusBadge(needsReauth: Bool, authSuspect: Bool, advisory: Bool) -> StatusBadge? {
        if needsReauth { return .reauthRequired }
        if authSuspect { return .authSuspect }
        if advisory { return .advisory }
        return nil
    }

    /// 이름 + 배지. 배지는 `fixedSize` 라 **이름이 먼저 줄어든다** — 반대로 두면 좁은 폭에서
    /// 상태 배지가 카드 밖으로 밀려 상태가 안 보인다(이름은 아바타·이메일로도 알아볼 수 있다).
    private var titleRow: some View {
        HStack(spacing: 5) {
            Text(profile.nickname)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            if isPrimary { badge(l.accountsPrimaryBadge, color: accent, bold: true) }
            ForEach(shownStatusBadges, id: \.self) { shown in
                switch shown {
                case .reauthRequired: badge(l.accountsReauthBadge, color: .red)
                case .authSuspect:    badge(l.accountsAuthSuspectBadge, color: .orange)
                case .advisory:       badge(l.accountsAdvisoryBadge, color: advisoryColor)
                }
            }
        }
    }

    private var shownStatusBadges: [StatusBadge] {
        if let statusBadgesForTesting { return statusBadgesForTesting }
        return Self.statusBadge(needsReauth: profile.needsReauth,
                                authSuspect: authSuspect, advisory: advisory).map { [$0] } ?? []
    }

    private func badge(_ text: String, color: Color, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: bold ? 8 : 9, weight: bold ? .bold : .medium))
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1).fixedSize()
    }

    /// ⋯ 메뉴 — 재로그인/기본 지정/삭제. 하나도 없으면 메뉴 자체를 안 그린다.
    @ViewBuilder private var menu: some View {
        if onDelete != nil || onSetPrimary != nil || onReauth != nil {
            Menu {
                if let onReauth {
                    Button(l.accountsReauthAction, systemImage: "arrow.clockwise") { onReauth() }
                }
                if let onSetPrimary {
                    Button(l.accountsSetPrimary, systemImage: "star") { onSetPrimary() }
                }
                if let onDelete {
                    Button(l.accountsDeleteAccount, systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    // MARK: 상태 줄

    /// 계정이 **전반적으로** 소진인가 — 5시간·주간 중 하나라도 100%. usage 를 모르면 보수적으로 참.
    private var generallyLimited: Bool {
        guard let usage else { return true }
        let five = usage.fiveHourPercent ?? 0, week = usage.sevenDayPercent ?? 0
        return five >= 100 || week >= 100
    }

    /// ★ 모델 전용 한도는 "계정 한도 소진"으로 표시하지 않는다 — 계정은 다른 모델로 계속 쓸 수
    /// 있다(메뉴바·알림과 같은 규칙). usage 를 아직 모를 때 `generallyLimited` 는 보수적으로
    /// 참이라, 이 분기가 없으면 모델 한도만 있는 계정에 계정 소진 카운트다운이 뜬다.
    @ViewBuilder private var statusLine: some View {
        if autoSwitchOn, let rl = profile.rateLimit, rl.resetsAt > now, rl.modelScoped {
            Label(l.accountsModelLimitResetsIn(remainText(until: rl.resetsAt)), systemImage: "sparkles")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        } else if autoSwitchOn, let rl = profile.rateLimit, rl.resetsAt > now, generallyLimited {
            Label(l.accountsResetsIn(remainText(until: rl.resetsAt)), systemImage: "hourglass")
                .font(.system(size: 10)).foregroundStyle(.orange)
                .lineLimit(1).minimumScaleFactor(0.85)
        } else {
            Text(profile.tierDescription)
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: 사용량 게이지 (5시간 / 주간 / 모델 스코프)

    /// 이 시간을 넘은 스냅샷은 "지금 값"으로 보여주지 않는다(흐리게 + 기준 시각 표기).
    /// ★ 얼어붙은 게이지는 특히 위험하다 — 초기화 카운트다운만 실시간 계산돼 살아 있는 것처럼
    ///   보이기 때문이다(Mobius 실측: 401 이 14시간 반복되는 동안 게이지가 정상처럼 보였다).
    static let usageStaleAfter: TimeInterval = 15 * 60

    private func staleAgeText(_ usage: UsageSnapshot) -> String? {
        let age = now.timeIntervalSince(usage.fetchedAt)
        guard age >= Self.usageStaleAfter else { return nil }
        return agoText(age)
    }

    private func gauges(_ usage: UsageSnapshot) -> some View {
        let stale = staleAgeText(usage)
        return VStack(alignment: .leading, spacing: 3) {
            if let percent = usage.fiveHourPercent {
                gaugeRow(label: l.accountsGaugeFiveHour, percent: percent,
                         resetsAt: usage.fiveHourResetsAt)
            }
            if let percent = usage.sevenDayPercent {
                gaugeRow(label: l.accountsGaugeWeekly, percent: percent,
                         resetsAt: usage.sevenDayResetsAt)
            }
            // 모델 스코프 주간 한도(예: Fable) — API 가 줄 때만. 제공이 끝나면 자동으로 사라진다.
            ForEach(usage.scopedLimits ?? [], id: \.label) { scoped in
                gaugeRow(label: scoped.label, percent: scoped.percent, resetsAt: scoped.resetsAt)
            }
            // 실패인지 단순 미갱신인지는 단정하지 않는다 — Codex 는 "그동안 codex 를 안 썼다"는
            // 뜻이기도 하다. 기준 시각만 밝히고 판단은 사용자에게 맡긴다.
            if let stale {
                Text(l.accountsUsageAsOf(stale))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).fixedSize()
            }
        }
        .opacity(stale == nil ? 1 : 0.5)   // 얼어붙은 값을 지금 값처럼 보여주지 않는다
    }

    /// 게이지 한 줄. 360pt 에서는 "초기화 …후" **문장**이 들어갈 자리가 없어 시계 아이콘 + 기간만
    /// 쓰고, 문장은 툴팁으로 남긴다. 라벨·퍼센트는 고정폭이라 카드마다 바가 같은 자리에서 시작한다.
    private func gaugeRow(label: String, percent: Double, resetsAt: Date?) -> some View {
        HStack(spacing: 5) {
            // fixedSize + 고정폭: minimumScaleFactor 를 쓰면 활성 카드(체크마크로 폭이 좁음)에서만
            // 글자가 줄어 카드마다 크기가 달라진다.
            Text(label)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(gaugeColor(percent))
                        .frame(width: max(3, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(minWidth: 28, maxWidth: .infinity)
            .frame(height: 5)
            Text("\(Int(percent))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(gaugeColor(percent))
                .lineLimit(1).fixedSize()
                .frame(width: 32, alignment: .trailing)
            if let resetsAt, resetsAt > now {
                let remain = remainText(until: resetsAt)
                Label(remain, systemImage: "clock")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).fixedSize()
                    .help(l.accountsResetsIn(remain))
            }
        }
    }

    private func gaugeColor(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return accent
        case ..<85: return .orange
        default: return .red
        }
    }

    // MARK: 기간 문구

    /// 남은 시간 — 일/시간/분 중 가장 큰 두 단위까지만. 모델 스코프 한도는 **주간**이라
    /// 시간으로만 쓰면 "168시간 0분"이 된다.
    private func remainText(until date: Date) -> String {
        durationText(date.timeIntervalSince(now))
    }

    private func agoText(_ interval: TimeInterval) -> String {
        durationText(interval)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        let (days, hours, mins) = (minutes / 1440, (minutes % 1440) / 60, minutes % 60)
        if days > 0 { return l.accountsDurationDays(days, hours) }
        if hours > 0 { return l.accountsDurationHours(hours, mins) }
        return l.accountsDurationMinutes(mins)
    }
}
