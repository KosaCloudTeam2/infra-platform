# 구현 범위 상세

## 1. 반드시 구현할 항목

### 네트워크

- VPC `10.20.0.0/16`
- Public Subnet 2개
- Private Subnet 2개
- Internet Gateway
- Public Route Table
- Private Route Table
- AWS burst용 ALB Security Group
- AWS burst EC2 Security Group
- 온프레미스-AWS 연결 방식 문서화(VPN, WireGuard, 제한된 HTTPS 중 택1)
- 온프레미스 관리 접속 경로 문서화(Bastion 또는 VPN)
- 온프레미스 Ingress 진입 방식 문서화(Ingress 직접 접근 또는 HAProxy VIP 선택)

### 컴퓨팅

- Proxmox VM 기반 온프레미스 Kubernetes control plane
- Proxmox VM 기반 Kubernetes worker node
- Kubernetes Deployment
- Kubernetes Service
- Ingress Controller
- AWS EC2 Launch Template
- AWS EC2 Auto Scaling Group
- AWS ALB Target Group
- CloudWatch Alarm
- EKS 최소 PoC: 클러스터 생성, Managed Node Group 최소 구성, 샘플 앱 배포, 삭제 검증

### 애플리케이션

- 현재 `app/`은 인프라 배포 검증용 임시 샘플 앱
- 실제 서비스 앱이 준비되면 Dockerfile, build 경로, 컨테이너 포트, Health Check 경로를 맞춰 교체
- 프로젝트 범위는 앱 기능 개발이 아니라 배포/운영 인프라 구축
- 온프레미스 Kubernetes와 AWS burst EC2에서 같은 앱 버전을 실행할 수 있도록 이미지 태그 기준을 통일

### 데이터베이스

- AWS RDS 제외
- Proxmox VM 기반 Percona XtraDB Cluster 3노드
- DB VM 디스크는 Ceph RBD 사용
- ProxySQL 1대 기본 MVP
- ProxySQL 2대 + Internal NLB는 선택 확장(일정 여유 시)
- Percona XtraBackup 기반 백업
- 백업 파일 Ceph RGW 업로드

### 배포

- Docker Hub Repository 또는 팀이 선택한 컨테이너 레지스트리
- GitHub Actions workflow
- Argo CD 설치와 GitOps Application 구성
- Docker image tag: `git-sha`, `latest`
- Kubernetes manifest 또는 Helm chart 적용
- Argo CD가 추적할 manifest 경로와 sync 정책 정의
- AWS Launch Template의 앱 bootstrap 버전 갱신 절차
- AWS burst app ASG instance refresh 수동 실행 절차

### 보안

- GitHub Actions OIDC Provider
- Deploy Role
- GitHub Actions Deploy Role
- EC2 Instance Role 또는 Kubernetes Secret 접근 Role
- Kubernetes Secret과 GitHub Secret
- WAF Managed Rule
- Security Group 최소 허용

### 관측성

- Kubernetes 또는 EC2 local container logs
- ALB 5xx Alarm
- AWS EC2 CPU/Request 기반 scale-out/scale-in Alarm
- Unhealthy Host Alarm
- 배포 성공/실패 기록
- ProxySQL backend 상태 확인
- PXC `wsrep` 클러스터 상태 확인
- Ceph Health 상태 확인
- 부하 테스트 도구 후보와 scale-out 시연 기준 문서화

### 스토리지

- Ceph RGW 기반 S3 호환 백업 저장소
- Proxmox 기반 Ceph RBD를 DB VM 디스크와 온프레미스 VM/K8s 볼륨에 사용
- CephFS 기반 공유 파일 시스템은 선택 구현

## 2. 선택 구현 항목

