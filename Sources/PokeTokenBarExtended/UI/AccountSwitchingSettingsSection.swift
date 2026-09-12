import SwiftUI
import MobiusCore

/// 설정 > '계정 전환' 섹션의 행들. 카드(`settingsSection`)는 `SettingsView` 가 씌운다.
///
/// **섹션 자체는 마스터 토글이 꺼져 있어도 항상 보인다** — 안 보이면 켤 방법이 없다. 대신 꺼진
/// 상태에서는 마스터 행 하나만 남고, 앱 런타임 동작은 기능을 넣기 전과 완전히 같다(타이머 0,
/// 세션 로그 스캔 0, 네트워크 0 — `AccountsState.start()` 가 그 모든 것의 유일한 진입점이다).
///
/// 계정 **추가** 진입점은 여기 두지 않는다. 계정 탭이 이미 두 자리에서 제공하고(계정이 없을 때의
/// 빈 화면, 있을 때의 푸터 '계정 추가' → Claude/Codex 선택 팝오버), 추가 결과인 카드가 나타나는
/// 곳도 그 탭이다. 설정에 중복시키면 로그인 창을 띄우는 경로가 둘로 늘어
/// `LoginFlowController` 의 "진행 중이면 무시" 가드에만 의존하게 된다.
///
/// 이 범위에 **없는** 것(1차 범위 밖, 코드는 살아 있으나 노출하지 않는다): Desktop 동시 전환,
/// 멀티 Mac 동기화, 실험실, Mobius 자체 업데이트 확인.
@MainActor
struct AccountSwitchingSettingsRows: View {
    let l: L

    /// `@Observable` 이 아니라 `ObservableObject` 다(이식본을 그대로 두기 위한 결정 —
    /// `docs/reference/mobius-integration.md`). `AppDelegate` 가 토글과 무관하게 **항상**
    /// 만들어 팝오버 트리에 주입하므로 옵셔널 분기가 필요 없다.
    @EnvironmentObject private var accounts: AccountsState

    /// 마스터 토글. 값 변경은 아래 `onChange` 가 `start()`/`stop()` 으로 옮긴다.
    @AppStorage(MobiusFeature.enabledKey) private var accountsEnabled = false
    /// 기본값 **켬** — `MobiusFeature.showUsageGauges` 의 "미설정이면 켬"과 같은 판정이어야
    /// 설정 화면과 계정 카드가 서로 다른 상태를 보여주지 않는다.
    @AppStorage(MobiusFeature.showUsageGaugesKey) private var showUsageGauges = true
    @AppStorage(MobiusFeature.advisorySwitchEnabledKey) private var advisorySwitchEnabled = false
    @AppStorage(MobiusFeature.advisoryThresholdPercentKey)
    private var advisoryThresholdPercent = MobiusFeature.advisoryThresholdDefault

    var body: some View {
        VStack(spacing: 0) {
            toggleRow(l.accountsSettingsEnable,
                      hint: l.accountsSettingsEnableHint,
                      isOn: $accountsEnabled)
            if accountsEnabled {
                // 기존 Mobius.app 이 실행 중이면 엔진이 내려가 있다. 계정 탭에도 같은 안내가
                // 있지만 이유는 **여기서도** 보여야 한다 — 아래 자동 전환 토글이 켜져 있는데
                // 아무 일도 안 일어나는 것을 확인하러 오는 화면이 바로 이 화면이다.
                if accounts.blockedByExternalApp {
                    Divider()
                    externalAppRow
                }
                ForEach(Provider.allCases, id: \.self) { provider in
                    Divider()
                    toggleRow(
                        l.accountsSettingsAutoSwitch(provider.displayName),
                        isOn: Binding(
                            get: { accounts.file.isAutoSwitchEnabled(provider) },
                            set: { accounts.setAutoSwitch($0, provider: provider) }))
                }
                Divider()
                advisoryRow
                Divider()
                toggleRow(l.accountsSettingsShowGauges, isOn: $showUsageGauges)
            }
        }
        // 토글을 끄면 타이머·세션 로그 스캔·외부 변경 옵저버가 **실제로** 멈춰야 한다
        // ("끄면 아무것도 안 돈다"가 이 기능의 계약이다). 켤 때 `start()` 는 자체
        // `guard timer == nil` 로 중복 생성을 막으므로 켜고 끄기를 반복해도 틱이 겹치지 않는다
        // (`AccountSwitchingSettingsTests` 가 타이머 객체의 동일성·무효화로 확인한다).
        .onChange(of: accountsEnabled) { _, enabled in
            if enabled { accounts.start() } else { accounts.stop() }
        }
    }

