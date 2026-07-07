---
description: URL 설계, 표준 응답 포맷, HTTP 상태 코드, 페이지네이션 등 REST API 컨벤션. api-developer 구현과 code-reviewer 검토의 공통 기준.
paths:
  - "src/main/java/**/controller/**/*.java"
  - "src/main/java/**/*Controller.java"
  - "src/main/java/**/*Request.java"
  - "src/main/java/**/*Response.java"
  - "src/main/java/**/*ExceptionHandler.java"
---

# API Convention Rules

## URL 설계

- **리소스명**: 복수형 명사 사용 (`/users`, `/orders`, `/products`)
- **케이싱**: kebab-case (`/user-profiles`, `/order-items`)
- **계층 깊이**: 최대 3단계 (`/users/{id}/orders/{orderId}`)
- **동사 금지**: `/getUser` (X) → `/users/{id}` (O)
- **버전**: URL 경로에 포함 (`/api/v1/users`)

## 표준 응답 포맷

### 성공 응답
```json
{
  "data": { },
  "meta": {
    "requestId": "uuid",
    "timestamp": "ISO-8601"
  }
}
```

### 페이지네이션 응답
```json
{
  "data": [],
  "meta": {
    "requestId": "uuid",
    "timestamp": "ISO-8601",
    "pagination": {
      "nextCursor": "base64-encoded-cursor",
      "hasNext": true,
      "size": 20
    }
  }
}
```

### 에러 응답
```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "사용자를 찾을 수 없습니다.",
    "details": [],
    "requestId": "uuid"
  }
}
```

- `code`: SCREAMING_SNAKE_CASE 상수 (클라이언트가 분기 처리용으로 사용)
- `message`: 사용자에게 노출 가능한 한국어 메시지
- `details`: 필드 유효성 오류 목록 (`[{ "field": "email", "reason": "형식이 올바르지 않습니다" }]`)
- 스택 트레이스, 내부 클래스명 절대 포함 금지

> **`requestId` 위치 규약 (의도된 비대칭)**: 성공 응답은 `meta.requestId`, 에러 응답은 `error.requestId`에 둔다.
> 에러 시에는 `meta` 래퍼가 없으므로 `error` 내부에 포함하는 것이 의도된 설계다.
> 공통 응답 래퍼/`@RestControllerAdvice` 구현 시 두 경로 모두에서 동일한 `requestId`(MDC traceId 연동 권장)를 채울 것.

## HTTP 상태 코드 기준

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

## 페이지네이션

- **방식**: Cursor 기반 (offset 방식 금지 — 대용량 데이터에서 성능 저하)
- **기본 size**: 20, **최대 size**: 100
- cursor는 Base64 인코딩된 불투명 값 (클라이언트가 파싱 불가)
- 요청 파라미터: `?cursor=xxx&size=20`

## 공통 규칙

- 날짜/시간: ISO 8601 형식 (`2024-01-15T09:30:00Z`), 항상 UTC
- ID: UUID v4 (순차 Long ID 외부 노출 금지)
- 빈 목록: `null` 대신 `[]` 반환
- 필드명: camelCase
