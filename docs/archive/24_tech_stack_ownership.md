# 기술 스택 담당 분류

현재 팀 논의 기준으로 프로젝트에서 사용할 기술 스택을 담당자별로 분류한 문서임. 실제 이름은 넣지
않고 `팀원 1~4` 기준으로 정리함.

주의:

- 이 문서는 역할 배정 기준표이며, 세부 구현 중 일부 항목은 협업이 필요함.
- MVP 필수 항목과 선택 확장 항목을 구분함.
- 담당 논의가 필요한 기술 스택은 별도 섹션으로 분리함.

---

## 1. 현재 역할 기준

| 팀원   | 현재 담당 방향                     | 핵심 책임                                                                                                     |
| :----- | :--------------------------------- | :------------------------------------------------------------------------------------------------------------ |
| 팀원 1 | Observability / Integration / Demo | 관측성, 통합 검증, 웹 서버 기동/접속 검증, 앱-DB 연결 검증, 장애 시나리오, Runbook, 부하 테스트, 발표 흐름    |
| 팀원 2 | Cloud / Network / IaC / AWS Burst  | AWS IaC, 클라우드 네트워크(VPC/Subnet/Route/SG), EC2 ASG/ALB burst, IAM/OIDC, WAF, 비용 제한, AWS 리소스 정리 |
| 팀원 3 | DB / Storage / On-prem DB Network  | DB 관련 온프레미스 네트워크, pfSense, PXC, ProxySQL, Ceph, 백업/복구, DB/스토리지 보안 경계                   |
| 팀원 4 | CI/CD / GitOps / Repository        | GitHub Actions, Docker Hub, Argo CD, GitOps manifest, 이미지 태그/배포 흐름, 앱 Secret/환경변수 설정          |

---

## 2. 담당자별 주 기술 스택

### 2.1 팀원 1: Observability / Integration / Demo

| 기술 스택                           | 현재 위치 | 비고                                                  |
| :---------------------------------- | :-------- | :---------------------------------------------------- |
| CloudWatch 지표/알람 해석           | MVP       | ALB, EC2 ASG, 5xx, UnHealthyHost, CPU 지표 확인       |
| Kubernetes Pod/Deployment 상태 확인 | MVP       | Pod Ready, rollout, 장애 판단                         |
| Kubernetes logs / EC2 Docker logs   | MVP       | 앱 장애 분석과 발표 캡처                              |
| 통합 검증                           | MVP       | K8s, ALB, DB, Ceph, CI/CD 흐름 연결 확인              |
| 장애 시나리오                       | MVP       | Pod 장애, 배포 실패, SG 오설정, DB 장애 시나리오 정리 |
| Runbook 품질 관리                   | MVP       | 배포/롤백/모니터링/장애 대응 문서 검토                |
| 웹 서버 실행(기동/접속 검증)        | MVP       | 기배포 앱의 health check, Ingress/ALB 접속 확인       |
| Kubernetes Secret                   | MVP       | DB 접속 정보, 앱 환경변수 주입 기준 검증              |
| 앱-DB 연결                          | MVP       | 팀원 3의 ProxySQL endpoint 연동 검증 주관             |
| k6 또는 JMeter 부하 테스트          | MVP/검증  | 팀원 1 주 담당. AWS ASG scale-out 시연 지표 생성      |
| p95 latency 지표                    | MVP/검증  | 부하 테스트 결과 설명용                               |
| Prometheus/Grafana                  | 선택 확장 | CloudWatch 중심이 어려울 때 또는 발표 보강용          |
| Loki / Fluent Bit                   | 선택 확장 | 로그 수집 고도화 후보                                 |
| Sentry                              | 선택 확장 | 앱 예외와 stack trace 추적 후보                       |
| AI 장애 로그 요약 / Runbook 추천    | 선택 확장 | 운영 보조 아이디어. MVP 필수 아님                     |

---

### 2.2 팀원 2: Cloud / Network / IaC / AWS Burst

