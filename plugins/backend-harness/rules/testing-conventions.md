---
description: JWT/세션 인증 테스트 작성 절차, 테스트 메서드 명명 규칙, Edge Case 체크리스트. qa-engineer 작성과 code-reviewer의 테스트 충분성 검토 공통 기준.
paths:
  - "src/test/java/**/*.java"
---

# 테스트 작성 컨벤션

## TEST-01. 통합 테스트 작성 전 필수 확인: JWT vs 세션 인증

테스트 파일을 작성하기 **전에** 프로젝트의 인증 방식을 먼저 확인한다.

**확인 순서 (우선순위대로)**:
1. **CONTEXT 우선**: `api-developer`가 Phase 1에서 결정해 SUMMARY로 전달한 인증 방식(JWT/세션)과
   접근 권한이 있으면 1차 근거로 삼는다.
2. **파일 검사 (CONTEXT에 없을 때)**: `SecurityFilterChain` 또는 `application.yml`에서 JWT 필터
   (`JwtAuthenticationFilter` 등) 활성화 여부를 검사한다.
3. **둘 다 불가할 때**: 아래 Fallback 규칙에 따라 JWT 방식으로 간주한다.

| 인증 방식 | `@WithMockUser` 사용 가능 여부 | 권장 대안 |
|---|---|---|
| 세션 기반 (Spring Security 기본) | ✅ 사용 가능 | — |
| JWT 필터 활성화 | ❌ JWT 검증 단계에서 401 반환 | 아래 대안 중 하나 |

**JWT 프로젝트의 대안:**
1. `Authorization: Bearer {testToken}` 헤더 직접 주입 (실제 토큰 발급 후 사용)
2. `@TestConfiguration`으로 테스트 전용 `SecurityFilterChain` 구성해 JWT 필터 교체
3. JWT 필터를 `@MockBean`으로 교체하거나 비활성화한 경우에만 `@WithMockUser` 사용

> **잘못 사용 시 증상**: 테스트가 실제로 비즈니스 로직을 검증하지 않고 401로만 통과하거나 실패한다.

> **확인 불가 시 Fallback**: 인증 방식을 확인할 수 없는 경우 **JWT 방식으로 간주**하고
> `Authorization: Bearer {testToken}` 헤더 주입 방식으로 작성한다. JWT 환경에서
> `@WithMockUser`를 잘못 사용하면 테스트가 401로 "통과"하는 더 위험한 상황이 되기 때문이다.

## TEST-02. `@SpringBootTest` + `@AutoConfigureMockMvc` 조합 선택 기준

| 목적 | 어노테이션 조합 | 비고 |
|---|---|---|
| MockMvc로 컨트롤러 레이어 검증 | `@SpringBootTest` + `@AutoConfigureMockMvc` | 포트 불필요, 빠름 |
| 실제 HTTP 포트로 종단 간 검증 | `@SpringBootTest(webEnvironment = RANDOM_PORT)` | `TestRestTemplate` 또는 `WebTestClient` 사용 |

`RANDOM_PORT` + `MockMvc`를 함께 쓰면 MockMvc가 포트를 무시하고 동작해 의도와 다른 결과가
나올 수 있다. **혼용 금지.**

## TEST-03. 테스트 메서드 명명 규칙

테스트 **메서드명**은 `{메서드명}_{조건}_{기대결과}` 형식:
- `getUser_existingId_returnsUserResponse`
- `createOrder_outOfStock_throwsOutOfStockException`

`@DisplayName`에는 메서드명을 그대로 넣지 않는다. 사람이 읽을 수 있는 한국어 문장을 작성한다
(예: `"존재하는 사용자 ID로 조회 시 UserResponse 반환"`).

## TEST-04. Edge Case 탐색 체크리스트

- [ ] `null` 입력값 처리
- [ ] 빈 컬렉션 (`[]`) 반환 시 `null` 반환하지 않는지
- [ ] 문자열 최대 길이 초과
- [ ] UUID 형식 오류 PathVariable
- [ ] 동시 요청 시 중복 생성 시나리오 (`@Transactional` + unique 제약)
- [ ] 페이지네이션 cursor 오염값 입력
- [ ] `@Valid` 검증 실패 요청 (필수 필드 누락, 형식 오류, 길이 초과) → 400 Bad Request 반환 확인
- [ ] 인증 토큰 없는 요청 → 401 반환 확인
- [ ] 권한 없는 사용자 요청 → 403 반환 확인

## TEST-05. 각 메서드당 최소 케이스 (단위 테스트)

1. **정상 케이스**: 기대 결과 반환
2. **경계값**: null, 빈 문자열, 최대/최소 값, 빈 컬렉션
3. **예외 케이스**: 존재하지 않는 ID, 권한 없음, 비즈니스 규칙 위반
