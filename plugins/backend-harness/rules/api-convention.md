---
description: URL 설계, 표준 응답 포맷(ApiResponse 래퍼), HTTP 상태 코드, 페이지네이션 등 REST API 컨벤션. api-developer 구현과 code-reviewer 검토의 공통 기준.
paths:
  - "src/main/java/**/controller/**/*.java"
  - "src/main/java/**/*Controller.java"
  - "src/main/java/**/*Request.java"
  - "src/main/java/**/*Response.java"
  - "src/main/java/**/*ExceptionHandler.java"
  - "src/main/java/**/dto/resp/**/*.java"
---

# API Convention Rules

## API-01. URL 설계

- **리소스명**: 복수형 명사 사용 (`/users`, `/orders`, `/products`)
- **케이싱**: kebab-case (`/user-profiles`, `/order-items`)
- **계층 깊이**: 최대 3단계 (`/users/{id}/orders/{orderId}`)
- **동사 금지**: `/getUser` (X) → `/users/{id}` (O)
- **버전**: URL 경로에 포함 (`/api/v1/users`)

## API-02. 표준 응답 포맷 — `ApiResponse<T>`

모든 API 응답(성공·실패)은 공통 래퍼 `ApiResponse<T>`
(프로젝트 공통 `dto/resp` 패키지)로 감싼다. 응답 바디는 `code` + `data` 두 필드이며,
`@JsonInclude(NON_NULL)`이므로 `data`가 `null`이면 필드 자체가 생략된다.

```java
@Getter
@NoArgsConstructor(access = AccessLevel.PRIVATE)
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {
    private String code;   // ApiResponseCode의 code 값
    private T data;        // 응답 페이로드 (null이면 직렬화 시 생략)
}
```

### 생성 규칙 — 정적 팩토리만 사용 (생성자는 private)

| 상황 | 사용 |
|---|---|
| 성공 | `ApiResponse.success(data)` — `SUCCESS` 코드 자동 적용 |
| 특정 코드 직접 지정 | `ApiResponse.of(responseCode, data)` |
| 실패 (기본 메시지) | `ApiResponse.error(responseCode, data)` |
| 실패 (메시지 오버라이드) | `ApiResponse.error(responseCode, overrideMessage, data)` |

- `new` 직접 생성 금지 — 팩토리 메서드만 사용한다 (생성자가 private이라 컴파일 수준에서도 막힌다).
- `code`는 반드시 `ApiResponseCode` enum에서 가져온다. 문자열 리터럴 하드코딩 금지.
- 새 응답 코드가 필요하면 `ApiResponseCode`에 추가한다 (기존 code 값과 충돌 확인).
- Controller 반환 타입은 `ApiResponse<구체DTO>` — raw 타입(`ApiResponse` 단독) 금지.

### 응답 형태

```json
// 성공 (code 값은 ApiResponseCode 정의를 따름)
{ "code": "<SUCCESS code>", "data": { } }

// data 없는 성공 — NON_NULL이므로 data 필드 생략
{ "code": "<SUCCESS code>" }

// 실패 — 같은 래퍼, code로 분기. 필드 오류 등 상세는 data에 담는다
{ "code": "<에러 code>", "data": { "fieldErrors": [ { "field": "email", "reason": "형식이 올바르지 않습니다" } ] } }
```

- 클라이언트 분기 처리는 항상 바디의 `code` 기준. HTTP 상태 코드는 아래 표를 함께 따른다.
- 스택 트레이스, 내부 클래스명 절대 포함 금지.
- 요청 추적: 바디에 `requestId` 필드가 없으므로 `X-Request-Id` 응답 헤더 + MDC(traceId)로
  추적한다 (`resilience-observability.md`의 "분산 추적" 참조).
- `@RestControllerAdvice` 예외 처리도 동일하게 이 래퍼로 감싸서 반환한다.

> ⚠️ **알려진 제약**: `error(responseCode, overrideMessage, data)`는 현재 클래스에 `message`
> 필드가 없어 `overrideMessage`가 **무시된다**. 메시지 오버라이드가 실제로 필요하면
> `message` 필드 추가 여부를 먼저 팀에서 결정할 것 — 그 전까지 이 오버로드는 사용하지 않는다.

### 페이지네이션 응답 (data 내부 구조)

```json
{
  "code": "<SUCCESS code>",
  "data": {
    "items": [],
    "nextCursor": "base64-encoded-cursor",
    "hasNext": true,
    "size": 20
  }
}
```

## API-03. HTTP 상태 코드 기준

| 상황 | 코드 |
|---|---|
| 조회 성공 | 200 OK |
| 생성 성공 | 201 Created + Location 헤더 |
| 수정 성공 (응답 바디 있음) | 200 OK |
| 수정/삭제 성공 (바디 없음) | 204 No Content |
| 부분 수정 성공 (응답 바디 있음) | 200 OK |
| 부분 수정 성공 (바디 없음) | 204 No Content |
| 입력값 유효성 오류 | 400 Bad Request |
| 인증 없음 | 401 Unauthorized |
| 권한 없음 | 403 Forbidden |
| 리소스 없음 | 404 Not Found |
| 비즈니스 규칙 위반 | 409 Conflict |
| 요청 한도 초과 (Rate Limit) | 429 Too Many Requests |
| 서버 오류 | 500 Internal Server Error |
| 일시적 사용 불가 (Circuit Open / 셧다운 중) | 503 Service Unavailable |

## API-04. 페이지네이션

- **방식**: Cursor 기반 (offset 방식 금지 — 대용량 데이터에서 성능 저하)
- **기본 size**: 20, **최대 size**: 100
- cursor는 Base64 인코딩된 불투명 값 (클라이언트가 파싱 불가)
- 요청 파라미터: `?cursor=xxx&size=20`

## API-05. 공통 규칙

- 날짜/시간: ISO 8601 형식 (`2024-01-15T09:30:00Z`), 항상 UTC
- ID: UUID v4 (순차 Long ID 외부 노출 금지)
- 빈 목록: `null` 대신 `[]` 반환
- 필드명: camelCase

## API-06. 매핑 어노테이션

- **핸들러 메서드**: HTTP 메서드 전용 어노테이션만 사용한다 —
  `@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`
- **메서드 레벨 `@RequestMapping` 금지**: `@RequestMapping(method = RequestMethod.GET)` (X)
  → `@GetMapping` (O). `method` 속성을 빠뜨리면 모든 HTTP 메서드에 매핑되는 사고를
  막고, 핸들러의 의도가 시그니처만 봐도 드러난다.
- **클래스 레벨 `@RequestMapping`**: 공통 base path 선언 용도로만 허용
  (`@RequestMapping("/api/v1/users")`).

```java
@RestController
@RequestMapping("/api/v1/users")   // 클래스 레벨 — base path 전용
public class UserController {

    @GetMapping("/{id}")           // 메서드 레벨 — 전용 어노테이션만
    public ResponseEntity<ApiResponse<UserResponse>> getUser(@PathVariable UUID id) { ... }
}
```
