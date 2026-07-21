# backend-harness

Java / Spring Boot 백엔드용 Claude Code 하네스 플러그인.
전문 에이전트 7종, 체인 스킬 5종, 안전 훅 3종, 프로젝트 스캐폴딩 커맨드를 제공한다.

> **처음이라면 이 순서로 읽는다**:
> ① 이 README의 "구성"과 "워크스루" (하네스가 무엇을 어떻게 돌리는지) →
> ② 프로젝트의 `CLAUDE.md` (절대 규칙·운영 환경 값·심각도 척도 등 공유 계약) →
> ③ `rules/` 중 자기 작업 영역의 파일 1~2개 (rule ID 체계 감 잡기) →
> ④ 에이전트·스킬 문서는 다 읽을 필요 없다 — 체인이 알아서 호출하며, 문제가 생겼을 때
> 해당 문서와 아래 "트러블슈팅"을 찾아 읽으면 된다.

## 설치와 사용

```
/plugin marketplace add Seungmin123/backend_harness
/plugin install backend-harness@backend-harness
```

프로젝트 저장소에 `templates/project-settings.json` 내용을 `.claude/settings.json`으로 커밋해
두면, 팀원이 그 저장소를 열 때 Claude Code가 자동으로 설치를 제안한다 — 개인별 수동 설치가
필요 없다.

설치 후 각 프로젝트에서 **`/harness-init`** 을 한 번 실행하면 운영 환경 값 4개를 묻고
CLAUDE.md/AGENTS.md·`.claude/rules/`·docs 골격을 스캐폴딩한다. 이후 사용법은 프로젝트
CLAUDE.md의 "에이전트 라우팅 개요"를 따른다 — 자연어로 요청하면 라우팅은 자동이다.

## 구성 (Governance 배치)

| 위치 | 역할 | 로드 시점 |
|---|---|---|
| 프로젝트 루트 `CLAUDE.md` | 헌법 — 프로젝트 고유 값(운영 환경 설정)·절대 규칙·공유 계약(호출 형식, 역할 경계) | 매 세션 자동 |
| `agents/` (플러그인) | 전문 서브에이전트 정의 (역할·입출력 계약·tools·model) | 호출 시 |
| `skills/` (플러그인) | 체이닝·재시도 루프 같은 절차 | 트리거 문구에 따라 필요할 때만 |
| `commands/` (플러그인) | `/review`, `/harness-init` | 사용자 호출 시 |
| `hooks/` (플러그인) | 편집/커밋 시점에 결정적으로 실행되는 자동 검증 | 자동 (hooks.json으로 등록) |
| `rules/` (플러그인 → `/harness-init`이 프로젝트 `.claude/rules/`로 설치) | `paths:` 조건으로 자동 로드되는 상세 컨벤션 | 해당 파일 작업 시 자동 |

> **rules만 프로젝트에 복사되는 이유**: `paths:` 조건부 자동 로드는 프로젝트 `.claude/rules/`
> 위치를 전제로 하기 때문이다. 따라서 rules는 유일하게 드리프트가 가능한 구성요소다 —
> 프로젝트에서 rule을 수정했다면 반드시 이 저장소에도 PR로 반영한다.

## 에이전트 참조

| 에이전트 | 책임 | tools | model |
|---|---|---|---|
| api-developer | REST API 설계 및 구현 | Read, Write, Edit, Grep, Glob, Bash(mvnw/gradlew compile/test) | 세션 상속 |
| qa-engineer | 테스트 생성 및 커버리지 분석 | Read, Write, Edit, Grep, Glob, Bash(mvnw/gradlew test) | sonnet |
| code-quality | 설계 원칙 및 코드 품질 | Read, Grep, Glob, Edit, Bash(mvnw/gradlew checkstyle) | sonnet |
| perf-analyzer | 성능 이슈 탐지 | Read, Grep, Glob, Edit, Bash(mvnw/gradlew test) | sonnet |
| security-checker | 보안 취약점 탐지 | Read, Grep, Glob, Edit, Bash(mvnw/gradlew dependency-check) | sonnet |
| ops-checker | 복원력(타임아웃·Circuit Breaker·Graceful Shutdown) 및 관찰성(로깅·메트릭·헬스체크) | Read, Grep, Glob, Edit, Bash(mvnw/gradlew test) | sonnet |
| code-reviewer | 최종 독립 검토 (**Edit/Write 없음**) | Read, Grep, Glob, Bash(git diff/log/show) | sonnet |

