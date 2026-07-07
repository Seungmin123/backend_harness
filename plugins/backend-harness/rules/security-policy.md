---
description: 시크릿 관리, Spring Security 설정, JWT 처리, 로그 개인정보 보호, 입력 검증 등 보안 정책. security-checker 체크 기준이자 api-developer/code-reviewer 공통 준수 대상.
paths:
  - "src/main/java/**/*.java"
  - "src/main/resources/application*.yml"
  - "src/main/resources/application*.properties"
---

# Security Policy

## 시크릿 관리

- **환경변수** 또는 **AWS Parameter Store** / **Secrets Manager** 사용 필수
- `application.properties` / `application.yml`에 실제 값 작성 금지
  - 허용: `${DB_PASSWORD}`, `${aws.parameter.store.key}`
  - 금지: `password=mysecret123`
- `.env` 파일은 `.gitignore`에 반드시 포함
- AWS 자격증명은 ECS Task Role(IAM Role) 기반으로 처리, 코드 내 AccessKey 금지

## Spring Security 필수 체크 항목

- 모든 API 엔드포인트에 인증/인가 설정 명시 (기본 `permitAll()` 금지)
- `SecurityFilterChain` 빈 직접 선언 (`WebSecurityConfigurerAdapter` deprecated)
- CSRF:
  - REST API(Stateless): `csrf.disable()` 허용, 이유 주석 필수
  - 세션 기반: CSRF 토큰 활성화 필수
- CORS: 와일드카드(`*`) 운영 환경 금지. `allowedOrigins`에 명시적 도메인 지정
- 헤더:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security` (HTTPS 환경)
- 패스워드: `BCryptPasswordEncoder` (strength ≥ 12) 사용

## JWT 처리 규칙

- 서명 알고리즘: RS256 또는 HS256 (HS256 시 키 길이 256bit 이상)
- `none` 알고리즘 허용 코드 존재 시 즉시 차단
- 만료(`exp`) 검증 필수
- 발급자(`iss`), 대상(`aud`) 검증 권장
- 토큰을 로그에 출력 금지

## 로그 개인정보 보호

로그에 출력 절대 금지 항목:
- 패스워드, 토큰, API 키
- 주민등록번호, 신용카드 번호
- 이메일, 전화번호 (마스킹 처리 후 허용)
- 로그에 `@JsonIgnore`와 무관하게 DTO 전체 직렬화 출력 금지

## 입력 검증

- 모든 Controller 메서드 파라미터에 `@Valid` 적용
- 파일 업로드:
  - 허용 확장자 화이트리스트 검사
  - MIME 타입 검사 (확장자만으로 판단 금지)
  - 저장 경로에 `..` 포함 여부 검사 (Path Traversal 방지)
- SQL: JPQL 또는 QueryDSL의 파라미터 바인딩 사용. 문자열 직접 조합 금지

## 의존성 보안

- `./mvnw dependency-check:check` 정기 실행 (CVSS 7.0 이상 즉시 업그레이드)
- SNAPSHOT 버전 운영 배포 금지
