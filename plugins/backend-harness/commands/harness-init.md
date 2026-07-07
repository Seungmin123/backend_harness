---
description: 이 프로젝트에 backend-harness를 초기화한다 — 운영 환경 값 4개 설정, CLAUDE.md/AGENTS.md·rules·docs·settings 스캐폴딩
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*), Bash(test:*), Bash(which:*), Bash(mkdir:*), Bash(cp:*), Bash(ln:*), Bash(chmod:*), Bash(find:*), AskUserQuestion
---

# /harness-init — 프로젝트 스캐폴딩

backend-harness 플러그인을 사용하는 프로젝트를 초기화한다. 아래 절차를 순서대로 수행하라.
플러그인 파일 경로가 필요할 때는 이 커맨드 파일이 속한 플러그인 루트를 사용한다
(`${CLAUDE_PLUGIN_ROOT}` — 비어 있으면 `find ~/.claude/plugins -type d -name backend-harness`로 찾는다).

## 0. 사전 점검

1. `which jq` — 미설치면 **여기서 중단**하고 사용자에게 설치를 안내한다(`brew install jq`).
   jq가 없으면 안전 훅(git-guard/pre-commit/post-edit)이 전부 조용히 통과해버리기 때문이다.
2. `test -x ./mvnw` — Maven wrapper가 없으면 경고한다(post-edit 자동 테스트가 동작하지 않음).
   중단하지는 않는다.
3. 프로젝트 루트에 이미 `CLAUDE.md`가 있으면 **덮어쓰지 말고** 사용자에게 물어본다:
   기존 내용을 유지하고 누락 섹션만 병합할지, 새로 생성할지.

## 1. 운영 환경 값 수집 (AskUserQuestion 사용)

다음 4개 값을 사용자에게 묻는다 (한 번의 AskUserQuestion으로 4개 질문):

- `CACHE_SERVER`: none | redis | caffeine | redis+caffeine
- `MESSAGE_BROKER`: none | application-event | kafka | sqs (kafka+sqs는 Other로 입력)
- `EXTERNAL_API`: true | false
- `DB_READ_REPLICA`: true | false

스택/인프라/의존성/테스트 스택은 프로젝트의 `pom.xml`을 읽어 스스로 파악한다
(Java 버전, Spring Boot 버전, 주요 스타터, 테스트 라이브러리). 파악 불가 항목만 추가로 묻는다.

## 2. 파일 생성

1. **CLAUDE.md**: 플러그인의 `templates/CLAUDE.md.template`을 읽어 `{{...}}` 플레이스홀더를
   1단계에서 수집한 값으로 치환해 프로젝트 루트에 `CLAUDE.md`로 쓴다.
2. **AGENTS.md 심링크**: `ln -s CLAUDE.md AGENTS.md` (이미 있으면 건너뛴다).
3. **rules 설치**: `mkdir -p .claude && cp -r <플러그인루트>/rules .claude/rules`
   (기존 `.claude/rules`가 있으면 덮어쓰기 전에 사용자에게 확인).
4. **docs 골격**: `cp -r <플러그인루트>/templates/docs docs` (기존 docs/가 있으면 없는 파일만 복사).
5. **settings 병합**: `.claude/settings.json`이 없으면 플러그인의 `templates/project-settings.json`을
   복사한다. 이미 있으면 `extraKnownMarketplaces.backend-harness`와 `enabledPlugins."backend-harness@backend-harness"`
   키만 병합한다(기존 키는 건드리지 않는다).

## 3. 완료 보고

다음을 요약해 출력한다:

- 생성/병합된 파일 목록
- 설정된 운영 환경 값 4개
- 활성화된 것: 에이전트 7종, 체인 스킬 5종, 훅 3종(플러그인이 자동 등록)
- 남은 수동 확인 1가지: 기존 코드가 있는 프로젝트라면 `./mvnw checkstyle:check`를 한 번 돌려
  기존 위반 현황을 파악할 것 (pre-commit 훅이 전체 프로젝트 기준으로 검사하므로)
