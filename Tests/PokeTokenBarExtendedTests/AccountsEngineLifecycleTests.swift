import XCTest
@testable import MobiusCore
@testable import PokeTokenBarExtended

/// `AccountsState.stop()` 이 **정말로 멈추는가.**
///
/// 이 기능의 계약은 "끄면 아무것도 안 돈다" 한 줄인데, 깨지는 방식이 화면에 안 나타난다 —
/// 진행 중인 작업이 남아도 UI 는 조용하고, 최악의 경우 **사용자가 방금 끈 기능이 계정을
/// 전환한다**(틱이 자동 전환까지 수행하므로). "타이머가 nil 이 됐다"는 관찰로는 영영 안 걸린다.
@MainActor
final class AccountsEngineLifecycleTests: XCTestCase {

    /// **결함**: `stop()` 이 타이머·옵저버만 걷고 진행 중인 비동기 작업을 취소하지 않았다.
    /// `start()` 의 마지막 줄은 타이머와 **별개로** 즉시 한 틱을 띄운다.
    func testStopCancelsTheTickThatStartLaunched() async throws {
        let state = try MobiusTestSupport.isolatedAccountsState(cleanupWith: self)
        state.start()
        let tick = try XCTUnwrap(state.tickTaskForTesting,
                                 "start() 는 타이머 설치와 별개로 즉시 한 틱을 띄운다")
        XCTAssertFalse(tick.isCancelled)

        state.stop()
        XCTAssertTrue(tick.isCancelled, "타이머만 걷으면 이 틱은 끝까지 돌아 계정을 바꿀 수 있다")

        await tick.value   // 취소된 틱이 실제로 끝나는지 — 안 끝나면 여기서 매달린다
        XCTAssertNil(state.tickTaskForTesting, "끝난 틱은 자기 핸들을 스스로 비운다")
    }

    // MARK: - 부류 스윕: 새 Task 필드가 분류 없이 늘어나는 것 방지

    /// 이 결함의 부류는 "**새 비동기 작업을 추가하고 `stop()` 에 넣는 것을 잊는다**"이고,
    /// 한 번 고쳐도 필드가 늘 때마다 되풀이된다. 그래서 기억이 아니라 기계로 막는다:
    /// `AccountsState` 의 모든 `Task` 필드는 `stop()` 에서 취소되거나, 아래 목록에 **이유와
    /// 함께** 예외로 적혀 있어야 한다.
    ///
    /// 예외의 기준은 하나다 — **끊으면 자격증명이 반쯤 쓰인 상태로 남는가.**
    /// (취소가 나머지에 안전한 이유: 자격증명을 쓰는 구간은 전부 동기이거나 취소가 전파되지
    /// 않는 `Task {}` 쉴드 안이라, 서버가 회전 토큰을 소비한 뒤 저장 전에 끊기는 경로가 없다.)
    static let deliberatelyNotCancelled: [String: String] = [
        "desktopSwitchTask": """
            Desktop 종료 → 프로필 스왑 → 재실행. 중간에서 끊으면 Desktop 자격증명이 반쯤 옮겨진 \
            채 남고 앱은 안 뜬다. 짧고 스스로 끝난다.
            """,
        "desktopCaptureTask": """
            사용자가 연 가이드 캡처. 이미 원래 Desktop 로그인을 치워 둔(stash) 상태이고 되돌리는 \
            경로는 endDesktopCapture() 하나뿐이라, 취소만 하면 사용자의 로그인이 로그아웃된 채 남는다.
            """,
        "desktopCaptureRestoreTask": """
            endDesktopCapture()의 복원(종료→stash 복원→재실행). 시작 전에 desktopCaptureStash를 \
            이미 nil로 비웠으므로 이 태스크 자체가 그 stash를 되돌릴 유일한 경로다 — 끊으면 Desktop이 \
            로그아웃된 채 남고 되돌릴 방법이 없어진다.
            """,
    ]