| 기술 스택                         | 현재 위치 | 비고                                                |
| :-------------------------------- | :-------- | :-------------------------------------------------- |
| Terraform                         | MVP       | AWS 리소스 IaC 기준                                 |
| AWS VPC/Subnet/Route Table        | MVP       | 클라우드 네트워크 범위(AWS) 책임                    |
| Internet Gateway / NAT 선택       | MVP       | 비용 기준 포함                                      |
| AWS ALB / Target Group / Listener | MVP       | AWS burst 외부 진입점                               |
| AWS EC2 Auto Scaling Group        | MVP       | AWS burst scale-out/scale-in                        |
| Launch Template / user data       | MVP       | AWS burst 앱 bootstrap                              |
| Security Group                    | MVP       | 팀원 3의 네트워크/DB 요구사항 반영 필요             |
| WAF Managed Rule                  | MVP       | Count/Block 정책 설명                               |
| IAM / GitHub OIDC Role            | MVP       | 장기 Access Key 미사용 기준                         |
| SSM 접근 경로                     | MVP       | DB/운영 EC2 접근 시 팀원 3과 협업                   |
| CloudWatch Alarm Terraform        | MVP       | 팀원 1의 관측 기준 반영                             |
| 비용 제한/리소스 정리             | MVP       | NAT, ALB, WAF, EC2, EKS PoC 삭제 기준 포함          |
| Route 53 / ACM / HTTPS            | 선택 확장 | 발표 완성도 보강 후보                               |
| CloudFront / S3 정적 자산         | 선택 확장 | AWS-only 확장 후보                                  |
| AWS Load Balancer Controller      | 선택 확장 | EKS 고도화 시 팀원 4와 협업                         |
| Karpenter                         | 선택 확장 | 운영용 EKS 전환 또는 EKS autoscaling 고도화 시 검토 |

---

### 2.3 팀원 3: DB / Storage / On-prem DB Network

| 기술 스택                             | 현재 위치      | 비고                                                       |
| :------------------------------------ | :------------- | :--------------------------------------------------------- |
| DB 관련 온프레미스 네트워크 설계/운영 | MVP            | DB 트래픽 기준의 pfSense, VLAN, 라우팅, 방화벽 기준        |
| pfSense 설치/설정                     | MVP/운영 기반  | DB 접근 경로 중심의 VPN/방화벽/NAT/라우팅 기준 정리        |
| 온프레미스-AWS 연결 방식              | MVP 문서화     | DB 접근 경로 기준으로 VPN, WireGuard, 제한된 HTTPS 중 선택 |
| Proxmox 네트워크                      | MVP            | 관리망/스토리지망 구분, MTU, bridge 확인                   |
| Ceph 스토리지망                       | MVP/선택 구현  | RBD/CephFS/RGW 구성과 네트워크 검증                        |
| iperf                                 | 검증 보조      | Proxmox/Ceph망, VPN 대역폭 검증                            |
| Percona XtraDB Cluster(PXC)           | MVP            | 3노드 기준                                                 |
| Galera/wsrep                          | MVP 설명       | PXC 내부 복제 기반. 별도 Galera 구축 아님                  |
| Single Writer 운영                    | MVP            | active-active write는 채택하지 않음                        |
| ProxySQL                              | MVP            | 앱 DB 접근 단일화                                          |
| DB 계정/권한                          | MVP            | 앱 계정, 백업 계정, 운영 계정 분리                         |
| Percona XtraBackup                    | MVP            | DB 백업 산출물 생성                                        |
| Ceph RGW                              | MVP            | DB 백업 저장소                                             |
| Ceph RBD / CephFS                     | 선택 구현      | Proxmox VM/K8s 볼륨 고급 활용                              |
| garbd                                 | 제외/향후 논의 | PXC 3노드 기준 불필요. 2노드 제약 시 검토                  |
| Redis Sentinel                        | 선택 확장      | 앱 세션/캐시 요구가 생길 때 검토                           |
| ProxySQL 2대 + Internal NLB           | 선택 확장      | 팀원 2와 협업 필요                                         |

---

### 2.4 팀원 4: CI/CD / GitOps / Repository