tools/model 차등 부여는 프롬프트 지시가 아니라 실제 권한 제한이다. 새 에이전트를 추가할 때도
"새 파일을 만들어야 하는가 / 기존 파일만 고치면 되는가 / 절대 고치면 안 되는가"를 먼저 판단하고
frontmatter의 `tools`를 그에 맞게 좁힌다.

## 스킬 참조

| 스킬 | 역할 |
|---|---|
| harness-orchestrate | 단일 호출/신규 API 체인/전체 검토 체인 라우팅 판단 |
| harness-api-build | 신규 API 구축 체인 — TDD: 스켈레톤→테스트(RED)→구현(GREEN)→security→ops→reviewer, chain-report.json 기록 |
| harness-full-review | 전체 코드 검토 체인, 자동 수정 진입 전 REVIEW GATE 사용자 확인 |
| harness-bugfix | 버그 수정 체인 — 재현 테스트 먼저 작성(RED) → 수정 → 검증(GREEN) |
| harness-review-cycle | FAIL 시 최대 3회 수정→재검토 루프, fix-owner 매핑, 에스컬레이션 |

## 규칙 파일 참조 (rules/)

| 규칙 | 파일 | rule ID | `paths:` 범위 |
|---|---|---|---|
| API 설계 기준 | `api-convention.md` | `API-xx` | Controller/Request/Response/ExceptionHandler |
| 보안 정책 | `security-policy.md` | `SEC-xx` | 전체 `.java`, `application*.yml`/`.properties` |
| 레이어 아키텍처 | `layer-architecture.md` | `LAYER-xx` | 전체 `.java` |
| 복원력·관찰성 표준 설정 | `resilience-observability.md` | `RES-xx`/`OBS-xx` | 전체 `.java`, `application*.yml`/`.properties` |
| 성능·JPA, DB 마이그레이션 안전성 | `performance-jpa.md` | `PERF-xx` | 전체 `.java`, `application*.yml`, `db/migration/**`, `db/changelog/**` |
| 테스트 작성 컨벤션 | `testing-conventions.md` | `TEST-xx` | `src/test/java/**/*.java` |
| 엔지니어링 행동 규범 (Karpathy 기반) | `engineering-guidelines.md` | `ENG-01~04` | 전체 `.java` (main+test) |

**rule ID 규약**: 각 규칙 파일의 `##` 섹션 헤더에 ID가 붙어 있다. 에이전트의 이슈 보고는
위반한 rule ID를 인용한다 — 규칙이 개정돼도 어느 조항 위반인지 추적이 유지되고, rule 개정 시
해당 ID를 인용하는 에이전트를 grep으로 찾을 수 있다(하네스 개선 절차 2번). 어떤 rule에도
해당하지 않는 일반 판단 이슈는 `GEN`으로 표기한다. 섹션을 삭제해도 ID는 재사용하지 않는다.

> **데이터 기반 근거 보강 (TODO)**: 실제 코드 리뷰·장애 회고 데이터가 쌓이면 각 rule의
> `description`에 근거(예: "PR N건에서 지적된 항목")를 추가해 우선순위 판단 근거로 삼는다.

## Hooks 상세

- **git-guard** (`PreToolUse`, 모든 Bash): 위험 명령 2단계 가드.
  즉시 차단 — `git reset --hard`, force push, `git clean -f*`, `rm -rf`, `DROP TABLE` 등.
  확인 후 진행 — `commit --amend`, `rebase`, `branch -D`, `flyway:migrate` 등.
- **pre-commit** (`PreToolUse`, `git commit`만): `.env` 스테이징 → Checkstyle(전체 프로젝트) →
  TDD `[RED]` 커밋 정합(테스트 파일만 포함) → 하드코딩 시크릿(스테이징 변경분) 순서.
  하나라도 실패하면 커밋 차단(exit 2).