    func testEveryBackgroundTaskFieldIsEitherCancelledByStopOrDocumented() throws {
        let lines = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Mobius/AccountsState.swift")
        let fields = Self.taskFieldNames(in: lines)
        let stop = Self.stopBody(in: lines)

        XCTAssertGreaterThan(fields.count, 3, "스캔이 Task 필드를 못 찾았다 — 선언 모양이 바뀌었나?")
        XCTAssertFalse(stop.isEmpty, "stop() 본문을 못 찾았다 — 스윕이 통째로 무의미해진다")

        let unclassified = Self.unclassifiedTaskFields(
            fields: fields, stopBody: stop, documented: Set(Self.deliberatelyNotCancelled.keys))
        XCTAssertTrue(unclassified.isEmpty, """
            이 Task 필드들이 stop() 에서 취소되지도, 예외로 설명되지도 않았다: \
            \(unclassified.joined(separator: ", ")). 기능을 끈 뒤에도 계속 도는 작업은 화면에 \
            안 보이므로 사용자가 신고할 수 없다 — 취소하거나, 왜 취소하면 안 되는지(자격증명 \
            원자성) 위 목록에 적을 것.
            """)

        for name in Self.deliberatelyNotCancelled.keys {
            XCTAssertTrue(fields.contains(name),
                          "\(name) 은 이제 없는 필드다 — 예외 목록에서 지워야 목록이 현실을 설명한다")
        }
    }

