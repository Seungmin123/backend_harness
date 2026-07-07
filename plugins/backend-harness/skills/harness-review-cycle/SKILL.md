---
name: harness-review-cycle
description: >
  code-reviewer가 FAIL 판정을 내렸을 때 실행되는 최대 3회 수정→재검토 루프. harness-api-build와
  harness-full-review 양쪽에서 재사용한다. FAIL 이슈 유형별 수정 담당 에이전트 매핑, 회차 카운터
  표기, 3회 초과 시 에스컬레이션 형식을 담당한다. 단독으로 트리거되지 않고 항상 상위 체인 스킬
  또는 /review 명령에서 호출된다.
allowed-tools: Read Write Edit Grep Glob Bash(./mvnw:*)
compatibility: Requires Java 17, Spring Boot 3.x, Maven wrapper (./mvnw), git.
---

# harness-review-cycle — 검토-수정 반복 사이클

## 기본 규칙

- **최대 반복 횟수**: 3회. 초과 시 사용자에게 에스컬레이션하고 자동 진행을 중단한다.
- **PASS_WITH_WARNINGS**: 재검토를 트리거하지 않는다. 경고 항목은 SUMMARY에 기록 후 종료.
- **반복 카운터**: 각 사이클 시작 시(1회차 최초 검토 포함) `[REVIEW CYCLE N/3]`을 출력한다.
- **오케스트레이터가 수정 에이전트를 호출**: `code-reviewer`는 판정과 이슈 분류만 수행하며
  수정 에이전트를 직접 호출하지 않는다(그럴 수도 없다 — `code-reviewer`에는 Edit/Write 권한이
  없다). 이 스킬(=오케스트레이터 역할)이 ISSUES에 명시된 수정 담당 에이전트를 순서대로 호출한 뒤
  `code-reviewer`를 재호출한다.
- **수정 에이전트의 Plan First 예외**: 사이클 내에서 fix 담당으로 호출된 에이전트(`api-developer`
  포함 전 에이전트 공통)는 Plan을 출력하되 직전 FAIL 항목(FOCUS)을 근거로 **사용자 확인 없이 바로
  수정에 진행**한다. 절대 규칙 1(Plan First)보다 이 예외가 우선한다 — 사이클은 최대 3회로 한정되고
  매 회차 `code-reviewer`가 재게이트하기 때문이다. 단, **`SecurityConfig`·인증/인가·인프라 인접
  변경**이 포함된 경우 해당 변경 내역을 사이클 출력에 **명시적으로 요약**해 가시성을 확보한다.

## 사이클 진입 게이트 (호출한 체인에 따라 다름)

| 진입 경로 | 사이클 진입 방식 |
|---|---|
| `harness-api-build` (신규 API 체인) | **자동 진행**. 새로 만드는 코드이므로 즉시 발동한다. |
| 단독 `api-developer`/`qa-engineer` 호출 후 `code-reviewer` FAIL | **자동 진행**. (단, 수정 과정에서 요청 범위 밖 기존 파일 변경이 필요하면 그 시점에 멈추고 확인을 요청한다.) |
| `harness-full-review` (전체 검토 체인) | **`harness-full-review`의 REVIEW GATE에서 이미 사용자 확인을 받은 뒤에만** 이 스킬이 호출된다. |
| 보고 전담 에이전트 단독 호출 분석 | 이 스킬은 호출되지 않는다 — 리포트만 출력하고 종료한다. |

## FAIL 시 수정 담당 에이전트 결정

FAIL 판정의 이슈 유형에 따라 수정 담당 에이전트를 결정한다. 이슈가 복수 유형에 걸치면 해당
에이전트를 순서대로 모두 호출한다.

| FAIL 이슈 유형 | 수정 담당 에이전트 |
|---|---|
| 요구사항 누락, 레이어 구현 오류, OpenAPI 누락 | `api-developer` |
| `@Valid` 누락, 보안 정책 위반, 시크릿 하드코딩 | `security-checker` |
| 테스트 누락, 커버리지 미달 | `qa-engineer` |
| 레이어 경계 위반, 설계 원칙 위반 | `code-quality` |
| 타임아웃·Retry·Circuit Breaker·Graceful Shutdown 누락, 트랜잭션 내 외부 호출 | `ops-checker` |
| 로깅 누락, Trace ID 전파 누락, 핵심 메트릭/헬스체크 누락 | `ops-checker` |
| N+1, 인덱스 미사용, 페이지네이션 부재 등 성능 결함 | `perf-analyzer` |