- **post-edit** (`PostToolUse`, Edit|Write): `.java` 편집 후 대응 테스트 자동 실행.
  실패 시 **오류로 승격(exit 2)** — 단 TDD 사이클 진행 중(`chain-report.json`의
  `tdd.green_confirmed != true`)이면 RED가 정상이므로 경고만. 멀티모듈이면 `-pl <모듈>`로
  해당 모듈만 실행.

세 훅 모두 **jq가 없으면 검사 없이 통과**한다(stderr 경고는 출력). `/harness-init`이 사전
점검에서 이를 확인한다.
훅은 Claude Code 세션만 보호하며, Codex/Gemini 등 다른 도구에서는 AGENTS.md 문서 경고에만 의존한다.

## 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| 커밋이 계속 차단된다 (Checkstyle) | pre-commit은 **프로젝트 전체 기준**이라 남이 만든 기존 위반도 걸린다. `./mvnw checkstyle:check`로 전체 현황을 확인하고, 기존 위반 정리는 별도 작업으로 분리한다 |
| `[RED]` 커밋이 차단된다 | RED 커밋에 `src/main` 파일이 섞였거나 `src/test` 파일이 없다 — RED 커밋은 테스트 파일만 담는다 |
| `.java` 편집마다 테스트 실패 오류(exit 2)가 뜬다 | 정상 동작이다(post-edit 승격). TDD 사이클 중인데 뜬다면 `chain-report.json`의 `tdd` 필드가 없거나 `green_confirmed`가 이미 true인 상태 — 체인 산출물 기록이 누락됐는지 확인한다 |
| 훅이 아무것도 안 잡는다 | `which jq` — 없으면 3종 모두 검사 없이 통과한다(stderr 경고만). `brew install jq` 후 재시도 |
| 체인이 중간에 끊겼다 (세션 종료 등) | 체인 스킬을 다시 호출하면 `chain-report.json`을 읽고 "이어서 진행할까요?"를 묻는다. 에스컬레이션(3회 초과) 후에는 수동 수정 → `/review`로 재진입 (회차 1/3 리셋) |
| code-reviewer가 TDD 증거 부재로 FAIL을 낸다 | `chain-report.json`에 `tdd.red_confirmed: true`가 기록됐는지 확인 — RED 확인을 건너뛴 체인 실행이 원인이다. qa-engineer를 fix 담당으로 RED부터 다시 밟는다 |
| 특정 검토 영역이 완료 보고에 "미실행"으로 나온다 | 해당 에이전트가 2회 크래시해 건너뛰었다는 뜻 — 그 영역은 **검토되지 않았다**. 해당 에이전트를 단독 호출해 보완한다 |

## 하네스 개선 절차

이 저장소가 하네스의 단일 원본(source of truth)이다.

1. 에이전트·스킬·훅·rules 수정은 이 저장소에 PR로 제출하고 팀 리뷰를 거친다.
2. **rule을 수정했다면 소비 에이전트·스킬을 grep으로 대조한다** (정합성 드리프트 방지 —
   과거 `api-convention.md` 응답 포맷 개편이 에이전트 본문에 전파되지 않아 리뷰 기준이
   갈라진 사례가 있다):
   ```bash
   # 수정한 rule 이름과, rule에서 바꾼 핵심 키워드(클래스명·필드명·용어) 양쪽으로 검색
   grep -rn "api-convention" agents/ skills/ commands/ templates/
   grep -rn "ApiResponse\|바꾼-키워드" agents/ skills/ commands/ templates/
   ```
   검색 결과에 걸린 문서의 해당 구절이 개편 후 규격과 일치하는지 확인하고 같은 PR에서 갱신한다.
   에이전트·스킬의 계약(입출력 필드, 심각도 등급, 게이트 조건)을 바꿀 때도 동일하게
   그 계약을 인용하는 문서를 grep으로 대조한다.
3. 머지 후 플러그인 버전(`.claude-plugin/plugin.json`의 `version`)을 올린다.
4. **미러 저장소에 동일 변경을 반영한다** — 이 플러그인은 두 저장소에서 유지된다
   (`kitbetter-web/player-harness`와 `Seungmin123/backend_harness`). 한쪽을 수정하면 같은
   변경을 다른 쪽에도 커밋한다. 저장소 고유 값 4개 파일은 각자 것을 유지한다:
   `plugin.json`(author), 플러그인 README(설치 명령), `harness-init.md`(마켓플레이스 키),
   `templates/project-settings.json`. **이 4개 파일 외에 두 저장소의 `plugins/` diff가 있으면
   그것이 동기화 누락이다** — `diff -rq`로 확인한다.
