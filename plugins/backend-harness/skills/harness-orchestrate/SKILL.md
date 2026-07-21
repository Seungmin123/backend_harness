---
name: harness-orchestrate
description: >
  사용자 요청을 분석해 단일 에이전트 호출 / 신규 API 체인 / 전체 검토 체인 중 라우팅 경로를
  결정하는 최상위 오케스트레이터. "기능 구현", "API 만들어", "엔드포인트 추가", "전체 코드 리뷰",
  "기존 코드 검토" 요청 시 가장 먼저 이 스킬로 판단한다. 실제 구현/검토 실행은 harness-api-build,
  harness-full-review, 또는 단일 에이전트 호출에 위임하며 이 스킬 자체는 파일을 수정하지 않는다.
allowed-tools: Read Grep Glob Bash(test:*)
compatibility: Requires Java 17+, Spring Boot 3.x+ (정확한 버전은 프로젝트 CLAUDE.md의 JAVA_VERSION/SPRING_BOOT_VERSION) project with Maven(./mvnw) 또는 Gradle(./gradlew) wrapper, git.
---

# harness-orchestrate — 라우팅 결정 스킬

이 스킬은 **판단만** 한다. 실행 로직은 각 하위 스킬/에이전트에 위임한다.

## 1단계: 단일 호출 vs 체이닝 판단

| 요청 키워드 / 상황 | 라우팅 |
|---|---|
| "API 만들어", "엔드포인트 추가", "Controller 생성" (기존 파이프라인에 점진적 추가) | 단일 `api-developer` 호출 → 종료 시 `qa-engineer → code-reviewer` |
| "테스트 작성", "커버리지", "테스트 케이스" | 단일 `qa-engineer` 호출 |
| "리팩토링", "코드 품질", "클래스가 너무 커" (범위가 명확한 국소 요청) | 단일 `code-quality` 호출 |
| "느려", "N+1", "쿼리 최적화", "성능" | 단일 `perf-analyzer` 호출 |
| "보안", "취약점", "OWASP", "인증/인가" | 단일 `security-checker` 호출 |
| "타임아웃", "Circuit Breaker", "재시도", "장애 대응", "로그", "트레이스", "메트릭", "모니터링", "헬스체크" | 단일 `ops-checker` 호출 |
| "신규 API 개발", "기능 구현" (테스트·보안·복원력·관찰성·리뷰가 아직 없는 상태에서 처음부터 구축) | → `harness-api-build` |
| "기존 코드 전체 검토", "코드 리뷰 해줘" | → `harness-full-review` |
| "버그 고쳐", "버그 수정", "오류 수정", "이거 안 돼", "왜 안 되지" (기존 동작이 기대와 다름) | → `harness-bugfix` |

> **"버그 수정" vs 위 단일 호출 표**: 증상이 명확히 한 카테고리(보안/성능/컨벤션)에 속하고
> 재현 테스트 없이도 원인이 자명한 사소한 수정이면 단일 에이전트 호출로 충분하다. 그렇지 않고
> "왜 이 입력에서 이런 결과가 나오는지 모르겠다"류의 요청이면 `harness-bugfix`로 라우팅한다
> (재현 테스트로 원인을 먼저 고정하는 쪽이 안전하다 — 판단이 모호하면 `harness-bugfix`를 우선한다).

## 2단계: 표현이 겹칠 때의 우선순위

단일 `api-developer` 호출 트리거("API 만들어", "엔드포인트 추가", "Controller 생성")와
`harness-api-build` 트리거("신규 API 개발", "기능 구현")는 표현이 겹친다. 충돌 시 아래 기준으로 구분한다.

- **`harness-api-build` 우선**: 신규 기능/엔드포인트를 **처음부터 구축**(테스트·보안·복원력·관찰성·
  리뷰가 아직 없는 상태)하는 요청.
- **단일 `api-developer` 호출**: 이미 파이프라인(테스트·보안 설정·리뷰)이 갖춰진 **기존 기능에
  엔드포인트를 점진적으로 추가/수정**하는 경우로 한정한다. 이 경우에도 신규 엔드포인트에 대한
  테스트 보강과 최종 검토가 필요하므로 작업 종료 시 `api-developer → qa-engineer → code-reviewer`
  순으로 마무리한다(절대 규칙 4 "Reviewer Always Last" 보장).
- **판단이 모호하면 `harness-api-build`로 처리한다** (누락 위험이 더 크기 때문).

## 3단계: 위임

- 신규 API 체인 → `harness-api-build` 스킬 문서를 읽고 그 지시를 따른다.
- 전체 검토 체인 → `harness-full-review` 스킬 문서를 읽고 그 지시를 따른다.
- 버그 수정 → `harness-bugfix` 스킬 문서를 읽고 그 지시를 따른다 (재현 테스트를
  먼저 작성해 원인을 고정한 뒤 수정한다 — 구현이 테스트보다 먼저인 다른 체인과 순서가 반대다).
- 단일 호출 → 위 표에 명시된 에이전트를 `CLAUDE.md`의 "에이전트 호출 형식"에 따라 직접 호출한다.
  (단일 호출도 절대 규칙 4에 따라 종료 전 `code-reviewer`를 거친다 — 각 에이전트 `.md`의
  `NEXT_AGENT` 출력 계약 참고.)

## 이어하기 (Resume)

라우팅 판단 자체는 파일을 생성하지 않는다. 체이닝이 시작되면 하위 스킬이 프로젝트 루트의
`chain-report.json`에 진행 상태를 기록한다. 이 스킬이 재호출됐을 때 `chain-report.json`이
이미 존재하면, 어느 단계까지 진행됐는지 요약해 "이어서 진행할까요?"라고 먼저 확인한다.
