---
name: harness-api-build
description: >
  신규 REST API를 처음부터 구축하는 테스트-선행(TDD) 체인. api-developer(스켈레톤) →
  qa-engineer(RED) → api-developer(구현·GREEN) → security-checker → ops-checker → code-reviewer
  순으로 자동 실행하며 각 단계 산출물을 chain-report.json에 기록한다.
  harness-orchestrate가 "신규 API 개발"/"기능 구현" 요청을 이 경로로 판단했을 때 사용한다.
allowed-tools: Read Write Edit Grep Glob Bash(./mvnw:*) Bash(./gradlew:*) Bash(git diff:*)
compatibility: Requires Java 17+, Spring Boot 3.x+ (정확한 버전은 프로젝트 CLAUDE.md의 JAVA_VERSION/SPRING_BOOT_VERSION), Maven(./mvnw) 또는 Gradle(./gradlew) wrapper, git.
---

# harness-api-build — 신규 API 구축 체인

## Chain — 테스트 선행 (TDD)

```
api-developer          (Phase 1 Plan 제시 → 사용자 CONFIRM 필수 → Phase 2a 스켈레톤)
    → qa-engineer          (Plan·스켈레톤 기준 테스트 작성 → RED 확인)
    → api-developer        (Phase 2b 구현 → GREEN 확인)
    → security-checker     (새 엔드포인트 보안 검토)
    → ops-checker           (타임아웃·Circuit Breaker·Graceful Shutdown·로깅/메트릭 검토)
    → code-reviewer         (최종 독립 검토)
```

> **왜 테스트가 구현보다 먼저인가**: 구현을 끝낸 뒤 테스트를 쓰면 테스트가 구현의 현재 동작을
> 정당화하는 방향으로 작성될 위험이 있다(구현이 틀려도 통과하는 테스트). 테스트를 Plan 기준으로
> 먼저 고정하면 구현은 그 테스트를 통과하는 것으로만 완료를 판정한다
> (`engineering-guidelines.md` 4번 — 검증 기준 선행 정의). Java는 대상 클래스가 없으면 테스트가
> 컴파일되지 않으므로, **컴파일만 가능한 스켈레톤**(Phase 2a)을 먼저 만들어 RED가 성립하게 한다.

> **`code-quality` 미포함 이유**: `api-developer`가 Phase 1 Plan 단계에서 레이어 구조·트랜잭션
> 경계·설계 원칙을 자체 체크리스트로 검증하므로 신규 구현 체이닝에서는 제외한다. 기존 코드 개선이
> 필요하다고 판단되면 그 시점에 `code-quality`를 별도 호출한다.
>
> **`perf-analyzer` 조건부 편입**: `CLAUDE.md` 운영 환경 설정이 **`CACHE_SERVER ≠ none` 또는
> `DB_READ_REPLICA: true`**면 perf-analyzer를 체인에 포함한다 (4단계에서 security/ops와 함께
> 병렬 dispatch, `PRIOR_AGENTS`에도 추가) — 캐시 TTL/키 설계와 readOnly 라우팅은 구현 시점에
> 검증하지 않으면 운영에서야 드러나기 때문이다. 두 조건 모두 아니면 미포함: `api-developer`가
> Repository 생성 시 N+1을 `@EntityGraph`/fetch join으로 처리하고 cursor 페이지네이션을 강제하므로
> 기본 성능 리스크는 구현 시점에 1차 차단된다. 이 경우에도 복잡한 조회/집계가 포함된 신규 API는
> 구현 후 `perf-analyzer` 별도 호출을 권장한다.

## Gate — Plan 확인 (필수, 자동 통과 불가)

`api-developer` Phase 1이 엔드포인트 목록·스키마·레이어 구조·트랜잭션 경계·인증 방식을 제시하면
**반드시 사용자 확인을 기다린다.** 진입 시점에는 근거로 삼을 이전 에이전트 SUMMARY가 없기 때문이다
(절대 규칙 1 "Plan First"와 동일 게이트).

### 태스크 크기 게이트 (Plan 확인에 포함)

