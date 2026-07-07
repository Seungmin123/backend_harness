---
description: Controller-Service-Repository-DTO 레이어 의존 방향과 Spring 안티패턴 표준. api-developer 구현, code-quality/code-reviewer 검토의 공통 기준.
paths:
  - "src/main/java/**/*.java"
---

# 레이어 아키텍처 규칙

## 의존 방향

| 레이어 | 의존 가능 | 의존 금지 |
|---|---|---|
| Controller | Service, DTO | Repository/Entity 직접 참조 |
| Service | Repository, DTO, Domain/Entity, 외부 Client | `HttpServletRequest`/`HttpServletResponse` 직접 사용 |
| Repository | Entity | Service·Controller 역참조 |
| Client (외부 API 연동) | — | Service 내부에 인라인 구현 금지, 별도 클래스로 분리 |
| DTO | (Record, 순수 데이터) | Entity 직접 노출 금지 (변환 메서드 또는 MapStruct 사용) |

이 표를 벗어나는 의존을 만들어야 하는 경우, 먼저 이 표를 갱신하고 이유를 남긴다
(`CLAUDE.md`의 "아키텍처 의존성" 요약 표도 함께 갱신).

## 레이어 경계 위반 탐지 기준

- Controller에서 `Repository` 직접 주입/호출
- Service에서 `HttpServletRequest` / `HttpServletResponse` 직접 사용
- Entity를 Controller 응답으로 직접 반환 (`@JsonIgnore`로 우회 금지)

## Spring 안티패턴

| 안티패턴 | 권고 |
|---|---|
| `@Autowired` 필드 주입 | 생성자 주입으로 변경 (테스트 용이성, final 필드 보장) |
| `@Transactional` 기본값 남용 (readOnly=false가 기본) | 조회 메서드에 `readOnly=true` 명시 |
| 순환 의존성 (A→B→A) | 의존성 방향 재설계 또는 이벤트 기반 분리 |
| `@Component`에 상태(state) 보관 | 싱글턴 빈에 인스턴스 변수로 요청 데이터 저장 금지 |
| `new` 키워드로 Spring 빈 직접 생성 | 의존성 주입으로 전환 |
| `Optional.get()` null 체크 없이 호출 | `orElseThrow()` 또는 `ifPresent()` 사용 |
