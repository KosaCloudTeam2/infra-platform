# 장애 시나리오

## 1. Task 장애

- **상황:** 컨테이너가 비정상 종료됨
- **감지:** ECS Service Events, Running Task 감소, CloudWatch Logs
- **복구:** ECS Service가 Desired Count를 맞추기 위해 Task 재시작
- **시연:** 잘못된 환경 변수로 앱 시작 실패 유도

## 2. Health Check 실패

- **상황:** 앱은 실행되지만 `/health` 응답 실패
- **감지:** ALB Target Group `unhealthy`
- **복구:** 정상 이미지 롤백 또는 Health Check 경로 수정
- **시연:** Health Check Path를 잘못 설정한 Task Definition 배포

## 3. 배포 실패

- **상황:** 신규 Task가 정상 상태에 도달하지 못함
- **감지:** ECS Deployment `FAILED`
- **복구:** Deployment Circuit Breaker 또는 수동 롤백
- **시연:** 존재하지 않는 이미지 태그 배포

## 4. 트래픽 증가

- **상황:** CPU/Memory 사용률 상승
- **감지:** ECS Service Metrics, ALB Request Count
- **복구:** AWS EC2 Auto Scaling으로 burst 인스턴스 증가 또는 Kubernetes replica 조정
- **시연:** `scripts/load-test.ps1` 또는 k6로 요청 증가