| 기술 스택                     | 현재 위치 | 비고                                                                                                  |
| :---------------------------- | :-------- | :---------------------------------------------------------------------------------------------------- |
| GitHub Actions                | MVP       | 이미지 빌드, push, 배포 workflow                                                                      |
| Docker Hub                    | MVP       | 기본 이미지 저장소                                                                                    |
| Dockerfile / 이미지 태그 전략 | MVP       | `git-sha`, `latest` 기준                                                                              |
| Argo CD                       | MVP       | 온프레미스 Kubernetes GitOps 배포                                                                     |
| Kubernetes manifest           | MVP       | Deployment, Service, Ingress 중심. Secret/환경변수 설정은 팀원 4가 수행하고 연결 검증은 팀원 1이 담당 |
| GitOps Application 구성       | MVP       | Argo CD sync/health 확인                                                                              |
| 앱 배포 rollback              | MVP       | 이전 image tag 또는 Git revision 복구                                                                 |
| AWS burst 앱 bootstrap 지원   | MVP       | 팀원 2의 Launch Template/user data와 협업                                                             |
| Private Registry / Harbor     | 선택 확장 | Docker Hub 대체 후보                                                                                  |
| Argo Rollouts                 | 선택 확장 | Blue/Green, Canary 배포 고도화                                                                        |
| KEDA                          | 선택 확장 | Kubernetes workload autoscaling 고도화                                                                |
| AWS Load Balancer Controller  | 선택 확장 | EKS 고도화 시 팀원 2와 협업                                                                           |

---

### 2.5 담당 논의가 필요한 기술 스택

아래 항목은 특정 팀원에게 고정하지 않고 별도 논의가 필요함.

| 기술 스택             | 현재 위치       | 논의가 필요한 이유                                     | 협업 후보                |
| :-------------------- | :-------------- | :----------------------------------------------------- | :----------------------- |
| EKS 최소 PoC          | MVP 보조 산출물 | AWS/IAM/비용, Kubernetes 배포, 검증/캡처가 함께 필요함 | 팀원 2 + 팀원 4 + 팀원 1 |
| Cloudflare/GSLB       | 선택 확장       | 네트워크 라우팅과 외부 DNS/클라우드 연동이 겹침        | 팀원 3 + 팀원 2          |
| Prometheus/Grafana    | 선택 확장       | 관측성 기준과 Kubernetes 배포가 겹침                   | 팀원 1 + 팀원 4          |
| Loki/Fluent Bit       | 선택 확장       | 로그 관측성과 Kubernetes DaemonSet 배포가 겹침         | 팀원 1 + 팀원 4          |
| AWS S3 2차 백업       | 선택 확장       | 백업 정책과 AWS bucket/IAM 구성이 겹침                 | 팀원 3 + 팀원 2          |
| ProxySQL Internal NLB | 선택 확장       | ProxySQL 운영과 AWS NLB/Terraform이 겹침               | 팀원 3 + 팀원 2          |

EKS 최소 PoC 결정 필요:

- [ ] EKS 최소 PoC 주 담당을 팀원 2, 팀원 4, 또는 공동 담당 중 하나로 정함
- [ ] PoC에 사용할 샘플 앱과 이미지 태그를 정함
- [ ] 생성 후 삭제 확인 체크리스트를 정함

---

## 3. 유동적으로 맡을 수 있는 기술 스택

| 기술 스택             | 담당 후보              | 이유                                                       |
| :-------------------- | :--------------------- | :--------------------------------------------------------- |
| k6/JMeter             | 팀원 1                 | 부하 시나리오와 관측 지표 중심. 팀원 2는 ASG/ALB 지표 보조 |
| iperf                 | 팀원 3 또는 팀원 1     | 네트워크/스토리지망 검증은 팀원 3, 결과 캡처는 팀원 1      |
| Prometheus/Grafana    | 팀원 1 또는 팀원 4     | 관측성 기준은 팀원 1, K8s 배포는 팀원 4                    |
| Loki/Fluent Bit       | 팀원 1 또는 팀원 4     | 로그 관측성과 K8s DaemonSet 배포가 겹침                    |
| Argo Rollouts         | 팀원 4 또는 팀원 1     | 배포 전략은 팀원 4, 발표 시나리오는 팀원 1                 |
| AWS S3 2차 백업       | 팀원 3 또는 팀원 2     | 백업 정책은 팀원 3, AWS bucket/IAM은 팀원 2                |
| ProxySQL Internal NLB | 팀원 3 또는 팀원 2     | ProxySQL 운영은 팀원 3, NLB/Terraform은 팀원 2             |
| AI 운영 보조          | 팀원 1 중심, 전원 협업 | 장애 로그 요약, 이상 탐지, Runbook 추천은 통합 운영 성격   |
| Sentry                | 팀원 1 또는 팀원 4     | 앱 예외 추적과 장애 분석 영역이 겹침                       |
| Redis Sentinel        | 팀원 3 또는 팀원 4     | 상태 저장 계층 운영과 앱 세션 요구가 겹침                  |
| Cloudflare/GSLB       | 팀원 3 또는 팀원 2     | 네트워크/라우팅은 팀원 3, 외부 DNS/클라우드 연동은 팀원 2  |

