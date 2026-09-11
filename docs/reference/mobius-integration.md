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
      `OAuthAccessTokenCache.shared.invalidate()`, 디스플레이 슬립 시 틱 정지
- [ ] **Phase 7 — 다국어**: 약 115개 문자열 × 7개 언어. `L` 구조체 방식(lproj·`Bundle.module` 금지)
- [ ] **Phase 8 — 게이트·빌드**: `test-gate.sh` 화이트리스트 갱신, 고정 서명 인증서, `/Applications` 설치

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
  스왑하면 자격증명이 오염된다. Phase 6 의 실행 감지 가드가 이를 막는다.
