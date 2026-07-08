# backend-harness

Java / Spring Boot 백엔드용 Claude Code 하네스 플러그인.
전문 에이전트 7종, 체인 스킬 5종, 안전 훅 3종, 프로젝트 스캐폴딩 커맨드를 제공한다.

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
| harness-api-build | 신규 API 구축 체인 (api-developer→qa→security→ops→reviewer), chain-report.json 기록 |
| harness-full-review | 전체 코드 검토 체인, 자동 수정 진입 전 REVIEW GATE 사용자 확인 |
| harness-bugfix | 버그 수정 체인 — 재현 테스트 먼저 작성(RED) → 수정 → 검증(GREEN) |
| harness-review-cycle | FAIL 시 최대 3회 수정→재검토 루프, fix-owner 매핑, 에스컬레이션 |

## 규칙 파일 참조 (rules/)

| 규칙 | 파일 | `paths:` 범위 |
|---|---|---|
| API 설계 기준 | `api-convention.md` | Controller/Request/Response/ExceptionHandler |
| 보안 정책 | `security-policy.md` | 전체 `.java`, `application*.yml`/`.properties` |
| 레이어 아키텍처 | `layer-architecture.md` | 전체 `.java` |
| 복원력·관찰성 표준 설정 | `resilience-observability.md` | 전체 `.java`, `application*.yml`/`.properties` |
| 성능·JPA, DB 마이그레이션 안전성 | `performance-jpa.md` | 전체 `.java`, `application*.yml`, `db/migration/**`, `db/changelog/**` |
| 테스트 작성 컨벤션 | `testing-conventions.md` | `src/test/java/**/*.java` |
| 엔지니어링 행동 규범 (Karpathy 기반) | `engineering-guidelines.md` | 전체 `.java` (main+test) |

> **데이터 기반 근거 보강 (TODO)**: 실제 코드 리뷰·장애 회고 데이터가 쌓이면 각 rule의
> `description`에 근거(예: "PR N건에서 지적된 항목")를 추가해 우선순위 판단 근거로 삼는다.

## Hooks 상세

- **git-guard** (`PreToolUse`, 모든 Bash): 위험 명령 2단계 가드.
  즉시 차단 — `git reset --hard`, force push, `git clean -f*`, `rm -rf`, `DROP TABLE` 등.
  확인 후 진행 — `commit --amend`, `rebase`, `branch -D`, `flyway:migrate` 등.
- **pre-commit** (`PreToolUse`, `git commit`만): `.env` 스테이징 → Checkstyle(전체 프로젝트) →
  하드코딩 시크릿(스테이징 변경분) 순서. 하나라도 실패하면 커밋 차단(exit 2).
- **post-edit** (`PostToolUse`, Edit|Write): `.java` 편집 후 대응 테스트 자동 실행.
  실패해도 차단하지 않고 경고만(exit 0 고정). 멀티모듈이면 `-pl <모듈>`로 해당 모듈만 실행.

세 훅 모두 **jq가 없으면 조용히 통과**한다. `/harness-init`이 사전 점검에서 이를 확인한다.
훅은 Claude Code 세션만 보호하며, Codex/Gemini 등 다른 도구에서는 AGENTS.md 문서 경고에만 의존한다.

## 하네스 개선 절차

이 저장소가 하네스의 단일 원본(source of truth)이다.

1. 에이전트·스킬·훅·rules 수정은 이 저장소에 PR로 제출하고 팀 리뷰를 거친다.
2. 머지 후 플러그인 버전(`.claude-plugin/plugin.json`의 `version`)을 올린다.
3. 각 사용자는 플러그인 업데이트로 반영받는다 — 프로젝트별 재설치가 필요 없다.
   단 **rules는 프로젝트에 복사본**이 있으므로, rules 변경 시 각 프로젝트에서
   `/harness-init` 재실행(또는 rules만 재복사)이 필요하다.