5. 각 사용자는 플러그인 업데이트로 반영받는다 — 프로젝트별 재설치가 필요 없다.
   단 **rules는 프로젝트에 복사본**이 있으므로, rules 변경 시 각 프로젝트에서
   `/harness-init` 재실행(또는 rules만 재복사)이 필요하다.

## 워크스루 — 신규 API 1건의 전체 흐름

"사용자 프로필 조회/수정 API 만들어줘"라고 요청했을 때 실제로 일어나는 일:

1. **라우팅**: `harness-orchestrate`가 "신규 API 개발"로 판단 → `harness-api-build` 체인 시작.
2. **Plan 게이트 (자동 통과 불가)**: `api-developer`가 Phase 1 Plan(엔드포인트 목록, 스키마,
   레이어 구조, 트랜잭션 경계, 인증 방식, 단계별 verify 기준)을 제시하고 **사용자 확인을
   기다린다**. 여기서 승인해야 코드가 생성된다. Plan이 크면(엔드포인트 3개 초과 등) 분할안을
   함께 제시한다(태스크 크기 게이트).
3. **체인 실행 (TDD)**: `api-developer`(스켈레톤 — 컴파일만 되는 골격) → `qa-engineer`(Plan 기준
   테스트 작성, **RED 확인** 후 `test: [RED]` 커밋) → `api-developer`(구현, **GREEN 확인** 후
   `feat: [GREEN]` 커밋) → `security-checker` + `ops-checker` 병렬 검토 보고 (`CACHE_SERVER ≠ none`
   또는 `DB_READ_REPLICA: true`면 `perf-analyzer`도 포함). 각 단계 산출물이
   `chain-report.json`(gitignore 대상)에 기록된다.
4. **기계 검증 게이트**: `./mvnw test`(또는 `./gradlew test`)가 green이어야 다음 단계로 간다.
   red면 `code-reviewer`를 호출하지 않고 fix 담당이 먼저 수정한다.
5. **최종 검토**: `code-reviewer`가 원본 요청 원문과 diff만 보고 독립 검토 —
   요구사항 커버리지, 컨벤션(`ApiResponse<T>` 등), 선행 에이전트의 HIGH 이상(CRITICAL 포함)
   이슈 반영 여부, 테스트 충분성과 TDD 증거(`chain-report.json`의 `tdd.red_confirmed`)를 판정한다.
6. **판정 분기**: `PASS`/`PASS_WITH_WARNINGS` → 완료 보고 후 종료.
   `FAIL` → `harness-review-cycle`이 이슈별 fix 담당을 호출하고 재검토 (최대 3회,
   FAIL 이슈는 `chain-report.json`의 `review_cycle.issues`에 구조화 기록).
   3회 초과 시 `[ESCALATION]`으로 사용자에게 넘긴다 — 수동 수정 후 `/review`로 재진입한다.

### 용어 요약

| 용어 | 의미 |
|---|---|
| 보고 전담 에이전트 | 기본적으로 이슈 보고만 하는 4종 (`code-quality`/`perf-analyzer`/`security-checker`/`ops-checker`). fix 담당 지정 시에만 기존 파일 한정 수정 |
| fix-owner | FAIL 이슈 유형별 수정 담당 에이전트 (`harness-review-cycle`의 매핑표) |
| 체인 | 에이전트를 정해진 순서로 자동 실행하는 스킬 (`harness-api-build` 등) |
| 게이트 | 자동 진행을 멈추고 조건 충족(사용자 확인 또는 테스트 green)을 요구하는 지점 |
| chain-report.json | 체인 진행 상태·이슈를 기록하는 로컬 파일 (커밋 금지, 세션 단절 시 재개 근거) |
| 심각도 척도 | CRITICAL/HIGH/MEDIUM/LOW 단일 기준 — 프로젝트 CLAUDE.md "심각도 척도" 섹션이 SSOT |
