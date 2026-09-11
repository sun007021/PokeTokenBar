import AppKit
import SwiftUI
import MobiusCore

/// 계정 탭 — Claude·Codex 풀별 계정 목록과 수동 전환.
///
/// 이 탭은 `mobius.enabled` 토글이 켜졌을 때만 세그먼트에 나타난다(`PopoverTab.visible`).
/// 토글이 꺼져 있으면 이 뷰는 만들어지지도 않으므로 타이머·`onAppear` 갱신도 돌지 않는다.
///
/// 원본(Mobius)과 다른 점 — 1차 범위:
///  - 풀 안쪽의 전체/Claude/Codex 필터 탭을 없앴다. 풀은 최대 둘이고 360pt 팝오버 안에서
///    탭 속의 탭은 자리값을 못 한다 → 항상 풀별 섹션으로 함께 보여준다.
///  - 풀별 자동 전환 토글·Claude Desktop 동시 전환·멀티 Mac 동기화는 설정으로 간다(Phase 5).
///  - 스크롤을 감싸지 않는다: 아래 `poolCards` 의 `List` 를 `ScrollView` 안에 넣으면 중첩
///    스크롤이 되고, 행 이동(드래그) 제스처가 바깥 스크롤과 충돌한다.
@MainActor
struct AccountsView: View {
    @EnvironmentObject private var state: AccountsState
    let l: L

    /// 게이지 표시 여부는 Mobius 쪽 키를 그대로 쓴다(설정 UI 는 Phase 5). 키가 없으면 켬 —
    /// `AccountsState` 의 usage 폴링 게이트(`object == nil || bool`)와 같은 기본값이어야
    /// "값은 받아오는데 안 보인다"(또는 그 반대)가 생기지 않는다.
    @AppStorage("mobius.showUsageGauges") private var showUsageGauges = true
    @State private var now = Date()
    /// 카드 행의 실측 콘텐츠 높이(행 인셋 제외). 계정 삭제 후 남는 키는 무해(참조 안 됨).
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var showAddChooser = false
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.file.accounts.isEmpty {
                emptyView
            } else {
                pools
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(clock) { now = $0 }
        .onAppear {
            state.reload()
            state.refreshUsageIfStale()
            state.refreshCodexUsageIfStale()
            state.validateFallbacksLocally()
            now = Date()
        }
    }

    private var providersWithAccounts: [Provider] { state.file.providersWithAccounts }

    // MARK: 풀 목록