> **FOCUS 범위 엄수** (`.claude/rules/engineering-guidelines.md` 3번 "수술하듯 변경하라"): fix
> 담당으로 호출된 모든 에이전트는 `FOCUS`에 명시된 이슈만 수정한다. 수정하는 과정에서 무관한
> 문제(스타일, 네이밍, 인접 로직 등)를 발견해도 고치지 않고 `ISSUES`에 별도 항목으로만 보고한다.
> `code-reviewer`가 Step 3(사이드 이펙트 탐지)에서 이 범위 이탈을 줄 단위로 잡아낸다.

> **분석 에이전트의 fix 모드**: `code-quality`/`perf-analyzer`/`security-checker`/`ops-checker`는
> 일반 체인 통과 시 `ISSUES`(+`SNIPPETS`/`VULNERABILITIES`)만 출력하는 보고 전담이지만, 위 표에
> 따라 fix 담당으로 호출되면 SNIPPET 제시에 그치지 않고 해당 수정을 **기존 파일 범위 내에서** 직접
> 적용한다 — 이 4개 에이전트에는 `Write` 권한이 없으므로(`CLAUDE.md` "Tool 권한 및 모델 정책"
> 참조) 신규 파일 생성이 필요한 수정이면 그 시점에 멈추고 오케스트레이터에 `api-developer` 위임을
> 요청한다. 적용한 파일은 재검토를 위해 `code-reviewer`에 전달한다.
> (`api-developer`·`qa-engineer`는 `CREATED_FILES`를 산출하는 생산 에이전트로 이 표에서 제외된다.)

## 반복 사이클 흐름

```
[1회차] [REVIEW CYCLE 1/3] code-reviewer → FAIL
    → 이슈 유형별 수정 에이전트 호출 (자동)
    → 수정 완료 후 code-reviewer 재호출

[2회차] [REVIEW CYCLE 2/3] code-reviewer → FAIL
    → 동일하게 수정 에이전트 호출
    → code-reviewer 재호출

[3회차] [REVIEW CYCLE 3/3] code-reviewer → FAIL
    → 자동 진행 중단
    → 사용자에게 에스컬레이션 (아래 형식으로 출력)
```

## 재검토 시 컨텍스트 전달 규칙

- `TARGET`: 이번 사이클에서 수정된 파일만 전달 (전체 diff 아님)
- `CONTEXT`: 원본 요구사항 원문 유지 (매 사이클 동일)
- `PRIOR_AGENTS`: 해당 체인의 1회차와 동일하게 유지 (체인 유래인 경우 — 매 사이클 동일)
- `FOCUS`: 직전 code-reviewer가 지적한 FAIL 항목 목록을 명시

```
[AGENT: code-reviewer]
TARGET: {이번 사이클 수정 파일 목록}
CONTEXT: {최초 사용자 요청 원문}
PRIOR_AGENTS: {체인에서 실행된 보고 전담 에이전트 목록 — 해당 체인의 1회차와 동일하게 유지}
FOCUS: 직전 FAIL 항목 — {이슈1}, {이슈2}
REVIEW_CYCLE: N/3
```

## 3회 초과 시 에스컬레이션 출력 형식

```
[ESCALATION] 3회 검토-수정 사이클 후에도 FAIL 항목이 해소되지 않았습니다.
미해결 이슈:
  - [이슈 목록]
권장 조치:
  1. 아키텍처 수준의 재설계가 필요할 수 있습니다.
  2. 사용자가 직접 검토 후 수정 방향을 결정해주세요.
  3. 특정 이슈만 수동 수정 후 /review 로 재검토를 요청할 수 있습니다.
```

## 산출물

`chain-report.json`의 `review_cycle` 필드를 매 회차 갱신한다:
`{ "round": N, "max": 3, "verdict": "...", "unresolved": ["..."] }`.
3회 초과로 에스컬레이션되면 `"verdict": "ESCALATED"`로 남겨, 세션이 끊긴 뒤에도 `/review`로
재진입할 때 몇 회차까지 진행됐는지 알 수 있게 한다.
