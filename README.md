# whalee claude-plugins

whalee 팀의 Claude Code 플러그인 마켓플레이스.

## 사용법

```
/plugin marketplace add Seungmin123/backend_harness
/plugin install backend-harness@whalee
```

또는 프로젝트 `.claude/settings.json`에 아래를 커밋해 두면 팀원이 저장소를 열 때 자동으로
설치가 제안된다:

```json
{
  "extraKnownMarketplaces": {
    "whalee": { "source": { "source": "github", "repo": "Seungmin123/backend_harness" } }
  },
  "enabledPlugins": { "backend-harness@whalee": true }
}
```

## 플러그인 목록

| 플러그인 | 설명 |
|---|---|
| [backend-harness](plugins/backend-harness/README.md) | Java/Spring Boot 백엔드 하네스 — 에이전트 7종, 체인 스킬 5종, 안전 훅 3종, `/harness-init` 스캐폴딩 |

## 기여

플러그인 수정은 PR로 제출한다. 머지 시 해당 플러그인의 `plugin.json` `version`을 올린다.
