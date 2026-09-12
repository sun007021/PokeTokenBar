---
summary: Mobius(Claude·Codex 계정 전환) 기능을 PokeTokenBar 에 통합하는 작업의 설계·단계·불변식.
read_when: mobius 통합 관련 코드를 만질 때, 상류(chattymin/PokeTokenBar) 변경을 rebase 할 때, 계정 전환·자격증명 경로를 리뷰할 때
---

# Mobius 통합 계획

이 포크는 [chussum/mobius](https://github.com/chussum/mobius) 의 Claude·Codex **계정 자동 전환**
기능을 PokeTokenBar 에 합친다. 기존 PokeTokenBar 기능은 전부 그대로 유지한다.

## 결정 사항 (확정)

| 항목 | 결정 | 이유 |
|---|---|---|
| 산출물 | 개인 포크 (상류 PR 아님) | 상류는 "읽기 전용 관찰자" 성격이라 자격증명 변경 기능은 별도 합의가 필요 |
| 1차 범위 | 핵심 전환만 | 계정 목록·수동/자동 전환·게이지·로그인. Desktop 동시 전환/멀티 Mac 동기화 UI 제외 |
| 데이터 경로 | `~/Library/Application Support/PokeTokenBar/mobius/` | 두 앱 병행 시 파일 경합 방지. 기존 Mobius 데이터는 1회 복사 마이그레이션 |
| 다국어 | **ko·en 만 번역**, 나머지 5개 슬롯은 en 값 | 개인 포크라 상류 기여 계획이 없다(사용자 결정 2026-09-12) |

### 다국어 규칙 (계정 전환 기능 한정)

`L.t(...)` 는 7개 인자가 필수라 슬롯을 비울 수 없다. 이 기능의 새 문자열은 **ko·en 만 제대로 쓰고
ja/es/fr/pt/de 슬롯에는 en 값을 그대로 넣는다.** 그 언어 사용자에게는 계정 탭만 영어로 보이고 나머지
앱은 모국어를 유지한다.

- **기존 PokeTokenBar 문자열은 건드리지 않는다** — 이 규칙은 계정 전환 기능에만 적용된다.
- Phase 4~5 에서 **이미 7개 언어로 번역된 항목은 그대로 둔다.** 되돌리는 건 순수한 손실이고, 각
  슬롯은 독립적으로 읽히므로 혼재는 무해하다.
- **7개 언어 레이아웃 테스트는 유지한다.** en 이 들어간 슬롯은 en 폭으로 측정될 뿐이고, 나중에 진짜
  번역이 들어올 때 폭 회귀를 잡아 준다. 테스트를 ko/en 만 도는 것으로 축소하지 마라.

`L.koEn(ko:en:)`(private) 이 en 을 5개 슬롯에 복제한다. 규칙이 지켜지는지는
`AccountsLocalizationTests` 가 양방향으로 잠근다 — 새 항목은 ja/es/fr/pt/de 가 en 과 같아야 하고,
이미 7개 언어가 든 기존 항목은 en 과 **달라야** 한다(되돌림 방지).

### 비-UI 계층에서 `L` 얻기

이 기능의 문구 대부분은 뷰가 아니라 `AccountsState`(알림·배너)에서 만들어진다. 뷰의
`companion.l` 에 닿을 수 없으므로 **언어 미러**를 둔다 — `UsageStore.localizationLanguage` 와
같은 관례다.

| 자리 | 규칙 |
|---|---|
| 보관 | `AccountsState.localizationLanguage`(기본 `.systemDefault`), 접근자 `private var l: L` |
| 시드 | `AppDelegate.applicationDidFinishLaunching` — `store.localizationLanguage` 바로 옆 |
| 갱신 | `SettingsView` 언어 픽커 setter. **빠뜨리면 언어를 바꿔도 알림·배너만 옛 언어로 남는다** |

★ **`AccountsState.init` 의 두 문구(로드 실패·프로바이더 복구)만 시스템 언어로 렌더된다** —
`MobiusLaunchSequence` 가 `AccountsState` 를 `CompanionStore` 보다 **먼저** 만들고(그 순서는 데이터
보존이라 못 바꾼다) init 은 자기 저장 프로퍼티를 읽을 수도 없다. 손상된 `accounts.json` 에서만
나오는 문구이고, 사용자가 앱 언어를 시스템과 다르게 고른 경우에만 어긋난다 —
`UsageStore` 가 같은 미러에서 감수한 것과 같은 틈이다.

★ **`LoginFlowError`·`DesktopCoordinatorError` 는 `LocalizedError` 가 아니다.**
`errorDescription` 은 언어를 받을 수 없기 때문이다. 사용자 문구는 `L.accountsErrorMessage(_:)` 가
만들고(`SaveTransferError` 와 같은 구조), 그래서 이 에러를 **표시하는 자리는 반드시 그 매핑을
거쳐야 한다** — 그냥 `localizedDescription` 을 쓰면 "The operation couldn't be completed…" 가 그대로
노출되는 조용한 품질 저하가 된다. 회귀 가드는 `AccountsLocalizationTests`.

★ **한글 리터럴 검사가 `Sources/PokeTokenBar/Mobius/` 까지 훑는다**
(`LocalizedUILiteralTests`). 이 계층은 뷰가 아니라 새 문구를 더할 때 `companion.l` 이 눈앞에 없어
리터럴로 되돌아가기 쉽다. 진단 로그(`AppLog.write`/`NSLog`)는 사용자 노출이 아니라 제외하되,
**리터럴이 하나뿐인 줄에서만** 건너뛴다 — 로그와 표시 문구가 한 줄에 섞이면 검사한다.

## 왜 이식이 싼가

`Sources/MobiusCore/` 는 **사용자 노출 문자열이 0개**다(한글은 전부 주석). 의존성은
`Foundation` + `Security` 뿐이고 `Bundle.module`·리소스를 쓰지 않는다. 따라서 엔진 4,100줄과
테스트 290개는 **무수정으로 이식**되고, 비용은 UI 재배치(430pt→360pt)와 다국어에만 발생한다.

## 코드 배치 (상류 rebase 부담 최소화)

Mobius 코드는 격리한다:

```
Sources/MobiusCore/              # 통째 복사. 수정 1곳(appSupport 주입)만 허용
Sources/PokeTokenBar/Mobius/     # AccountsState, LoginFlow, 마이그레이션, 계정 UI
Tests/MobiusCoreTests/           # 통째 복사, 무수정
```

기존 파일 수정은 **4곳으로 제한**한다 — `Package.swift`, `UI/PopoverView.swift`(탭 추가),
`UI/SettingsView.swift`(섹션 1개), `PokeTokenBarApp.swift`(상태 생성·수명주기). 이 경계를 넘는
변경은 rebase 충돌 비용으로 되돌아온다.

## 데이터 보존 불변식 (깨지면 사용자 진행이 사라진 것처럼 보인다)

1. **번들 ID `io.github.chattymin.poketokenbar` 와 앱 이름 `PokeTokenBar` 를 바꾸지 않는다.**
   바꾸면 Application Support 디렉터리와 UserDefaults 도메인이 통째로 갈린다(파일은 남지만
   사용자에겐 "데이터가 날아갔다"로 보인다).
2. `AppStatePaths.directory()` · `companion-state.json` · `CompanionState` 스키마에 손대지 않는다.
   Mobius 데이터는 **하위 디렉터리** `mobius/` 에만 쓴다.
3. 새 UserDefaults 키는 `mobius.` 접두사를 붙인다 (상류 키와의 충돌 및 rebase 충돌 예방).
   통합 시점 기준 양쪽 키 충돌은 0개였다 — 접두사는 미래 충돌 예방용이다.
4. **앱 시작 순서**: `migrateLegacyStorageIfNeeded()` → `MobiusDataMigration.migrateIfNeeded()` →
   `AccountsState` 생성. 세 단계가 모두 "대상이 이미 있으면 건너뛴다"로 게이트되므로 뒤가 먼저
   돌면 앞이 영영 안 돈다 — 아래 '앱 시작 순서' 절.

## 이식 규칙 (Mobius 가 실패로 배운 것 — 재현 금지)

- **Keychain 쓰기는 반드시 `security` CLI 경유.** 네이티브 `SecItemUpdate` 를 쓰면 macOS 가 파티션
  리스트를 그 앱의 cdhash 로 재도장해, Claude Code·Claude Desktop 의 자격증명 읽기마다 암호창이
  뜬다(되돌리려면 사용자가 직접 파티션을 고쳐야 한다). `SystemKeychain` 의 이 구조를 건드리지 않는 것이
  대응이다. `security dump-keychain` 은 승인창 폭탄이라 어떤 경우에도 실행 금지.
- **토큰의 진실은 Keychain, 이메일은 `~/.claude.json`.** 파일(`.credentials.json`)은 낡을 수 있어
  파일 우선 읽기로 바꾸면 낡은 토큰과 최신 이메일이 짝지어져 라이브 로그인이 오염된다.
- **지속화 struct 에 필드를 추가할 땐 관대한 `init(from:)`** (`decodeIfPresent ?? 기본값`).
  구버전 파일이 `keyNotFound` 로 디코드 실패하면 빈 스토어가 파일을 덮어써 계정이 영구 유실된다.
- **고정 frame `List` 에서 행 삽입+삭제 조합 금지.** 풀 전체를 한 List 의 행으로 두고 primary 는
  `moveDisabled`, 전환은 "행 이동"으로 모델링한다. 안 그러면 primary 전환 시 스크롤 오프셋이
  어긋난 채 방치돼 UI 가 겹쳐 보인다.
- **주기 타이머가 만드는 작업에는 재진입 가드**, 그리고 **스캔 락을 쥔 채 도는 구간의 비용이 입력
  크기에 비례하면 메인 스레드가 그 락을 동기적으로 기다리게 하지 않는다.** 대용량 세션 로그
  환경에서 UI 영구 정지(행)로 나타난 부류다.
- **익명 로그 라인으로 계정 상태를 기록하지 않는다.** Claude 세션 로그 hit 에는 계정 식별자가 없어
  전환 직후 옛 계정의 에러가 새 계정에 박힌다 → 자동 전환이 통째로 죽는다. 판정은 usage API 로 한다.
- **이식한 코드는 호스트 앱의 환경 가드 관례를 따른다.** PTB 는 번들이 아닐 수 있다 — raw 바이너리
  개발 실행(`swift run` / `./.build/debug/PokeTokenBar`)과 `swift test` 가 그 경우다. 알림
  (`UNUserNotificationCenter`)·로그인아이템(`SMAppService`)·프로덕션 로그처럼 **번들을 요구하는 API
  는 `AppEnv.isBundledApp` 뒤에 둔다**. `UNUserNotificationCenter.current()` 는 번들이 아니면 nil 을
  주는 게 아니라 **예외를 던져 프로세스를 죽인다** — Mobius 는 항상 `.app` 이라 이 가드가 없었고,
  이식된 `AccountsState.start()`/`notify()` 가 그대로 넘어와 기능 토글을 켠 raw 바이너리가 시작 즉시
  죽었다. Phase 5~8 에서 새 알림·로그인아이템 코드를 더할 때 같은 게이트를 붙일 것. 회귀 가드는
  `Tests/PokeTokenBarTests/MobiusBundleGuardTests.swift`(진짜 트리거 호출 2건 + 소스 스캔 1건),
  부류 전체 기록은 `docs/reference/defect-log.md` §알림.

## Phase 1 실측

- **Swift 언어 모드 경계**: 이 패키지는 `swift-tools-version: 6.0` 이지만 `MobiusCore` 타깃만
  `.swiftLanguageMode(.v5)` 로 핀 고정했다. 엔진 4,100줄을 무수정으로 이식하려면 상류(Mobius)와
  같은 언어 모드가 필요했기 때문이다. Phase 3 에서 Swift 6 모드인 PokeTokenBar 쪽(`@MainActor`
  상태 계층, 예: `AccountsState`)이 v5 로 컴파일된 `MobiusCore` 타입을 actor 경계 너머로 넘길 때
  Sendable 마찰이 예상된다 — v1 대응은 필요한 지점에 `@preconcurrency import MobiusCore` 를
  붙이는 것으로 하고, `MobiusCore` 자체를 Swift 6 모드로 옮기는 것은 별도 후속으로 남긴다.
- **상류의 타이밍 민감 테스트**: `SessionKeySettingsRenderingTests` 는 오프스크린 윈도우를 key 로
  만들고 500ms 고정 대기 후 스크롤 결과를 측정하므로 머신 부하에 따라 실패할 수 있다. Mobius 코드를
  0줄 더한 기준선 커밋에서도 동일하게 재현되므로 이 통합의 회귀가 아니다 — **전체 스위트 판정 시
  이 테스트 1건만 실패하는 것은 통과로 간주한다.**
- ★ **스위트 시간이 수십 분으로 튀면 코드가 아니라 맥이 잔 것이다 — `caffeinate -i swift test` 로
  돌려라.** 방치한 채 배터리로 돌리면 macOS 가 유휴 판정으로 sleep 에 들어가고, 그때 시간 대기
  중이던 테스트가 그 시간만큼 통째로 늘어난다(그리고 **깨어나서 통과한다** — 행이 아니다).
  실측 2026-09-12: 같은 커밋이 40.1s·39.2s 로 돌다가 한 번 **1,186s** 가 나왔고,
  `SwitcherTests.testResaveOnSwitchClearsReauthOfOutgoingAccount` 한 건이 **992.4s** 를 먹었다.
  `pmset -g log` 에 `10:37:54 Entering Sleep … 'Maintenance Sleep' … **994 secs**` 가 그대로
  찍혀 있다(두 번째 sleep 146s 는 `UsageStoreTests` 163s 로 나타났다). 느린 스위트가 **매번
  다른 곳으로 옮겨 다니는 것**이 신호다 — 그때 timed wait 을 쥐고 있던 테스트가 걸릴 뿐이라,
  `sample` 로 잡히는 스택(CFNetwork 등)은 원인이 아니라 그 순간 주차돼 있던 자리다. 이 함정은
  `MobiusCore` 테스트처럼 네트워크·Keychain 을 아예 안 쓰는(`InMemoryKeychain` + 임시 디렉터리)
  스위트에서도 똑같이 나타나므로, **"우리 코드가 뭔가 붙잡고 있다"로 오귀인하기 쉽다.**

## 단계

- [ ] **Phase 0 — 안전망**: 데이터 백업(디렉터리 + UserDefaults), 포크·클론, 기준선 `swift test`
- [ ] **Phase 1 — 엔진 이식**: `MobiusCore` + `MobiusCoreTests` 복사, `Package.swift` 배선. **UI 변화 0**
- [ ] **Phase 2 — 경로 주입 + 마이그레이션**: `MobiusEnvironment.appSupport` 주입,
      기존 `~/Library/Application Support/Mobius/` → `PokeTokenBar/mobius/` 1회 **복사**(이동 아님),
      `secrets/` 0600 권한 보존 검증, 멱등성 테스트
- [ ] **Phase 3 — 상태 계층**: `AppState` → `AccountsState`(ObservableObject 유지, sync·update 제거),
      `LoginFlow`·`ToolInventory`·`ClaudeCLI` 이식, 토글 off 면 타이머 미생성. 유휴 CPU A/B 측정
- [ ] **Phase 4 — 계정 탭**: `PopoverTab.accounts`, 360pt 카드 리스트 재작성
- [ ] **Phase 5 — 설정 섹션**: 자동 전환(Claude/Codex) · 계정 추가 · 게이지 · 미리 전환 · 알림
- [ ] **Phase 6 — 안전장치**: 이중 writer 가드(`dev.chussum.mobius` 실행 감지), 전환 시
      `OAuthAccessTokenCache.shared.invalidate()`, 슬립 시 틱 정지
      (★ **디스플레이** 슬립은 신호로 쓰지 않기로 했다 — Phase 3b 판단. 메뉴바 애니메이션과 달리
      자동 전환은 정확성 기능이라, 화면만 꺼진 채 `claude`/`codex` 세션이 계속 도는 흔한 상황에서
      틱을 멈추면 소진돼도 전환이 안 되고 사용자는 막힌 CLI 로 돌아온다. 쓴다면 **시스템** 슬립
      (`NSWorkspace.willSleepNotification`/`didWakeNotification`)이어야 하고, 깨어날 때 즉시 1틱을
      돌리는 경로가 함께 필요하다)
- [ ] **Phase 7 — 다국어**: 계정 전환 문구 65개를 `L` 로 이관 완료(lproj·`Bundle.module` 금지).
      Phase 3 이 만든 임시 경유지 `Sources/PokeTokenBar/Mobius/MobiusStrings.swift` 는
      호출부가 사라져 **삭제**했다. 항목은 `Localization.swift` 의 `accountsNotify*`(알림)·
      `accountsError*`(배너·실패 사유·에러 매핑) 접두사로 모여 있고, 비-UI 계층이 `L` 을 얻는
      방법은 아래 §다국어 규칙 참조
- [ ] **Phase 8 — 게이트·빌드**: `test-gate.sh` 화이트리스트 갱신, 고정 서명 인증서, `/Applications` 설치

## 앱 시작 순서 (`MobiusLaunchSequence`)

`AppDelegate.applicationDidFinishLaunching` 은 Mobius 초기화를 하드코딩된 호출 줄이 아니라
`MobiusLaunchSequence.run { … }` 로 돈다. 순서가 **한 곳**(`MobiusLaunchSequence.order`)에만
적혀 있어야 테스트가 프로덕션 경로까지 같이 고정할 수 있기 때문이다.

| 순서 | 단계 | 먼저 돌면 잃는 것 |
|---|---|---|
| 1 | `legacyStorageRename` (`TokenMac` → `PokeTokenBar`) | `!fileExists(new)` 게이트 — 누가 먼저 `AppStatePaths.directory()` 를 부르면(호출만으로 디렉터리가 **생긴다**) TokenMac 시절 도감·토큰이 영영 이전 안 됨 |
| 2 | `mobiusDataMigration` (`…/Mobius` → `PokeTokenBar/mobius`) | `alreadyMigrated` 판정이 **대상 디렉터리 존재** — `AccountStore` 가 먼저 저장해 `mobius/` 를 만들면 기존 Mobius.app 계정·비밀 스냅샷이 영영 이전 안 됨 |
| 3 | `accountStateCreation` (`AccountsState` + 조건부 `start()`) | — |

`Tests/PokeTokenBarTests/MobiusLaunchSequenceTests.swift` 가 각 순서를 **실제 파일 연산으로
재생**해 데이터가 실제로 넘어왔는지 본다(순서 단언만으로는 "왜 그 순서인지"를 증명 못 한다).
프로덕션 함수 셋(`AppDelegate.migrateLegacyStorageIfNeeded(base:)`,
`MobiusDataMigration.migrateIfNeeded(source:)`, `AppStatePaths.directory()`)을 `PTB_STATE_DIR`
로 임시 디렉터리에 격리해 그대로 호출한다 — 그 함수들의 `base`/`source` 파라미터는 **테스트
주입 전용**이고, 함정 당사자인 대상 경로 유도는 일부러 주입하지 않는다.

마이그레이션 실패는 **앱 시작을 막지 않는다** — 계정 전환은 부가 기능인데 거기서 던지면 포켓몬
앱 전체가 못 뜬다. `AppLog` 에 남기고 계속 진행하며, 실패하면 대상 디렉터리가 안 만들어지므로
다음 실행에서 자연히 재시도된다.

## 기능 토글 `mobius.enabled` (기본 꺼짐)

`MobiusFeature.isEnabled` 가 꺼져 있으면 `AccountsState.start()` 를 부르지 않는다. `start()` 가
타이머(3초 틱)·세션 로그 스캔·Keychain 워밍업·알림 권한 요청·`DistributedNotificationCenter`
옵저버의 **유일한** 진입점이므로, 꺼진 상태의 런타임 동작은 기능을 넣기 전과 같다. 객체는
생성되지만 `AccountStore.init` 은 디스크를 읽기만 하고 아무 디렉터리도 만들지 않는다.

수동 확인: `defaults write io.github.chattymin.poketokenbar mobius.enabled -bool YES`.
토글 UI 는 Phase 5.

## 상태 계층을 `ObservableObject` 로 두는 이유

PokeTokenBar 는 `@Observable`(Observation), Mobius `AppState` 는 `@Published` 다. 변환하면 diff 가
1,850줄 전체로 번져 위 "이식 규칙" 들이 손상될 위험이 크다. SwiftUI 는 두 시스템의 공존을 허용하므로
`AccountsState` 는 `ObservableObject` 그대로 두고 `.environmentObject` 로 붙인다.

## 알려진 트레이드오프 (v1 에서 감수)

- **로그 스캐너 중복**: PokeTokenBar 의 `LocalUsageReader` 와 Mobius 의 `SessionLogWatcher` 가 같은
  `~/.claude/projects` · `~/.codex/sessions` 트리를 각자 훑는다. v1 은 각자 캐시·오프셋으로 공존하고,
  Phase 3 에서 유휴 CPU 를 실측해 기준선 대비 +0.5%p 를 넘으면 통합을 앞당긴다.
- **Desktop 동시 전환 코드는 남되 UI 미노출**: `performSwitch`/`reload` 에 얽혀 있어 제거 수술이
  오히려 회귀 위험이다. 토글 기본 off 로 잠재운다.
- **두 앱 병행 실행 금지**: Keychain·`~/.claude.json` 은 전역 자원이라 Mobius.app 과 이 앱이 동시에
  스왑하면 자격증명이 오염된다. Phase 6 의 실행 감지 가드가 이를 막는다(아래 '이중 writer 가드').

## 이중 writer 가드 (Phase 6)

`MobiusCoexistence` 가 `dev.chussum.mobius`(원본 Mobius.app)의 실행을 감지하면 이 앱의 계정 전환
엔진이 **물러난다.** 조정이 아니라 양보다 — 원본에는 이 협상에 참여할 코드가 없으므로 아는 쪽이
항상 물러나야 한 명만 남는다(`SingleInstance` 와 같은 방향의 결정).

막으려는 사고는 **에러로 나타나지 않는다**: 토큰(Keychain)과 이메일(`~/.claude.json`)이 서로 다른
시점에 갱신되는 찰나를 상대가 읽으면 낡은 토큰과 최신 이메일이 한 프로필에 짝지어지고, 사용자의
라이브 로그인까지 조용히 오염된다(원본 '실패 기록 1').

| 축 | 결정 |
|---|---|
| 감지 | `NSRunningApplication.runningApplications(withBundleIdentifier:)`. 판정은 순수 함수 `isBlocked(by:)` 로 분리했고 `isTerminated` 인스턴스는 세지 않는다 — 세면 Mobius.app 을 종료해도 자동 재개가 영영 안 온다 |
| 주기 | 5초(`AccountsState.externalAppWatchInterval`). **엔진 틱에 얹지 않는다** — 막힌 동안엔 틱이 없어 복구 신호를 줄 주체가 사라진다 |
| 범위 | 마스터 토글이 켜져 있는 동안만. `stop()` 은 감시 타이머까지 걷어 "끄면 아무것도 안 돈다"를 유지한다 |
| 자격증명 경로 | `apply`(자동)·`manualSwitch`/`performSwitch`(수동)·`addAccount` 는 캐시된 플래그가 아니라 **그 자리에서 다시 판정**한다(`externalAppBlocksSwitching`) — 5초 창 안에 상대가 뜨는 경우를 좁힌다 |
| 표시 | 계정 탭 상단 주황 블록 + 설정 섹션 안내 행, 그리고 탭 컨트롤 `.disabled`. 설명 없이 기능만 죽으면 고장으로 읽힌다 |
| 재개 | Mobius.app 이 종료되면 5초 안에 자동(앱 재시작 불필요). 팝오버를 열면 그 자리에서도 재판정한다 |

엔진을 내리는 경로가 둘이 되었으므로(사용자의 `stop()`, 가드의 자동 후퇴) 진행 중 작업의 취소는
`stopEngine()` 한 곳에 모았다 — `AccountsEngineLifecycleTests` 의 Task 필드 스윕도 그 함수를 본다.

감지기는 `AccountsState` 에 주입한다. 진짜 `NSRunningApplication` 조회를 그대로 두면 **개발자
Mac 에 Mobius.app 이 떠 있는지에 따라 스위트 전체가 흔들리므로**, `MobiusTestSupport` 의 기본값은
"안 돌고 있다"이고 가드 자체는 `MobiusCoexistenceGuardTests` 가 양쪽 값을 주입해 검증한다.

### 전환 후 한도 캐시 무효화

`OAuthAccessTokenCache`(PokeTokenBar 쪽)는 Claude 자격증명을 인메모리로 들고 있어, 계정을 바꿔도
**옛 토큰으로 조회가 성공한다.** 증상은 "한도가 안 나온다"가 아니라 **A 계정 숫자가 B 계정 게이지로
그려지는 것**이라 화면만 봐서는 틀렸다는 걸 알 수 없다(`CredentialSwitchCacheTests` 가 잠근 #227 과
같은 부류).

- **통지 지점**: `AccountsState.onSwitched` — `switcher.switchTo` **성공 직후**. 자동(`apply`)·
  수동(`performSwitch`)이 서로 다른 경로라 **양쪽 모두**에 건다. 실패(throw)하면 부르지 않는다 —
  멀쩡한 토큰을 버리고 재조회를 부르는 것이 이 기능의 유일한 비용이다.
- **결합 위치**: `AppDelegate.wireAccountSwitchToLimits()`. `AccountsState` 와 `UsageStore` 는
  서로를 모르고 둘 다 들고 있는 것은 델리게이트뿐이라, 새 전역 상태 대신 `store.onRefresh` 와 같은
  콜백 관례를 쓴다.
- **프로바이더 구분**: `MobiusSwitchSideEffects.invalidatesClaudeLimitCache` — Codex 한도는
  세션 로그에서 오므로 이 캐시와 무관하다. 안 가르면 Codex 전환마다 헛된 Claude 재조회가 붙는다.
- **재조회**: `UsageStore.refresh()`. 진행 중이면 그쪽이 코얼레싱해 완료 후 1회 더 도므로, 옛
  토큰으로 끝난 조회가 최종값으로 남지 않는다. `refreshLimitTokenFromKeychain()` 은 쓰지 않는다 —
  `allowKeychainPrompt: true` 라 전환 때마다 키체인 승인창을 부를 수 있다.