Plan의 규모가 **엔드포인트 3개 초과 또는 신규 클래스 10개 초과**면, Plan에 태스크 분할안
(엔드포인트 그룹별로 이 체인을 여러 번 실행)을 함께 제시하고 사용자가 선택하게 한다.
RED→GREEN 사이클이 커질수록 실패 테스트의 원인 추적이 어려워지고 리뷰 diff가 비대해지기
때문이다. 사용자가 분할 없이 진행을 선택하면 그대로 진행하되 `chain-report.json`에
`"size_gate": "waived"`를 기록한다.

## 실행 순서

1. `api-developer` 호출(Phase 1 Plan → 사용자 CONFIRM → **Phase 2a 스켈레톤**) →
   `CREATED_FILES`, `ENDPOINTS`, `SUMMARY`(인증 방식 포함) 수신.
   스켈레톤은 DTO·시그니처·레이어 골격까지만 — 비즈니스 로직 본문은
   `UnsupportedOperationException`을 던지며, `./mvnw compile`(또는 `./gradlew compileJava`)
   성공을 확인한다.
2. `qa-engineer` 호출(**RED 작성**), `CONTEXT`에 1번의 `SUMMARY`(Plan의 스키마·예외 시나리오·인증
   방식 포함) 전달 → `CREATED_FILES`, `COVERAGE_GAP` 수신.
   - 테스트는 **Plan을 근거로** 작성한다 (스켈레톤의 현재 동작이 아니라).
   - 작성한 테스트를 실행해 **RED(실패)를 확인하고 실패 로그를 남긴다**. 스켈레톤 상태에서
     통과하는 테스트는 구현을 검증하지 못하는 무효 테스트다 — 재작성한다
     (`harness-bugfix`의 RED 유효성 판정과 동일 원칙).
   - **RED 커밋**: `test: [RED] {기능 요약}` 형식으로 테스트 파일만 커밋한다
     (커밋 직전 사용자 확인 — `CLAUDE.md` 협업 규칙 준수. RED 증거를 히스토리에 남기는 것이 목적).
3. `api-developer` 재호출(**Phase 2b 구현**), `FOCUS`에 2번의 테스트 파일 목록 전달.
   RED 테스트를 통과할 만큼만 구현하고(과잉 구현 금지 — `engineering-guidelines.md` 2번)
   같은 테스트 실행으로 **GREEN을 확인**한다. GREEN 실패가 반복되면 최대 3회에서 중단하고
   `harness-review-cycle`과 동일한 에스컬레이션 형식으로 보고한다.
   - **GREEN 커밋**: `feat: [GREEN] {기능 요약}` 형식으로 구현 파일을 커밋한다 (동일 확인 규칙).
4. `security-checker`와 `ops-checker`를 **병렬로 dispatch** — 둘 다 보고 전담이라 상호 독립이다
   (`CLAUDE.md` "병렬 실행과 실행 실패 처리" 참조). `VULNERABILITIES`/`ISSUES`/`SNIPPETS` 수신.
   운영값 조건(`CACHE_SERVER ≠ none` 또는 `DB_READ_REPLICA: true`) 충족 시 `perf-analyzer`도
   같은 병렬 dispatch에 포함한다 (위 "조건부 편입" 참조).
   크래시 시 1회 재시도 → 재실패면 건너뛰고 `PRIOR_AGENTS`에서 제외, 완료 보고에 미실행 명시.
5. **기계 검증 게이트 (code-reviewer 선행 조건)**: 전체 테스트(`./mvnw test` 또는
   `./gradlew test`)를 실행해 **green임을 확인한 뒤에만** `code-reviewer`를 호출한다.
   red면 code-reviewer를 호출하지 않는다 — 실패 테스트를 `FOCUS`로 지정해 구현 결함이면
   `api-developer`, 테스트 자체 결함이면 `qa-engineer`에게 먼저 수정시키고 이 게이트를 재실행한다.
   (LLM 리뷰는 기계 검증이 통과한 결과물에 대해서만 의미가 있다.)
6. `code-reviewer` 호출. `PRIOR_AGENTS: security-checker, ops-checker` 전달
   (4단계에서 perf-analyzer가 편입됐으면 목록에 추가 — 실제로 완주한 에이전트만), `CONTEXT`에는
   **최초 사용자 요청 원문**(1~5단계 SUMMARY가 아님)을 전달한다.
   code-reviewer는 Step 4에서 `chain-report.json`의 `tdd.red_confirmed`를 검증한다.