    /// 이중 writer 안내 행. 토글이 아니라 상태 표시라 `toggleRow` 를 쓰지 않지만, 치수는
    /// 같은 값(가로 12 / 세로 8)으로 맞춰 행 높이가 어긋나지 않게 한다.
    private var externalAppRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.accountsExternalAppTitle)
                Text(l.accountsExternalAppBody)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 38)
    }

    /// '한도 차기 전 미리 전환' — **'Claude 자동 전환'의 하위 옵션**이다. 부모가 꺼져 있으면
    /// 강제로 off 로 보이고 비활성화된다. 저장값(`advisorySwitchEnabled`)은 건드리지 않으므로
    /// 부모를 다시 켜면 이전 선택이 그대로 돌아온다.
    ///
    /// 게이트는 엔진과 **같은 함수**(`AccountsState.advisoryIsEffective`)로 판정한다 — 각자
    /// 조건을 적으면 "표시는 꺼졌는데 5분 폴링은 돈다"가 되고, 그 상태는 화면 어디에도 안
    /// 보이므로 사용자가 신고할 수조차 없다.
    private var advisoryRow: some View {
        let parentOn = accounts.file.isAutoSwitchEnabled(.claude)
        let effective = AccountsState.advisoryIsEffective(
            switchEnabled: advisorySwitchEnabled, claudeAutoSwitchEnabled: parentOn)
        return toggleRow(
            l.accountsSettingsAdvisory,
            hint: parentOn
                ? l.accountsSettingsAdvisoryHint
                : l.accountsSettingsAdvisoryNeedsParent(
                    l.accountsSettingsAutoSwitch(Provider.claude.displayName)),
            isOn: parentOn ? $advisorySwitchEnabled : .constant(false),
            trailing: { if effective { thresholdPicker } })
            .disabled(!parentOn)
    }

    /// 임계값 픽커. 행 밖으로 뽑아 둔 이유는 레이아웃 테스트가 advisory 행의 폭을 **프로덕션
    /// 컨트롤 그대로** 재기 위해서다 — 테스트가 픽커를 자기 손으로 다시 만들면 재는 모양과
    /// 그리는 모양이 갈라져, 폭이 넘치게 바뀌어도 초록불이 유지된다.
    var thresholdPicker: some View {
        Picker(l.accountsSettingsThreshold, selection: $advisoryThresholdPercent) {
            ForEach(MobiusFeature.advisoryThresholdChoices, id: \.self) {
                Text(verbatim: "\($0)%").tag($0)
            }
        }
        .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
    }

    /// ★ `Toggle("", …) + labelsHidden()` 을 쓰지 않는다 — 원본 Mobius 실측: 그 조합은 AX role 이
    /// switch 가 아니라 toggle button 으로 잡히고 클릭에도 반응하지 않는다. 라벨-클로저형은
    /// 라벨 안에 넣은 픽커가 개별 클릭을 그대로 받으므로 임계값 픽커를 같은 행에 둘 수 있다.
    ///
    /// 치수는 `SettingsView.groupRow` 와 맞춘다(가로 12 / 세로 8 / 최소 높이 38) — 다른 섹션
    /// 카드와 행 높이가 어긋나면 한 화면 안에서 바로 보인다.
    /// `private` 이 아닌 이유: 레이아웃 테스트가 **이 빌더로** 7개 언어를 잰다. 테스트가 같은
    /// 모양의 행을 따로 만들면 프로덕션 행만 넓어져도 초록불이 유지된다.
    func toggleRow<Trailing: View>(
        _ label: String,
        hint: String? = nil,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    if let hint {
                        Text(hint).font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
        .toggleStyle(.switch).controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 38)
    }

    func toggleRow(
        _ label: String, hint: String? = nil, isOn: Binding<Bool>
    ) -> some View {
        toggleRow(label, hint: hint, isOn: isOn, trailing: { EmptyView() })
    }
}
