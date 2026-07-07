---
description: JPA/쿼리 최적화, 캐시(Redis/Caffeine) 설정 기준값, HikariCP 커넥션 풀 권장치, ECS Fargate 리소스 기준, DB 마이그레이션(Flyway/Liquibase) 안전성 체크리스트. api-developer 구현과 perf-analyzer 검토의 공통 기준.
paths:
  - "src/main/java/**/*.java"
  - "src/main/resources/application*.yml"
  - "src/main/resources/db/migration/**"
  - "src/main/resources/db/changelog/**"
---

# 성능·JPA 표준 설정

## N+1 쿼리 방지

- `@OneToMany`/`@ManyToOne` Lazy 로딩 후 루프 내 즉시 반복 접근 금지
- 개선: `@EntityGraph`, fetch join, `@BatchSize`

## 인덱스 / 대용량 조회

- JPQL/QueryDSL `WHERE` 조건 컬럼에 `@Index` 적용, `LIKE '%keyword%'`(풀스캔) 지양
- `findAll()` 또는 페이지네이션 없는 목록 조회 금지 — cursor 기반 페이지네이션 사용

## 캐시 〔`CACHE_SERVER ≠ none`〕

공통 (redis / caffeine / redis+caffeine):
- 변경 빈도 낮고 조회 빈도 높은 메서드에 `@Cacheable` 적용, 데이터 변경 시 `@CacheEvict` 동반
- TTL 필수 설정 (메모리 무한 증가 방지), Cache Stampede 방지 고려

`CACHE_SERVER: redis` / `redis+caffeine`:
- 커넥션 풀(`lettuce`/`jedis`) 설정, `spring.data.redis.timeout` 설정 (장애 시 무한 대기 방지)
- Eviction 정책: `maxmemory-policy: allkeys-lru` 권장

`CACHE_SERVER: caffeine` / `redis+caffeine`:
- `maximumSize` 필수 설정 (힙 메모리 무한 증가 → ECS Fargate OOM 위험)
- `expireAfterWrite` / `expireAfterAccess` 설정
- 다중 인스턴스 환경에서는 캐시 정합성 전략 필요 (Redis+Caffeine 이중 캐시 또는 무효화 이벤트)

## Connection Pool (HikariCP)

- 이론적 기준 공식(`(CPU 코어 수 × 2) + 유효 스핀들 수`)은 Fargate의 네트워크 연결 스토리지
  특성상 과소 산정되므로 상한 가늠용으로만 참고한다.
- **실무 권장치 (1 vCPU Fargate)**: `maximumPoolSize=10` 내외 (트래픽에 따라 5~10 범위).
  과대 설정 금지 — 풀 크기가 DB `max_connections`나 (태스크 수 × 풀 크기)를 초과하면 DB 커넥션 고갈.
- `connectionTimeout`은 기본값(30초)이 과도하게 높지 않은지 확인
- 트랜잭션 내부에서 외부 API 호출로 커넥션을 길게 점유하지 않는다

`DB_READ_REPLICA: true` 추가 기준:
- `@Transactional(readOnly=true)`가 실제로 읽기 복제본으로 라우팅되는지 확인
  (`AbstractRoutingDataSource` 또는 `LazyConnectionDataSourceProxy`)
- 읽기/쓰기 풀 크기를 트래픽 비율에 맞게 분리

## ECS Fargate 특화

- 대용량 객체 반복 생성, 루프 내 문자열 연결(`+`) 대신 `StringBuilder`/`String.join()` 사용
  (태스크 메모리 압박 방지)
- Cold Start: 배포 직후 트래픽 급증에 대비한 Warmup 엔드포인트 또는 헬스체크 유예 시간
- Fargate Spot 사용 시 SIGTERM 처리·Graceful Shutdown 30초 이내 완료
  (셧다운 설정 자체는 `.claude/rules/resilience-observability.md` 및 `ops-checker` 담당,
  여기서는 성능 영향만 다룬다)

## JVM

- 루프 내 불필요한 객체 생성 금지
- `Stream.collect(Collectors.toList())` 대신 `toList()` 사용 (Java 16+, 불변 리스트)

## DB 마이그레이션 안전성 〔Flyway/Liquibase 사용 시〕

Entity 변경이 스키마 변경을 수반하면 이 체크리스트를 함께 확인한다. 운영 DB는 `ddl-auto: none`
(또는 `validate`)이 기본이므로 Hibernate 자동 스키마 생성에 의존하지 않고 마이그레이션
스크립트로 직접 관리한다.

- **NOT NULL 컬럼 추가**: 기존 행이 있는 테이블에 기본값(`DEFAULT`) 없이 `NOT NULL` 컬럼을
  즉시 추가하지 않는다. `DEFAULT` 동반 추가 또는 (1) nullable로 추가 → (2) 백필 → (3) `NOT NULL`
  제약 추가의 3단계로 분리한다.
- **컬럼/테이블 삭제**: 애플리케이션 코드에서 참조를 제거한 배포와 실제 컬럼/테이블 삭제
  마이그레이션을 같은 배포에 묶지 않는다. 롤링 배포 중 구버전 인스턴스가 여전히 해당 컬럼을
  참조할 수 있다 — 최소 1회 배포 주기 이후 별도 마이그레이션으로 삭제한다.
- **컬럼 타입 변경**: 하위 호환 없는 타입 변경(예: `VARCHAR` → `INT`)을 단일 마이그레이션으로
  수행하지 않는다. 신규 컬럼 추가 → 이중 쓰기/백필 → 기존 컬럼 제거의 Expand-Contract 패턴을
  사용한다.
- **인덱스 추가**: 대용량 테이블에 인덱스를 추가할 때 테이블 락 여부를 확인한다
  (PostgreSQL `CREATE INDEX CONCURRENTLY`, MySQL `ALGORITHM=INPLACE` 등 DB 엔진별 온라인
  인덱스 생성 방식 사용).
- **이미 적용된 마이그레이션 파일 수정 금지**: 배포된 버전의 마이그레이션 스크립트를 수정하면
  체크섬 불일치로 다른 환경에서 배포가 실패한다. 정정이 필요하면 새 버전 파일을 추가한다.
- **버전 파일 네이밍/순서**: Flyway `V{n}__description.sql` 또는 Liquibase changelog 순서가
  실제 적용 순서와 일치하는지 확인한다. 병렬 브랜치에서 동일 버전 번호 충돌 여부도 확인한다.
- **Entity ↔ 마이그레이션 동기화**: `@Column`, `@Table` 등 Entity 스키마 매핑 변경 시 대응하는
  마이그레이션 스크립트가 함께 추가되었는지 확인한다.
