---
description: 타임아웃·Retry·Circuit Breaker·Graceful Shutdown(복원력)과 로깅·분산추적·메트릭·헬스체크(관찰성) 표준 설정값. api-developer 구현과 ops-checker 검토의 공통 기준. AWS ECS Fargate 기준. Kafka/SQS 세부 운용 기준은 별도로 ops-checker.md에 유지한다(MESSAGE_BROKER 조건부라 대부분 프로젝트에 해당 없음).
paths:
  - "src/main/java/**/*.java"
  - "src/main/resources/application*.yml"
  - "src/main/resources/application*.properties"
---

# 복원력·관찰성 표준 설정 (AWS ECS Fargate 기준)

`EXTERNAL_API` 등 운영 환경 설정에 따라 관련 섹션만 적용한다(활성화 기준은 `CLAUDE.md`의
"운영 환경 설정" 참조). Graceful Shutdown, 로깅, 분산 추적, 메트릭, 헬스체크는 항상 적용한다.

## 타임아웃 〔`EXTERNAL_API: true`〕

```java
// RestTemplate
SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
factory.setConnectTimeout(3_000);   // 3초
factory.setReadTimeout(10_000);     // 10초

// WebClient
webClient.get()
    .retrieve()
    .bodyToMono(Response.class)
    .timeout(Duration.ofSeconds(10));
```

## Retry 〔`EXTERNAL_API: true`〕

```yaml
# application.yml
resilience4j.retry:
  instances:
    externalApi:
      maxAttempts: 3
      waitDuration: 500ms
      retryExceptions:
        - java.io.IOException
        - java.util.concurrent.TimeoutException
      ignoreExceptions:
        # 비즈니스 예외 — 재시도해도 결과가 달라지지 않음
        - com.example.exception.BusinessException
        - com.example.exception.BadRequestException
```

> **주의**: 4xx 계열 HTTP 응답을 예외로 변환하는 경우 `ignoreExceptions`에 반드시 포함한다.
> 재시도해도 결과가 달라지지 않으며, 불필요한 부하만 발생한다. 사용하는 HTTP 클라이언트
> 라이브러리(Feign / RestTemplate / WebClient)에 따라 예외 클래스가 다르므로 실제 프로젝트
> 의존성 버전을 확인하고 해당 타입을 명시한다(라이브러리별 `$` 내부 클래스 표기 포함, YAML에서
> `$` 포함 클래스명은 따옴표 필수). 클래스명 검증 책임 소재는 `.claude/agents/ops-checker.md`
> "Retry" 섹션을 따른다.

## Circuit Breaker 〔`EXTERNAL_API: true`〕

```yaml
resilience4j.circuitbreaker:
  instances:
    paymentService:
      slidingWindowSize: 10
      failureRateThreshold: 50      # 50% 실패 시 OPEN
      waitDurationInOpenState: 30s
      permittedNumberOfCallsInHalfOpenState: 3
resilience4j.bulkhead:
  instances:
    paymentService:
      maxConcurrentCalls: 10
```

## Graceful Shutdown (ECS 배포 필수, 항상 적용)

```yaml
# application.yml
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 25s  # ECS stopTimeout(30초)보다 여유 있게
```

- ECS Task Definition `stopTimeout` 설정 (기본 30초, SIGTERM 처리 시간 부족 가능성 확인)
- ALB Target Group `deregistrationDelay`: 커넥션 드레이닝 충분한지 (기본 300초, 불필요하면 단축 가능)
- SIGTERM 수신 후 새 요청 거부 + 진행 중 요청 완료 보장

## 로깅 (구조화 로그, CloudWatch 최적화)

```java
// 권장: JSON 구조화 로그 (logstash-logback-encoder 사용)
log.info("Order created", kv("orderId", order.getId()), kv("userId", userId));
```

- `catch` 블록에서 예외를 무시하거나 `System.out.println`으로 출력 금지
- 패스워드/토큰/API 키/DTO 전체 `toString()` 로그 출력 금지
- `DEBUG` 레벨 로그를 운영 코드에 과도하게 남기지 않는다 (CloudWatch 비용 증가)

## 분산 추적 (MDC)

```java
// 필수: 요청 진입 시 MDC 설정 (OncePerRequestFilter 기반)
MDC.put("traceId", UUID.randomUUID().toString());
MDC.put("userId", getCurrentUserId());
// 응답 후 반드시 MDC.clear()
```

- `RestTemplate` / `WebClient` 호출 시 `X-Trace-Id` 헤더 전달
- `@Async` 비동기 메서드는 `MDC.getCopyOfContextMap()`으로 컨텍스트 복사

## 메트릭 (Micrometer)

```java
@Timed(value = "order.create", description = "주문 생성 처리 시간")
public OrderResponse createOrder(OrderRequest request) { ... }
```

비즈니스 핵심 지표(주문 생성/실패 수, 결제 처리 시간, 외부 API 성공/실패 비율)에
`Counter`/`Gauge`/`Timer`를 둔다.

## 헬스체크 (Actuator, ECS Fargate)

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health, metrics, prometheus
```

- `/actuator/health` 응답 3초 이내 (ECS 기본 타임아웃)
- ECS Task Definition 헬스체크 `startPeriod` 60초 권장 (Cold Start 고려)
- `/actuator/**` 인증/인가 설정은 이 표준이 아니라 `.claude/agents/security-checker.md`가 검토한다.

## Kafka / SQS 운용 기준

`MESSAGE_BROKER: kafka` / `sqs` / `kafka+sqs`일 때의 멱등성·DLQ·Trace ID 전파·가시성 타임아웃 등
세부 기준은 대부분의 프로젝트에 해당하지 않으므로 여기 옮기지 않고
`.claude/agents/ops-checker.md`의 "메시지 브로커" 섹션에 그대로 둔다.
