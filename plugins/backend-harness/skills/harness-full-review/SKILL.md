---
name: harness-full-review
description: >
  기존 코드베이스 전체를 code-quality → perf-analyzer → security-checker → ops-checker →
  code-reviewer 순으로 검토하는 체인. harness-orchestrate가 "기존 코드 전체 검토"/"코드 리뷰 해줘"
  요청을 이 경로로 판단했을 때 사용한다. 자동 수정 사이클 진입 전 사용자 확인 게이트를 포함한다.
allowed-tools: Read Write Edit Grep Glob Bash(./mvnw:*) Bash(./gradlew:*) Bash(git diff:*)
compatibility: Requires Java 17+, Spring Boot 3.x+ (정확한 버전은 프로젝트 CLAUDE.md의 JAVA_VERSION/SPRING_BOOT_VERSION), Maven(./mvnw) 또는 Gradle(./gradlew) wrapper, git.
---

# harness-full-review — 전체 코드 검토 체인

## Chain

```
code-quality → perf-analyzer → security-checker → ops-checker → code-reviewer
```

이 체인의 4개 에이전트(`code-quality`/`perf-analyzer`/`security-checker`/`ops-checker`)는
기본적으로 **보고 전담**(ISSUES/SNIPPETS/VULNERABILITIES만 출력)이다. fix 담당으로 전환되는
시점은 아래 Gate를 통과한 이후, `harness-review-cycle`에 진입했을 때뿐이다.

## 실행 순서

1~4. `code-quality` → `perf-analyzer` → `security-checker` → `ops-checker` 순서로 호출하고
   각 `ISSUES`/`SNIPPETS`/`VULNERABILITIES`를 수집한다 (이 단계는 파일을 수정하지 않는다).
5. `code-reviewer` 호출. `PRIOR_AGENTS: code-quality, perf-analyzer, security-checker, ops-checker` 전달.

## Gate — 자동 수정 사이클 진입 전 사용자 확인 (필수)

`code-reviewer`가 FAIL을 출력해도 자동으로 수정에 들어가지 않는다. 기존 코드를 다수 파일에 걸쳐
자동 수정할 수 있으므로 반드시 아래 형식으로 먼저 확인한다.

```
[REVIEW GATE] 전체 검토에서 FAIL N건이 발견되었습니다.
자동 수정 대상: {파일·이슈·담당 에이전트 요약}
수정 사이클을 진행할까요? (진행 / 리포트만 보고 종료 / 일부 이슈만 선택)
```

- **"진행"** → `harness-review-cycle` 스킬 문서로 위임 (최대 3회).
- **"리포트만"** → `ISSUES`를 `SUMMARY`에 정리하고 종료.
- **확인은 사이클당 1회**: 동의 후 시작된 사이클의 2·3회차는 다시 묻지 않고 자동 재검토한다
  (이 게이트는 "기존 코드를 건드릴지"를 한 번 결정하기 위한 것이다).

## 산출물 — `chain-report.json`

`harness-api-build`와 동일한 파일에 `"chain": "harness-full-review"`로 기록한다.
`steps`에는 4개 보고 전담 에이전트의 `issues`/`summary`가 담긴다.

## 완료 보고

```
====================================
  harness-full-review 완료
====================================
code-quality:     {N}건 (HIGH 이상 {n})
perf-analyzer:    {N}건 (HIGH 이상 {n})
security-checker: {N}건 (HIGH 이상 {n} — CRITICAL {n} 포함)
ops-checker:      {N}건 (HIGH 이상 {n})
code-reviewer:    {PASS/PASS_WITH_WARNINGS/FAIL} (재검토 {N}/3회, 게이트: {진행/리포트만})
====================================
```