7. `VERDICT: FAIL` → `harness-review-cycle` 스킬 문서로 위임한다. 사이클 진입 방식은
   **자동 진행**이다 — 신규 API 체인은 새로 만드는 코드이므로 사용자 확인 없이 즉시 수정 사이클을
   발동한다.
   `VERDICT: PASS` 또는 `PASS_WITH_WARNINGS` → 완료.

각 에이전트 호출은 `CLAUDE.md`의 "에이전트 호출 형식"을 따른다.

## Plan First 적용 범위

체이닝 전체에 Plan First를 적용하면 에이전트마다 사용자 확인이 필요해져 흐름이 끊긴다.
아래 기준으로 적용 범위를 제한한다.

- **체이닝 진입 전 (api-developer Phase 1)**: 엔드포인트 목록·스키마·레이어 구조를 제시하고
  **사용자 확인 필수** (태스크 크기 게이트 포함).
- **이후 에이전트 (qa-engineer(RED) → api-developer(2b) → … → code-reviewer)**: 이전 에이전트의
  SUMMARY를 근거로 자동 진행. RED/GREEN **커밋 직전 확인**은 Plan First가 아니라 `CLAUDE.md`
  협업 규칙(커밋 전 사용자 확인)에 따른 것이다.
  각 에이전트는 ISSUES를 출력한 뒤 다음 에이전트로 넘어가며, 사용자 개입이 필요한 판단(예:
  아키텍처 변경 권고)이 생기면 그 시점에 멈추고 확인을 요청한다.

## 산출물 — `chain-report.json`

```json
{
  "chain": "harness-api-build",
  "target": "사용자 프로필 조회/수정 API",
  "plan_confirmed": true,
  "size_gate": "passed",
  "tdd": {
    "red_confirmed": true,
    "red_test_files": ["src/test/java/.../UserControllerIntegrationTest.java"],
    "green_confirmed": true
  },
  "steps": [
    { "agent": "api-developer", "phase": "2a-skeleton", "created_files": ["..."], "summary": "..." },
    { "agent": "qa-engineer", "created_files": ["..."], "coverage_gap": ["..."] },
    { "agent": "api-developer", "phase": "2b-implement", "created_files": ["..."], "summary": "..." },
    { "agent": "security-checker", "vulnerabilities": ["..."] },
    { "agent": "ops-checker", "issues": ["..."] }
  ],
  "review_cycle": { "round": 1, "max": 3, "verdict": "PASS", "issues": [], "unresolved": [] }
}
```

- `review_cycle.issues` / `unresolved`의 기록 규칙은 `harness-review-cycle` 스킬 문서의
  "산출물" 섹션을 따른다 (FAIL 이슈의 구조화 저장 — 재시도 FOCUS의 원천).
- **`chain-report.json`은 커밋하지 않는다** — 로컬 작업 상태 파일이며 `/harness-init`이
  `.gitignore`에 등록한다. 미등록 상태면 이 스킬이 첫 기록 전에 `.gitignore`에 추가한다.
- 동시 체인 실행은 지원하지 않는다. 시작 시점에 진행 중(최종 verdict 없음)인
  `chain-report.json`이 이미 있으면 덮어쓰지 말고 사용자에게 먼저 확인한다.

세션이 끊긴 뒤 이 스킬이 재호출되면 `chain-report.json` 존재 여부를 확인하고, 있으면
"이전 체인이 {마지막 단계}까지 진행되었습니다. 이어서 진행할까요?"라고 사용자에게 먼저 묻는다.

## 완료 보고

```
====================================
  harness-api-build 완료
====================================
Plan:             CONFIRMED (크기 게이트: {passed/waived})
api-developer:    스켈레톤 {N}개 클래스 → 구현 완료, 엔드포인트 {N}개
qa-engineer:      테스트 {N}개 작성 — RED 확인 → GREEN 확인 (커밋: test:[RED] / feat:[GREEN])
security-checker: 취약점 {N}건 (조치 완료)
ops-checker:      이슈 {N}건 (조치 완료)
code-reviewer:    {PASS/PASS_WITH_WARNINGS} (재검토 {N}/3회, TDD 증거 확인)
====================================
```