---

## 4. 선택 확장 / 향후 논의 기술 스택

| 기술 스택                                            | 분류                          | 우선 담당 후보  |
| :--------------------------------------------------- | :---------------------------- | :-------------- |
| AWS Load Balancer Controller(ALB Ingress Controller) | 선택 확장                     | 팀원 2 + 팀원 4 |
| EKS Hybrid Nodes                                     | 선택 확장                     | 팀원 2 + 팀원 3 |
| 운영용 EKS 전환                                      | 향후 과제                     | 팀원 2 + 팀원 4 |
| Karpenter                                            | EKS 고도화 확장               | 팀원 2 + 팀원 4 |
| KEDA                                                 | Kubernetes autoscaling 고도화 | 팀원 4 + 팀원 1 |
| Argo Rollouts Blue/Green/Canary                      | 선택 확장                     | 팀원 4          |
| Cloudflare/GSLB                                      | 선택 확장                     | 팀원 3 + 팀원 2 |
| Thanos / Loki / Fluent Bit / Ceph RGW 장기 저장      | 선택 확장                     | 팀원 1 + 팀원 3 |
| Redis Sentinel                                       | 앱 요구 발생 시 선택 확장     | 팀원 3 + 팀원 4 |
| Sentry                                               | 앱 예외 추적 선택 확장        | 팀원 1 + 팀원 4 |
| garbd                                                | PXC 2노드 제약 시 논의        | 팀원 3          |
| Vault / PKI / Keycloak                               | 보안 고도화                   | 팀원 2 + 팀원 3 |
| Route 53 / ACM / HTTPS                               | 선택 확장                     | 팀원 2          |
| CloudFront / S3 정적 자산                            | 선택 확장                     | 팀원 2          |
| ProxySQL 2대 + Internal NLB                          | 선택 확장                     | 팀원 3 + 팀원 2 |

---

## 5. 현재 범위에서 제외하는 항목

| 기술 스택 / 구성                                            | 판단                              |
| :---------------------------------------------------------- | :-------------------------------- |
| AWS EC2에 직접 Kubernetes 설치해 cloud worker로 붙이는 구성 | MVP와 선택 확장에서 제외          |
| PXC/Galera active-active write 운영                         | MVP 제외. Single Writer 사용      |
| garbd 필수 운영                                             | PXC 3노드 기준 불필요             |
| 운영 수준 DR 자동화                                         | MVP 제외                          |
| GitOps/apps/IaC repo 분리                                   | MVP는 단일 repo 유지. 향후 확장   |
| 운영용 EKS 전환                                             | 선택 확장/향후 과제               |
| Karpenter 기반 EKS node autoscaling                         | EKS 고도화 확장. 최소 PoC 범위 밖 |

---

## 6. 담당 경계 요약

| 영역                            | 주 담당        | 협업                        |
| :------------------------------ | :------------- | :-------------------------- |
| 온프레미스 DB 네트워크/pfSense  | 팀원 3         | 팀원 2                      |
| AWS IaC/클라우드 네트워크/burst | 팀원 2         | 팀원 1, 팀원 4              |
| DB/Storage                      | 팀원 3         | 팀원 2, 팀원 1              |
| CI/CD/GitOps                    | 팀원 4         | 팀원 1                      |
| 웹 서버 기동/접속 및 앱-DB 검증 | 팀원 1         | 팀원 4, 팀원 3              |
| 관측성/장애 대응                | 팀원 1         | 전원                        |
| 발표/시연                       | 전원           | 팀원 1 통합                 |
| EKS 최소 PoC                    | 담당 논의 필요 | 팀원 2, 팀원 4, 팀원 1 협업 |
