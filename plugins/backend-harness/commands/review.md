---
description: code-reviewer를 단발성으로 재호출해 현재 변경분 또는 지정한 범위를 재검토한다.
argument-hint: "[TARGET]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git show:*)
---

# /review — code-reviewer 단발 재호출

`CLAUDE.md`의 "슬래시 명령어" 섹션에 정의된 명령이다. `code-reviewer` 에이전트를 단독으로
재호출하는 진입점이며, 체이닝(harness-api-build/harness-full-review)을 새로 시작하지 않는다.

## 1. TARGET 결정

- `$ARGUMENTS`가 비어 있으면: 현재 작업 트리의 변경분(`git diff HEAD` — 스테이징 + 미스테이징)을
  TARGET으로 한다.
- `$ARGUMENTS`가 있으면(파일/패키지 경로): 해당 범위만 TARGET으로 한다.

## 2. CONTEXT / FOCUS / PRIOR_AGENTS 결정

- **CONTEXT**: 직전 사이클과 동일하게 **최초 사용자 요청 원문**을 유지한다. 현재 세션에 남아있지
  않으면 추측하지 말고 사용자에게 원본 요청 내용을 되묻는다
  (`.claude/rules/engineering-guidelines.md` 1번 — 가정 표면화).
- **FOCUS**: 직전 `code-reviewer` FAIL 또는 미해결 이슈 목록이 있으면 그대로 전달한다. 없으면 생략한다.
- **PRIOR_AGENTS**: 원래 체인에서 실제로 실행된 보고 전담 에이전트 목록을 그대로 유지한다
  (신규 API 체인 유래: `security-checker, ops-checker` / 전체 검토 체인 유래: `code-quality,
  perf-analyzer, security-checker, ops-checker`). 단독 호출로 시작된 작업이었다면 생략한다.

## 3. 에스컬레이션과의 관계 — 회차 리셋

`harness-review-cycle` 스킬 문서가 3회 초과로 에스컬레이션한 뒤, 사용자가 일부
이슈를 수동으로 수정하고 이 명령으로 재검토를 요청하는 것이 일반적인 진입 경로다. 이 경우
회차 카운터는 **새 사이클 1/3으로 리셋**한다(이전 사이클은 종료된 것으로 간주).
`code-reviewer`가 다시 FAIL을 내면 `harness-review-cycle`에 **새 사이클로** 재진입한다(회차를
이어가지 않는다).

## 4. 실행

`CLAUDE.md`의 "에이전트 호출 형식"에 따라 `code-reviewer`를 호출한다:

```
[AGENT: code-reviewer]
TARGET: {1번에서 결정한 대상}
CONTEXT: {최초 사용자 요청 원문}
PRIOR_AGENTS: {2번에서 결정 — 없으면 생략}
FOCUS: {2번에서 결정 — 없으면 생략}
REVIEW_CYCLE: 1/3
```

`VERDICT: FAIL`이면 `harness-review-cycle` 스킬 문서의 사이클로 진입한다(새 사이클
1/3). `PASS` / `PASS_WITH_WARNINGS`이면 결과를 보고하고 종료한다.
