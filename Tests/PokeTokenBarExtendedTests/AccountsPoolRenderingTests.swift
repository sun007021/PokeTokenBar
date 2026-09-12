import AppKit
import SwiftUI
import XCTest
import MobiusCore
@testable import PokeTokenBarExtended

/// 계정 탭의 **풀 구성** — 프로바이더가 둘일 때 두 풀이 다 자리를 차지하는가.
///
/// 기존 레이아웃 테스트(`AccountsTabLayoutTests`)는 카드 **한 장**의 폭·줄수만 재고, 탭 전체를
/// 렌더한 적이 없었다. "codex 는 나오는데 claude 는 안 나온다"는 리포트를 그 테스트들로는
/// 확인도 반증도 할 수 없었던 이유다 — 그래서 조립된 뷰를 실제로 렌더해 못 박는다.
@MainActor
final class AccountsPoolRenderingTests: XCTestCase {

    private func claudeSnapshot(email: String, token: String) throws -> CredentialsSnapshot {
        let oauth = try JSONSerialization.data(withJSONObject: [
            "emailAddress": email, "organizationName": "Org", "accountUuid": UUID().uuidString,
        ])
        let blob = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": ["accessToken": token, "refreshToken": "r-\(token)",
                              "expiresAt": 4_000_000_000_000, "scopes": ["user:inference"],
                              "subscriptionType": "max"],
        ])
        return CredentialsSnapshot(keychainBlob: blob, credentialsFileData: blob,
                                   oauthAccountJSON: oauth)
    }

    private func height(_ state: AccountsState) -> CGFloat {
        NSHostingController(rootView: AccountsView(l: L(.en)).environmentObject(state))
            .sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 2000)).height
    }

    func testBothProviderPoolsTakeUpSpaceInTheAccountsTab() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self,
                                                               keychain: InMemoryKeychain())
        _ = try state.store.upsertProfile(nickname: "claude-one",
                                          snapshot: claudeSnapshot(email: "c@x.com", token: "C0"))
        state.reload()
        XCTAssertEqual(state.file.providersWithAccounts, [.claude])
        let claudeOnly = height(state)

        _ = try state.store.upsertProfile(
            nickname: "codex-one", provider: .codex,
            identity: ProviderIdentity(emailAddress: "x@codex.com", organizationName: "Org",
                                       tierDescription: "Plus"),
            secretData: Data(#"{"tokens":{"id_token":"a.b.c"}}"#.utf8))
        state.reload()

        XCTAssertEqual(state.file.providersWithAccounts, [.claude, .codex],
                       "풀 목록은 계정이 있는 프로바이더 전부여야 한다")
        // 두 번째 풀은 섹션 헤더 + 카드 한 장(카드 최소 높이 72pt)만큼 자리를 더 먹는다.
        // 헤더만 생기고 카드가 0 높이로 접히는 경우(고정 frame List 의 높이 계산 실패)를
        // 이 하한이 잡는다.
        XCTAssertGreaterThanOrEqual(height(state), claudeOnly + 72,
                             "두 번째 풀이 실제 높이를 차지하지 않으면 화면에서 사라진 것과 같다")
    }

    /// 풀이 하나면 섹션 헤더가 없다(원본의 사용자 피드백) — 헤더 유무로 풀 개수를 읽은
    /// 진단이 성립하려면 이 규칙이 유지돼야 한다.
    func testASinglePoolRendersWithoutASectionHeader() throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self,
                                                               keychain: InMemoryKeychain())
        _ = try state.store.upsertProfile(nickname: "claude-one",
                                          snapshot: claudeSnapshot(email: "c@x.com", token: "C0"))
        state.reload()
        let single = height(state)

        _ = try state.store.upsertProfile(nickname: "claude-two",
                                          snapshot: claudeSnapshot(email: "d@x.com", token: "D0"))
        state.reload()
        XCTAssertEqual(state.file.providersWithAccounts, [.claude],
                       "같은 풀에 계정을 더해도 풀은 하나다")
        // 같은 풀의 두 번째 카드는 헤더 없이 카드 높이(72pt)만 더한다 — 헤더가 함께
        // 생겼다면 이 값을 넘어선다.
        XCTAssertEqual(height(state), single + 72, accuracy: 1)
    }
}