    private var pools: some View {
        VStack(spacing: 12) {
            ForEach(providersWithAccounts, id: \.self) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    // 풀이 하나뿐이면 구분할 대상이 없어 이름 줄이 군더더기가 된다(원본의
                    // 사용자 피드백) — 그때는 카드가 바로 온다.
                    if providersWithAccounts.count > 1 { sectionHeader(provider) }
                    poolCards(provider)
                }
            }
        }
    }

    /// 풀 경계 — 대문자 레이블 + 오른쪽으로 흐르는 헤어라인. 맨글자 하나만 떠 있으면 길 잃은
    /// 텍스트처럼 보여서 디바이더로 "여기부터 이 풀"임을 고정한다.
    private func sectionHeader(_ provider: Provider) -> some View {
        HStack(spacing: 8) {
            Text(provider.displayName.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.leading, 2)
    }

    // ★ 기본(primary) 카드도 반드시 풀의 **같은 List 의 행**이어야 한다. 기본 카드를 List 밖
    // 고정 슬롯에 두면 기본 계정을 바꿀 때 List 멤버십이 바뀌어(승격 행 삭제 + 강등 행 삽입)
    // NSTableView 기반 List 가 스크롤 오프셋을 한 행만큼 어긋난 채 방치한다 — 카드 높이가 전부
    // 같아 frame(height:) 이 안 변하는 경우(예: 전 계정 게이지 표시)에만 나타나 재현이 까다롭다.
    // 풀의 전 계정을 한 List 에 두면(기본은 moveDisabled) 전환이 같은 id 집합 안의 "행 이동"으로
    // diff 되어 오프셋이 깨지지 않는다.
    @ViewBuilder private func poolCards(_ provider: Provider) -> some View {
        let accounts = state.file.accounts(of: provider)
        List {
            ForEach(accounts, id: \.id) { profile in
                let isPrimary = profile.id == accounts.first?.id
                card(profile, isPrimary: isPrimary)
                    // 시각 위계: fallback 카드는 양쪽을 균등하게 들여 기본 카드보다 살짝 작게.
                    // 행 **안**의 스타일 변경이라 위 멤버십 불변식과 무관하다.
                    .padding(.horizontal, isPrimary ? 0 : 6)
                    // 행 높이 실측 — scrollDisabled List 라 추정이 실제보다 작으면 카드가 잘리고
                    // 스크롤로도 못 본다(배지·큰 폰트·로케일로 실제 높이가 달라진다).
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { rowHeights[profile.id] = geo.size.height }
                            .onChange(of: geo.size.height) { _, height in
                                rowHeights[profile.id] = height
                            }
                    })
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(isPrimary)
            }
            .onMove { state.moveFallback(provider: provider, from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // 높이가 내용과 정확히 같아 스크롤할 게 없다 — 스크롤을 꺼서 세로 스크롤바 거터(카드가
        // 왼쪽으로 밀리며 오른쪽에 빈 틈)가 생기지 않게 한다.
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        // macOS List(NSTableView) 가 행 콘텐츠에 좌 7pt·우 9pt 의 자체 여백을 비대칭으로 얹어,
        // 카드가 List 밖 요소보다 좁고 어긋나 보인다. 음수 패딩으로 상쇄한다.
        .padding(.leading, -7)
        .padding(.trailing, -9)
        // 실측 행 높이(콘텐츠 + 행 인셋 6pt) 합. 아직 측정 전인 행만 추정치.
        .frame(height: accounts.reduce(CGFloat(0)) { sum, profile in
            sum + (rowHeights[profile.id].map { $0 + 6 } ?? AccountCardView.estimatedHeight(
                hasUsage: usageFor(profile) != nil,
                scopedCount: usageFor(profile)?.scopedLimits?.count ?? 0,
                codexHint: codexAwaitingData(profile)))
        })
    }

    private func usageFor(_ profile: AccountProfile) -> UsageSnapshot? {
        showUsageGauges ? state.usage[profile.id] : nil
    }

    private func isActive(_ profile: AccountProfile) -> Bool {
        profile.id == state.file.activeByProvider[profile.provider]
    }

    /// 활성 Codex 계정인데 아직 사용량 데이터가 없을 때(Codex 는 세션 로그 in-band 라 앱 시작 후
    /// codex 턴이 한 번 돌아야 rate_limits 가 생긴다) 빈 게이지 대신 안내를 띄운다.
    private func codexAwaitingData(_ profile: AccountProfile) -> Bool {
        showUsageGauges && profile.provider == .codex && isActive(profile)
            && state.usage[profile.id] == nil
    }

    private func card(_ profile: AccountProfile, isPrimary: Bool) -> some View {
        // 재로그인 플로우는 Claude 전용 — Codex 는 재인증 감지 경로가 아직 없다.
        let claudeCard = profile.provider == .claude
        let suspect = claudeCard && state.authSuspect.contains(profile.id)
        // 낙관적 표시: 수동 전환(Claude) 클릭 직후 pendingSwitchID 로 그 카드를 즉시 활성으로
        // 보여줘 UI 가 스무스하게 전환된 것처럼 보이게 한다. Codex·평시엔 풀별 isActive.
        let showActive = claudeCard && state.pendingSwitchID != nil
            ? (profile.id == state.pendingSwitchID) : isActive(profile)
        let needsReauthAction = (profile.needsReauth || suspect) && claudeCard
        return AccountCardView(
            l: l,
            profile: profile,
            isActive: showActive,
            isPrimary: isPrimary,
            autoSwitchOn: state.file.isAutoSwitchEnabled(profile.provider),
            usage: usageFor(profile),
            codexAwaitingData: codexAwaitingData(profile),
            now: now,
            onDelete: { state.removeAccount(profile.id) },
            onSetPrimary: isPrimary ? nil : { setPrimary(profile.id) },
            onReauth: needsReauthAction ? { state.addAccount() } : nil,
            authSuspect: suspect,
            // 임계값 선제 경고는 Claude 전용이고, 경고 창이 아직 유효할 때만. 소진 카운트다운과
            // 같은 `now` 틱을 공유해 별도 타이머 없이 같은 주기로 나타나고 사라진다.
            advisory: claudeCard && profile.hasActiveAdvisory(now: now))
            .help(isActive(profile) ? "" : l.accountsSwitchHelp)
            .onTapGesture {
                guard !isActive(profile) else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    state.manualSwitch(to: profile.id)
                }
            }
            .contextMenu {
                if needsReauthAction {
                    Button(l.accountsReauthAction) { state.addAccount() }
                }
                if !isPrimary {
                    Button(l.accountsSetPrimary) { setPrimary(profile.id) }
                }
                Button(l.accountsDeleteAccount, role: .destructive) {
                    state.removeAccount(profile.id)
                }
            }
    }

    private func setPrimary(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { state.setPrimary(id) }
    }

    // MARK: 빈 상태 · 계정 추가

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.badge.key")
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(l.accountsEmptyTitle)
                .font(.system(size: 12)).foregroundStyle(.secondary)
            addClaudeButton
            codexAddGuide.padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            addAccountButton
            if let error = state.lastError {
                Text(error)
                    .font(.system(size: 9)).foregroundStyle(.red)
                    .lineLimit(1).truncationMode(.tail)
                    .help(error)
            }
            Spacer(minLength: 0)
        }
    }

    private var addClaudeButton: some View {
        Button { state.addAccount() } label: {
            Label(l.accountsAddClaude, systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    /// 계정 추가 — 프로바이더마다 방식이 달라(Claude = 브라우저 로그인, Codex = CLI adopt)
    /// 하나의 버튼에서 고르게 한다. 팝오버 안의 팝오버지만 그 자리에서 안내까지 끝난다.
    private var addAccountButton: some View {
        Button { showAddChooser.toggle() } label: {
            Label(l.accountsAdd, systemImage: "plus.circle.fill")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .popover(isPresented: $showAddChooser, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showAddChooser = false
                    state.addAccount()
                } label: {
                    Label(l.accountsAddClaude, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Divider()
                codexAddGuide
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    /// Codex 계정 추가 안내 — 브라우저 로그인 미지원, CLI adopt 방식. 문구가 여러 군데로
    /// 흩어지면 드리프트하므로 빈 상태와 추가 팝오버가 같은 블록을 쓴다.
    private var codexAddGuide: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(l.accountsCodexGuideTitle, systemImage: "terminal")
                .font(.system(size: 11, weight: .semibold))
            Text(l.accountsCodexGuideBody)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(l.accountsCodexGuideNote)
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
