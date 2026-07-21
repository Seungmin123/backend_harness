---
description: Controller-Service-Repository-DTO 레이어 의존 방향(수직), 모듈러 모놀리스 모듈 경계(수평), Spring 안티패턴 표준. api-developer 구현, code-quality/code-reviewer 검토의 공통 기준.
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

## 모듈 경계 (모듈러 모놀리스)

모듈 목록과 의존 방향의 원본은 `docs/ARCHITECTURE.md`의 "모듈/서비스 지도"다.
레이어 규칙(수직)과 별개로, 모듈 간(수평) 접근은 아래를 따른다.

- **패키지 구조**: 최상위를 모듈로 나눈다 — `<base>.{user|album|community|order|message|file}.*`
  각 모듈 내부는 표준 레이어 구조(controller/service/repository/dto)를 따른다.
- **모듈 간 접근은 두 가지 경로만 허용**:
  1. 상대 모듈의 **공개 서비스 인터페이스** 호출 (동기 — 의존 방향이 ARCHITECTURE.md 표에 있을 때만)
  2. **도메인 이벤트** 발행/구독 (비동기 — 알림·후처리처럼 결과를 기다리지 않는 경우.
     `MESSAGE_BROKER: application-event`면 `ApplicationEventPublisher` 사용)
- **금지**:
  - 다른 모듈의 Repository·Entity 직접 참조 (조회가 필요하면 상대 모듈 서비스가 DTO로 반환)
  - 다른 모듈의 내부 구현 패키지(`internal`, `service` 구현체 등) import
  - 모듈 간 순환 의존 (`A→B→A`) — 발견 즉시 이벤트 분리 또는 의존 방향 재설계
  - 지원 모듈(`message`, `file`)이 도메인 모듈을 역참조
- **JPA 연관관계는 모듈 내부로 한정**: 모듈을 넘는 `@ManyToOne` 등 엔티티 연관 금지 —
  상대 모듈 엔티티는 ID(FK 값)로만 보관하고, 필요 시 서비스 호출로 조회한다.
  (모듈 경계를 넘는 fetch join이 생기는 순간 모듈 분리가 무너진다.)
- **모듈 경계는 Spring Modulith로 기계 강제**: `ApplicationModules.verify()` 테스트를
  두고 CI에서 실행한다 (ADR-1). 이 규칙 파일의 모듈 경계 조항은 그 테스트가 잡지 못하는
  의미적 위반(ID 보관 원칙, DB 소유권 등)을 리뷰로 보완하는 역할이다.

## 모듈별 아키텍처 적용 수준 (ADR-1)

모듈 내부 구조는 복잡도에 따라 두 수준으로 이원화한다. 어느 모듈이 어느 수준인지가
구현·리뷰의 기준이므로, 승격 시 이 표를 같은 PR에서 갱신한다.

| 수준 | 적용 모듈 | 내부 구조 |
|---|---|---|
| **표준 레이어드** | `user`, `album`, `community`, `file` | 이 파일의 "의존 방향" 표 그대로 (controller/service/repository/dto) |
| **헥사고날 + DDD 전술** | `order`, `message` | 아래 "헥사고날 모듈 패키지 구조" — 외부 시스템(Shopify, 이메일/푸시 채널)을 port/adapter로 격리 |

- 레이어드 모듈에 복잡한 도메인 로직(상태 머신, 불변식이 많은 규칙)이 생기면 헥사고날로
  **승격**한다 — 그 전까지 레이어드 모듈에 port/adapter 보일러플레이트를 만들지 않는다
  (`engineering-guidelines.md` 2번 "과설계 방지").

### 헥사고날 모듈 패키지 구조 (`order`, `message`)

```
<base>.order/
├── domain/            # 도메인 모델 (엔티티·VO·도메인 서비스) — 프레임워크 의존 최소화
├── application/       # 유스케이스 (port 인터페이스 정의 포함)
│   └── port/
│       ├── in/        # 인바운드 port (유스케이스 인터페이스)
│       └── out/       # 아웃바운드 port (저장소·외부 시스템 인터페이스)
└── adapter/
    ├── in/web/        # Controller (인바운드 adapter)
    └── out/
        ├── persistence/   # JPA 어댑터 (아웃바운드)
        └── shopify/       # 외부 API 어댑터 (예: order 모듈의 Shopify Client)
```

- **의존 방향**: adapter → application → domain 단방향. domain은 어느 것도 참조하지 않는다.
- 외부 시스템 호출(Shopify, 이메일/푸시)은 반드시 `port/out` 인터페이스 뒤로 격리한다 —
  Service에 HTTP 클라이언트 직접 주입 금지. 테스트에서는 port를 fake로 대체한다.
- 다른 모듈에서 볼 수 있는 것은 `port/in`(공개 유스케이스)과 발행하는 도메인 이벤트뿐이다.

## 모듈별 DB 소유권 (ADR-1)

- **모든 테이블은 정확히 하나의 모듈이 소유한다.** 소유 모듈만 그 테이블에 대한
  Repository/쿼리를 가질 수 있다.
- **교차 모듈 조인·쿼리 금지**: 다른 모듈 테이블과의 JOIN, 다른 모듈 테이블을 읽는 native
  query 금지. 데이터가 필요하면 상대 모듈의 공개 인터페이스로 조회한다.
- 조인이 성능상 불가피해 보이면 그것은 모듈 경계가 잘못 그어졌다는 신호다 — 우회 쿼리를
  만들지 말고 경계 재검토를 제안한다.
- 마이그레이션 파일(`db/migration/**`)도 모듈 소유를 주석으로 명시한다
  (예: `-- owner: order`). MSA 분리 시 이 소유권 목록이 그대로 분리 단위가 된다.

## 레이어 경계 위반 탐지 기준

- Controller에서 `Repository` 직접 주입/호출
- Service에서 `HttpServletRequest` / `HttpServletResponse` 직접 사용
- Entity를 Controller 응답으로 직접 반환 (`@JsonIgnore`로 우회 금지)
- **다른 모듈** 패키지의 Repository/Entity/내부 구현 import (모듈 경계 위반)
- 모듈 경계를 넘는 JPA 연관관계 (`@ManyToOne` 등 — ID 보관으로 대체할 것)
- 다른 모듈 소유 테이블에 대한 JOIN 또는 native query (DB 소유권 위반)
- 헥사고날 모듈(`order`, `message`)에서 Service에 HTTP 클라이언트 직접 주입
  (port/out 인터페이스로 격리할 것)

## Spring 안티패턴

| 안티패턴 | 권고 |
|---|---|
| `@Autowired` 필드 주입 | 생성자 주입으로 변경 (테스트 용이성, final 필드 보장) |
| `@Transactional` 기본값 남용 (readOnly=false가 기본) | 조회 메서드에 `readOnly=true` 명시 |
| 순환 의존성 (A→B→A) | 의존성 방향 재설계 또는 이벤트 기반 분리 |
| `@Component`에 상태(state) 보관 | 싱글턴 빈에 인스턴스 변수로 요청 데이터 저장 금지 |
| `new` 키워드로 Spring 빈 직접 생성 | 의존성 주입으로 전환 |
| `Optional.get()` null 체크 없이 호출 | `orElseThrow()` 또는 `ifPresent()` 사용 |
