# 장애 시나리오

> 아키텍처 상세 참조: [Ops Flow / Extensions](../architecture/details/ops_flow_and_extensions.md)

## 1. Pod 또는 앱 인스턴스 장애

- **상황:** 컨테이너 또는 앱 프로세스 비정상 종료
- **감지:** Kubernetes Pod `CrashLoopBackOff`, Argo CD Health 저하, Kubernetes 또는 EC2 Docker logs
- **복구:** Kubernetes Deployment 재시작, 이전 이미지 태그 롤백
- **시연:** 잘못된 환경 변수로 앱 시작 실패 유도

## 2. Health Check 실패

- **상황:** 앱은 실행되지만 `/health` 응답 실패
- **감지:** ALB Target Group `unhealthy`
- **복구:** 정상 이미지 롤백 또는 Health Check 경로 수정
- **시연:** Health Check Path 또는 readinessProbe 오설정 배포

## 3. 배포 실패

- **상황:** 신규 버전이 정상 상태에 도달하지 못함
- **감지:** Argo CD `OutOfSync`/`Degraded`, Kubernetes rollout 실패
- **복구:** 이전 Git revision 또는 image tag로 롤백
- **시연:** 존재하지 않는 이미지 태그 배포

## 4. 트래픽 증가

- **상황:** CPU/Memory 사용률 상승
- **감지:** Kubernetes Metrics 또는 CloudWatch Metrics, ALB Request Count
- **복구:** AWS EC2 Auto Scaling으로 burst 인스턴스 증가 또는 Kubernetes replica 조정
- **시연:** `scripts/load-test.ps1` 또는 k6로 요청 증가