- Route 53 도메인 연결
- ACM 인증서와 HTTPS Listener
- S3 + CloudFront 정적 자산 오프로딩
- Blue/Green 배포
- CloudWatch Agent 기반 EC2 container log 수집
- AWS Secrets Manager 기반 AWS burst app secret 주입
- Prometheus/Grafana 별도 운영
- Loki 기반 Kubernetes 로그 조회
- Locust 또는 JMeter 기반 부하 테스트
- DNS VIP/CoreDNS/Keepalived 기반 내부 DNS 이중화
- HAProxy VIP/Keepalived 기반 온프레미스 Ingress 앞단 이중화
- PMM(Percona Monitoring and Management)
- Private Registry 또는 Harbor 기반 온프레미스 이미지 저장소
- Elastic Container Registry(ECR) 기반 AWS-only 비교안 이미지 저장소
- ECS Fargate 기반 AWS-only 비교안
- Argo CD HA 구성과 SSO 연동
- ProxySQL 2대 운영 시 설정 동기화 자동화
- AWS S3 2차 백업 복제
- Ceph CSI 기반 Kubernetes PVC
- Proxmox VE 기반 온프레미스 VM/LXC 운영 시연
- AWS Load Balancer Controller(ALB Ingress Controller) 기반 EKS/클라우드 Kubernetes 외부 노출 검토
- EKS Hybrid Nodes 검토
- 운영용 EKS 전환 검토
- Cloudflare Load Balancing 또는 Global Server Load Balancing(GSLB) 기반 다중 endpoint 분산
- Argo Rollouts 기반 Blue/Green 또는 Canary 배포
- KEDA 기반 Kubernetes workload autoscaling 고도화
- Prometheus remote_write, Thanos, Loki, Ceph RGW 기반 장기 관측성 저장소
- Redis Sentinel 기반 세션/캐시 고가용성
- Sentry 기반 애플리케이션 예외 추적
- AI 기반 장애 로그 요약, 이상 탐지, Runbook 추천
- Vault, PKI, Keycloak 기반 보안 운영 고도화

### Kubernetes cloud bursting 구현 경계

현재 MVP의 운영 런타임은 비용 우선 구조이므로 EKS로 전환하지 않음. 다만 AWS 관리형 Kubernetes 경험
확보를 위해 EKS 최소 PoC는 MVP 보조 산출물로 포함하고, 아래 구조를 구분해서 설명해야 함.

| 구분                                          | 설명                                                     | MVP 포함 여부 |
| :-------------------------------------------- | :------------------------------------------------------- | :------------ |
| 온프레미스 Kubernetes + AWS EC2 ASG/ALB burst | 온프레미스 K8s와 AWS ASG가 별도 런타임으로 동작          | 포함          |
| EKS 최소 PoC                                  | 관리형 Kubernetes 생성, 샘플 앱 배포, 삭제 검증 중심     | 포함          |
| ALB Ingress Controller / EKS Hybrid Nodes     | EKS 기반 외부 노출 또는 하이브리드 운영 고도화           | 선택 확장     |
| 운영용 EKS 전환                               | AWS 관리형 Kubernetes를 실제 운영 런타임으로 전환하는 안 | 선택 확장     |

AWS EC2에 직접 Kubernetes를 설치해 온프레미스 클러스터의 worker로 붙이는 구성은 인증서, Container
Network Interface(CNI), 노드 bootstrap, VPN, Autoscaler 설계 부담이 크고 EKS 경험 목적과도 맞지
않으므로 이번 MVP와 선택 확장 범위에서 제외함.

## 3. 구현하지 않을 항목

- 신규 서비스 기능 개발
- 복잡한 권한 관리 UI
- 멀티 리전 Active-Active
- 운영 수준의 DR 자동화
- AWS burst 앱에서 Proxmox/Ceph RBD 직접 마운트
- Proxmox 관리 UI 인터넷 공개
- EKS control plane 상시 운영
- AWS EC2에 직접 Kubernetes를 설치해 클라우드 worker로 붙이는 구성
- GitLab self-managed와 Harbor를 MVP 필수로 운영
- Vault, PKI, Keycloak을 Day 13 MVP 필수로 운영
- PXC/Galera를 active-active write 구조로 운영
- PXC 3노드 구성에서 garbd를 필수로 운영
- Cloudflare GSLB, KEDA, Argo Rollouts, Redis Sentinel, Sentry, Thanos/Loki 장기 저장소를 Day 13 MVP
  필수로 운영
