# 04 Observability / Integration / Demo 상세 구현

담당: 팀원 1, 전원 보조

## 1. 목표

서비스 상태를 확인할 수 있는 최소 관측 체계를 구성하고, 발표에서 보여줄 장애 대응 시나리오를
안정적으로 준비함.

## 2. 구현 범위

- CloudWatch Metrics/Alarm 또는 Prometheus/Grafana
- ALB 5xx Alarm
- Unhealthy Host Alarm
- EC2 CPU/Request 기반 Alarm
- Argo CD Application sync/health 상태
- Kubernetes Deployment rollout 상태
- 웹 서버 기동/접속(Ingress/ALB) 검증
- 앱-DB 연결(ProxySQL endpoint) 검증
- PXC/ProxySQL/Ceph 상태 확인 Runbook
- 장애 시나리오 통합
- 시연 순서 작성

## 3. 관측 지표

| 대상       | 지표                      | 목적                   |
| :--------- | :------------------------ | :--------------------- |
| Argo CD    | Sync/Health               | GitOps 배포 상태 확인  |
| Kubernetes | Pod ready, rollout status | 앱 배포 정상 여부      |
| ALB        | Target 5xx                | AWS burst 앱 오류 감지 |
| ALB        | UnHealthyHostCount        | Target 장애 감지       |
| EC2 ASG    | CPU, Request              | 스케일링 판단          |
| ProxySQL   | backend status            | DB 노드 장애 확인      |
| PXC        | wsrep status              | 클러스터 정합성 확인   |
| Ceph       | health status             | 백업 저장소 상태 확인  |

## 4. 시연 시나리오

### 4.1 배포 시연

1. GitHub Actions 실행
2. Docker Hub 이미지 확인
3. Argo CD Application sync 확인
4. Kubernetes Deployment rollout 확인
5. Service 또는 Ingress URL 접속
6. 앱-DB 연결 상태(ProxySQL endpoint) 확인

### 4.2 앱 장애 시연

1. 잘못된 이미지 또는 Health Check 실패 유도
2. Argo CD sync 상태 또는 Kubernetes rollout 상태 확인
3. CloudWatch 또는 Grafana 지표 확인
4. 이전 Git revision 또는 image tag로 롤백 수행

### 4.3 DB/백업 시연

1. 웹 서버 기동 후 ProxySQL endpoint 접속 확인
2. PXC 상태 확인
3. XtraBackup 산출물 확인
4. Ceph RGW 업로드 파일 확인

## 5. 완료 기준

- [ ] Argo CD와 Kubernetes 배포 상태 확인
- [ ] CloudWatch 또는 Grafana에서 앱 로그와 지표 확인
- [ ] ALB/EC2 기본 알람 생성
- [ ] DB/Ceph 상태 확인 명령 정리
- [ ] 시연 스크립트와 캡처 준비
- [ ] 발표 리허설에서 15분 내 설명 가능
