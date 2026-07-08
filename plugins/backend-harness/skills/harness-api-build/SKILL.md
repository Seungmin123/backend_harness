---
name: harness-api-build
description: >
  신규 REST API를 처음부터 구축하는 체인. api-developer → qa-engineer → security-checker →
  ops-checker → code-reviewer 순으로 자동 실행하며 각 단계 산출물을 chain-report.json에 기록한다.
  harness-orchestrate가 "신규 API 개발"/"기능 구현" 요청을 이 경로로 판단했을 때 사용한다.
allowed-tools: Read Write Edit Grep Glob Bash(./mvnw:*) Bash(./gradlew:*) Bash(git diff:*)
compatibility: Requires Java 17+, Spring Boot 3.x+ (정확한 버전은 프로젝트 CLAUDE.md의 JAVA_VERSION/SPRING_BOOT_VERSION), Maven(./mvnw) 또는 Gradle(./gradlew) wrapper, git.
---

# harness-api-build — 신규 API 구축 체인

## Chain

```
api-developer          (Phase 1 Plan 제시 → 사용자 CONFIRM 필수 → Phase 2 구현)
    → qa-engineer          (구현된 클래스 기준 테스트 생성)
    → security-checker     (새 엔드포인트 보안 검토)
    → ops-checker           (타임아웃·Circuit Breaker·Graceful Shutdown·로깅/메트릭 검토)
    → code-reviewer         (최종 독립 검토)
```

> **`code-quality` 미포함 이유**: `api-developer`가 Phase 1 Plan 단계에서 레이어 구조·트랜잭션
> 경계·설계 원칙을 자체 체크리스트로 검증하므로 신규 구현 체이닝에서는 제외한다. 기존 코드 개선이
> 필요하다고 판단되면 그 시점에 `code-quality`를 별도 호출한다.
>
> **`perf-analyzer` 미포함 이유**: `api-developer`가 Repository 생성 시 N+1 위험 연관관계를
> `@EntityGraph`/fetch join으로 처리하고, 대용량 조회를 cursor 페이지네이션으로 강제하므로 기본적인
> 성능 리스크는 구현 시점에 1차 차단된다. 단, **트래픽 규모가 크거나 복잡한 조회/집계가 포함된
> 신규 API는 구현 후 `perf-analyzer`를 별도 호출**할 것을 권장한다.

## Gate — Plan 확인 (필수, 자동 통과 불가)

`api-developer` Phase 1이 엔드포인트 목록·스키마·레이어 구조·트랜잭션 경계·인증 방식을 제시하면
**반드시 사용자 확인을 기다린다.** 진입 시점에는 근거로 삼을 이전 에이전트 SUMMARY가 없기 때문이다
(절대 규칙 1 "Plan First"와 동일 게이트).

## 실행 순서

1. `api-developer` 호출 → `CREATED_FILES`, `ENDPOINTS`, `SUMMARY`(인증 방식 포함) 수신
2. `qa-engineer` 호출, `CONTEXT`에 1번의 `SUMMARY` 전달 → `CREATED_FILES`, `COVERAGE_GAP` 수신
3. `security-checker` 호출 → `VULNERABILITIES`, `SNIPPETS`, `CVE_UPGRADES` 수신
4. `ops-checker` 호출 → `ISSUES`, `SNIPPETS` 수신
5. `code-reviewer` 호출. `PRIOR_AGENTS: security-checker, ops-checker` 전달, `CONTEXT`에는
   **최초 사용자 요청 원문**(1~4단계 SUMMARY가 아님)을 전달한다.
6. `VERDICT: FAIL` → `harness-review-cycle` 스킬 문서로 위임한다. 사이클 진입 방식은
   **자동 진행**이다 — 신규 API 체인은 새로 만드는 코드이므로 사용자 확인 없이 즉시 수정 사이클을
   발동한다.
   `VERDICT: PASS` 또는 `PASS_WITH_WARNINGS` → 완료.

각 에이전트 호출은 `CLAUDE.md`의 "에이전트 호출 형식"을 따른다.

## Plan First 적용 범위

체이닝 전체에 Plan First를 적용하면 에이전트마다 사용자 확인이 필요해져 흐름이 끊긴다.
아래 기준으로 적용 범위를 제한한다.

- **체이닝 진입 전 (api-developer Phase 1)**: 엔드포인트 목록·스키마·레이어 구조를 제시하고
  **사용자 확인 필수**.
- **이후 에이전트 (qa-engineer → code-reviewer)**: 이전 에이전트의 SUMMARY를 근거로 자동 진행.
  각 에이전트는 ISSUES를 출력한 뒤 다음 에이전트로 넘어가며, 사용자 개입이 필요한 판단(예:
  아키텍처 변경 권고)이 생기면 그 시점에 멈추고 확인을 요청한다.

## 산출물 — `chain-report.json`

```json
{
  "chain": "harness-api-build",
  "target": "사용자 프로필 조회/수정 API",
  "plan_confirmed": true,
  "steps": [
    { "agent": "api-developer", "created_files": ["..."], "summary": "..." },
    { "agent": "qa-engineer", "created_files": ["..."], "coverage_gap": ["..."] },
    { "agent": "security-checker", "vulnerabilities": ["..."] },
    { "agent": "ops-checker", "issues": ["..."] }
  ],
  "review_cycle": { "round": 1, "max": 3, "verdict": "PASS" }
}
```

세션이 끊긴 뒤 이 스킬이 재호출되면 `chain-report.json` 존재 여부를 확인하고, 있으면
"이전 체인이 {마지막 단계}까지 진행되었습니다. 이어서 진행할까요?"라고 사용자에게 먼저 묻는다.

## 완료 보고

```
====================================
  harness-api-build 완료
====================================
Plan:             CONFIRMED
api-developer:    {CREATED_FILES 수} 파일 생성, 엔드포인트 {N}개
qa-engineer:      테스트 {N}개 생성, 커버리지 갭 {N}건
security-checker: 취약점 {N}건 (조치 완료)
ops-checker:      이슈 {N}건 (조치 완료)
code-reviewer:    {PASS/PASS_WITH_WARNINGS} (재검토 {N}/3회)
====================================
```