    /// 위 스윕이 `stopEngine()` 을 보므로, `stop()` 이 그 함수를 안 부르면 스윕은 초록불인데
    /// 사용자가 기능을 꺼도 아무것도 안 멈추는 상태가 된다 — 두 조각을 잇는 줄을 직접 잠근다.
    /// (여기서만 소스로 확인하는 게 아니라 `testStopCancelsTheTickThatStartLaunched` 가 실제
    /// 취소까지 관찰한다. 이 테스트는 그 계약이 **어느 함수를 거치는지**를 고정한다.)
    func testStopDelegatesTeardownToStopEngine() throws {
        let lines = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Mobius/AccountsState.swift")
        guard let start = lines.firstIndex(where: {
            !MobiusTestSupport.isComment($0) && $0.contains("func stop()")
        }) else { return XCTFail("stop() 을 못 찾았다") }
        let indent = String(lines[start].prefix { $0 == " " })
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line == indent + "}" { break }
            body.append(line)
        }
        XCTAssertTrue(body.contains { !MobiusTestSupport.isComment($0) && $0.contains("stopEngine()") },
                      "stop() 이 stopEngine() 을 부르지 않으면 취소 스윕은 아무것도 지키지 못한다")
    }

    /// 위 스윕이 **실제로 무언가를 잡는지**(결함 프로토콜 3) — 통과만 보면 아무것도 안 지키는
    /// 스캔과 구별할 수 없다. 새 필드를 하나 주입하고 stop() 에는 넣지 않은 소스를 먹인다.
    func testTaskFieldSweepRejectsANewFieldThatStopIgnores() {
        let lines = """
            @MainActor final class AccountsState {
                private var usageTask: Task<Void, Never>?
                private var ghostTask: Task<Void, Never>?
                var usageTaskForTesting: Task<Void, Never>? { usageTask }
                private func stopEngine() {
                    timer?.invalidate()
                    usageTask?.cancel()
                }
            }
            """.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let fields = Self.taskFieldNames(in: lines)
        XCTAssertEqual(fields, ["usageTask", "ghostTask"],
                       "계산 프로퍼티는 남의 필드를 내주는 창구라 스윕 대상이 아니다")
        XCTAssertEqual(
            Self.unclassifiedTaskFields(fields: fields, stopBody: Self.stopBody(in: lines),
                                        documented: []),
            ["ghostTask"],
            "취소도 설명도 없는 필드를 못 잡으면 위 스윕은 초록불만 주는 장식이다")
    }

    // MARK: - 취소가 **효과**를 갖는 지점

    /// 취소는 중단이 아니다 — 이미 큐에 오른 태스크는 취소돼도 몸체를 그대로 돌기 시작하고,
    /// 틱의 `await` 가 전부 취소 인지형인 것도 아니다. 자격증명 스왑은 동기라 중간에 끊지
    /// 못하므로(끊으면 그게 더 큰 사고다) **시작하기 전에** 물러나야 한다. 그 관문이 `apply`
    /// 하나다: 자동 전환과 그 알림은 전부 여기를 지나고, 사용자의 수동 전환은 `performSwitch`
    /// 로 따로 가므로 이 확인에 걸리지 않는다.
    func testTheAutomaticSwitchChokepointBailsOutOnACancelledTick() throws {
        let lines = try MobiusTestSupport.sourceLines(
            of: "Sources/PokeTokenBarExtended/Mobius/AccountsState.swift")
        XCTAssertTrue(Self.bailsOutWhenCancelled(function: "private func apply(", in: lines), """
            apply() 가 취소 확인 없이 decision 을 처리한다 — 기능을 끈 뒤에도 진행 중이던 틱이 \
            계정을 바꾸고 알림까지 띄운다.
            """)
        XCTAssertTrue(Self.bailsOutWhenCancelled(function: "func tick()", in: lines),
                      "이미 큐에 오른 틱은 취소돼도 몸체를 돌기 시작한다 — 틱 입구에서도 확인해야 한다")
    }

    func testTheChokepointScanRejectsAFunctionWithoutTheCheck() {
        let without = ["    private func apply(_ d: Decision) async {", "        switch d {"]
        XCTAssertFalse(Self.bailsOutWhenCancelled(function: "private func apply(", in: without),
                       "확인이 없는 함수를 통과시키면 이 스캔은 장식이다")
    }

    // MARK: - 소스 스캐너 (순수 함수 — 위 주입 테스트들이 직접 먹인다)

    /// `… var <name>: Task<…>?` **저장** 프로퍼티의 이름. 계산 프로퍼티(`{ … }`)는 작업을 들고
    /// 있는 게 아니라 남의 필드를 내주는 창구라 제외한다(예: `tickTaskForTesting`).
    static func taskFieldNames(in lines: [String]) -> [String] {
        lines.compactMap { line -> String? in
            guard !MobiusTestSupport.isComment(line), line.contains(": Task<"),
                  !line.contains("{"),
                  let varRange = line.range(of: "var "),
                  let colon = line.range(of: ": Task<", range: varRange.upperBound..<line.endIndex)
            else { return nil }
            let name = line[varRange.upperBound..<colon.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
    }

    /// 진행 중인 작업을 실제로 취소하는 함수의 본문 — 같은 들여쓰기의 닫는 괄호까지.
    ///
    /// `stop()` 이 아니라 `stopEngine()` 을 보는 이유: 이중 writer 가드(Phase 6)가 생기면서
    /// 엔진을 내리는 경로가 둘이 됐다 — 사용자가 기능을 끄는 `stop()`, 그리고 기존 Mobius.app
    /// 이 감지돼 자동으로 물러나는 경로. 두 경로가 **같은** 취소 목록을 써야 해서 취소는
    /// `stopEngine()` 한 곳에 모았고, 이 스윕도 그 함수를 본다. `stop()` 이 그 함수를 실제로
    /// 부르는지는 `testStopDelegatesTeardownToStopEngine` 이 본다.
    static func stopBody(in lines: [String]) -> [String] {
        guard let start = lines.firstIndex(where: {
            !MobiusTestSupport.isComment($0) && $0.contains("func stopEngine()")
        }) else { return [] }
        let indent = String(lines[start].prefix { $0 == " " })
        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line == indent + "}" { return body }
            body.append(line)
        }
        return body
    }

    static func unclassifiedTaskFields(
        fields: [String], stopBody: [String], documented: Set<String>
    ) -> [String] {
        fields.filter { name in
            guard !documented.contains(name) else { return false }
            return !stopBody.contains {
                !MobiusTestSupport.isComment($0) && $0.contains("\(name)?.cancel()")
            }
        }
    }

    /// 해당 함수가 **첫 실행문 근처에서** 취소를 확인하고 물러나는지. 뒤쪽에 있으면 이미
    /// 부작용을 낸 뒤라 의미가 없으므로 선언 후 12개 실행문 안만 본다(주석은 세지 않는다).
    static func bailsOutWhenCancelled(function: String, in lines: [String]) -> Bool {
        guard let start = lines.firstIndex(where: {
            !MobiusTestSupport.isComment($0) && $0.contains(function)
        }) else { return false }
        var statements = 0
        for line in lines[(start + 1)...] {
            if MobiusTestSupport.isComment(line)
                || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.contains("guard !Task.isCancelled") { return true }
            statements += 1
            if statements > 12 { return false }
        }
        return false
    }
}
