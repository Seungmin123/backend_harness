---
name: harness-bugfix
description: >
  버그 수정 전용 체인. 수정 전에 버그를 재현하는 실패 테스트를 먼저 작성하고, 수정 후 그 테스트가
  통과하는지로 완료를 판정한다("재현 → 수정 → 검증" 순서, engineering-guidelines.md 4번 원칙 적용).
  "버그 고쳐", "버그 수정", "오류 수정", "이거 안 돼" 요청이 harness-orchestrate에서 이 경로로
  판단됐을 때 사용한다.
allowed-tools: Read Write Edit Grep Glob Bash(./mvnw:*) Bash(./gradlew:*) Bash(git diff:*)
compatibility: Requires Java 17+, Spring Boot 3.x+ (정확한 버전은 프로젝트 CLAUDE.md의 JAVA_VERSION/SPRING_BOOT_VERSION), Maven(./mvnw) 또는 Gradle(./gradlew) wrapper, git.
---

# harness-bugfix — 버그 수정 체인 (재현 우선)

## 왜 재현이 먼저인가

버그 수정은 "무엇이 잘못됐는지"를 코드로 고정(=실패 테스트)하지 않고 고치면, 실제로 그 버그를
고쳤는지 확인할 방법이 없다 (`.claude/rules/engineering-guidelines.md` 4번 "목표 중심으로
실행하라" 참조). `harness-api-build`의 RED→GREEN 순서와 같은 원칙이며, 버그 수정에서는
"재현 테스트"가 RED에 해당한다.

## Chain

```
qa-engineer (재현 테스트 작성, RED 확인)
    → {증상에 맞는 단일 에이전트} (수정, GREEN 확인)
    → qa-engineer (회귀 테스트 보강 — 필요시)
    → code-reviewer (최종 검토)
```

## 실행 순서

1. **재현 테스트 작성**: `qa-engineer`를 `FOCUS: 버그 재현 — {버그 증상 설명}`으로 호출한다.
   - 반드시 **버그가 있는 현재 코드에서 실패하는 테스트**를 먼저 작성한다.
   - `./mvnw -Dtest={테스트클래스} test`(Gradle: `./gradlew test --tests {테스트클래스}`)로
     RED(실패)를 확인하고 로그를 남긴다.
   - 이미 통과한다면(재현 실패) 버그 설명을 사용자에게 되묻는다 — 추측으로 진행하지 않는다
     (`.claude/rules/engineering-guidelines.md` 1번).
   - RED 확인 후 재현 테스트를 `test: [RED] {버그 요약}` 형식으로 커밋한다
     (커밋 직전 사용자 확인 — `CLAUDE.md` 협업 규칙. `harness-api-build`와 동일한 커밋 규약).

2. **원인 파악 및 수정 담당 결정**: 증상에 따라 `harness-orchestrate` 스킬 문서의
   "단일 에이전트 호출" 표를 기준으로 담당을 정한다 (로직 오류 → `api-developer`, 보안 결함이
   버그의 원인 → `security-checker`, 성능 저하가 버그의 원인 → `perf-analyzer` 등). FOCUS에
   1단계에서 작성한 재현 테스트 경로와 실패 원인 가설을 전달한다.

3. **GREEN 확인**: 수정 담당 에이전트가 수정을 마치면 같은 테스트 실행 명령(RED 단계와 동일)으로
   재현 테스트가 통과하는지 확인한다. GREEN 확인 후 수정 파일을 `fix: [GREEN] {버그 요약}`
   형식으로 커밋한다 (동일 확인 규칙). 통과하지 않으면 2단계로 돌아가되, 원인 가설을 갱신해
   `FOCUS`에 반영한다(무한 반복 방지를 위해 `harness-review-cycle` 스킬 문서와
   동일하게 최대 3회로 제한하고 초과 시 동일한 에스컬레이션 형식으로 보고한다).

4. **회귀 테스트 보강**: 버그의 원인이 다른 입력 조합에서도 재발할 수 있다고 판단되면
   `qa-engineer`를 다시 호출해 Edge Case를 보강한다(`.claude/rules/testing-conventions.md` 참조).
   과도한 보강은 하지 않는다 — 이 버그와 직접 관련된 케이스만 추가한다
   (`.claude/rules/engineering-guidelines.md` 2, 3번 — 요청 이상으로 확장하지 않는다).

5. **최종 검토**: `code-reviewer` 호출. `CONTEXT`에는 최초 버그 신고 원문을 전달하고,
   `TARGET`에는 재현 테스트 파일 + 수정된 파일만 전달한다(무관한 파일 변경 여부는
   code-reviewer Step 3에서 사이드 이펙트로 탐지된다).

## 완료 보고

```
====================================
  harness-bugfix 완료
====================================
재현 테스트:   {테스트 클래스} — RED 확인
원인:          {한 줄 요약}
수정 담당:     {에이전트명}
검증:          {테스트 클래스} — GREEN 확인 ({N}회 시도)
회귀 테스트:   {추가 여부 및 케이스 수}
code-reviewer: {PASS/PASS_WITH_WARNINGS}
====================================
```
