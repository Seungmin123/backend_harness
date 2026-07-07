# docs/plans/

진행 중인 기능의 구현 설계 문서(**작업 단위 문서**)를 담는다. 완료 후 살아남을 필요가 없다 —
승격할 지식만 `docs/features/`, `docs/ADR.md` 등으로 옮기고 원문은 삭제한다
(`CLAUDE.md`의 "문서 체계 — 승격 규칙" 참조).

- 파일명: `docs/plans/PLAN_<작업명>.md`
- 소유: 작성자. 다른 사람이 수정하려면 먼저 합의한다(`CLAUDE.md`의 "협업 규칙" 참조).
- 절대 규칙 1(Plan First)의 Plan Mode 논의 근거로 사용한다 — 파일 2개 이상 변경, 또는
  Service·Controller·SecurityConfig 수정 시 필수.

## 권장 구조

```
# PLAN: <작업명>

## As-Is / To-Be
## ERD (스키마 변경이 있다면)
## API 명세
## 단계별 검증 기준
1. [단계] → verify: [확인 방법]
```
