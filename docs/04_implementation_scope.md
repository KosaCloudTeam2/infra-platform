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

### 컴퓨팅

- Proxmox VM 기반 온프레미스 Kubernetes control plane
- Proxmox VM 기반 Kubernetes worker node
- Kubernetes Deployment
- Kubernetes Service
- Ingress Controller
- AWS EC2 Launch Template
- AWS EC2 Auto Scaling Group
- AWS ALB Target Group
- CloudWatch Log Group

### 애플리케이션

- 현재 `app/`은 인프라 배포 검증용 임시 샘플 앱
- 실제 서비스 앱이 준비되면 Dockerfile, build 경로, 컨테이너 포트, Health Check 경로를 맞춰 교체
- 프로젝트 범위는 앱 기능 개발이 아니라 배포/운영 인프라 구축
- 온프레미스 Kubernetes와 AWS burst EC2에서 같은 앱 버전을 실행할 수 있도록 이미지 태그 기준을 통일

### 데이터베이스

- AWS RDS 제외
- EC2 기반 Percona XtraDB Cluster 3노드
- ProxySQL 1대 기본 MVP
- ProxySQL 2대 + Internal NLB는 Terraform 변수로 전환 가능한 안정성 보완 항목
- Percona XtraBackup 기반 백업
- 백업 파일 Ceph RGW 업로드

### 배포

- ECR Repository 또는 팀이 선택한 컨테이너 레지스트리
- GitHub Actions workflow
- Argo CD 설치와 GitOps Application 구성
- Docker image tag: `git-sha`, `latest`
- Kubernetes manifest 또는 Helm chart 적용
- Argo CD가 추적할 manifest 경로와 sync 정책 정의
- AWS Launch Template의 앱 bootstrap 버전 갱신 절차

### 보안

- GitHub Actions OIDC Provider
- Deploy Role
- GitHub Actions Deploy Role
- EC2 Instance Role 또는 Kubernetes Secret 접근 Role
- Secrets Manager
- WAF Managed Rule
- Security Group 최소 허용

### 관측성

- Container Logs
- ALB 5xx Alarm
- AWS EC2 CPU/Request 기반 scale-out/scale-in Alarm
- Unhealthy Host Alarm
- 배포 성공/실패 기록
- ProxySQL backend 상태 확인
- PXC `wsrep` 클러스터 상태 확인
- Ceph Health 상태 확인

### 스토리지

- Ceph RGW 기반 S3 호환 백업 저장소
- Proxmox 기반 Ceph RBD 온프레미스 VM/K8s 볼륨은 선택 구현
- CephFS 기반 공유 파일 시스템은 선택 구현

## 2. 선택 구현 항목

- Route 53 도메인 연결
- ACM 인증서와 HTTPS Listener
- S3 + CloudFront 정적 자산 오프로딩
- Blue/Green 배포
- Prometheus/Grafana 별도 운영
- PMM(Percona Monitoring and Management)
- Argo CD HA 구성과 SSO 연동
- ProxySQL 2대 운영 시 설정 동기화 자동화
- AWS S3 2차 백업 복제
- Ceph CSI 기반 Kubernetes PVC
- Proxmox VE 기반 온프레미스 VM/LXC 운영 시연
- EKS 기반 하이브리드 Kubernetes 전환 검토
- AWS EC2를 직접 구축 Kubernetes worker node로 자동 join
- Cluster Autoscaler 기반 AWS node 증감
- 기존 ECS Fargate 기반 AWS-only fallback 유지

### Kubernetes cloud bursting 구현 경계

현재 MVP는 비용 우선 구조이므로 EKS를 쓰지 않음. 단, 아래 두 구조는 구분해서 설명해야 함.

| 구분                                          | 설명                                            | MVP 포함 여부 |
| :-------------------------------------------- | :---------------------------------------------- | :------------ |
| 온프레미스 Kubernetes + AWS EC2 ASG/ALB burst | 온프레미스 K8s와 AWS ASG가 별도 런타임으로 동작 | 포함          |
| 단일 Kubernetes cluster node autoscaling      | AWS EC2가 K8s worker로 자동 join/release        | 선택 확장     |

단일 Kubernetes cluster 확장까지 구현하려면 인증서, CNI, 노드 bootstrap, VPN, Cluster Autoscaler
설계가 추가되므로 13일 MVP에서는 제외함.

## 3. 구현하지 않을 항목

- 신규 서비스 기능 개발
- 복잡한 권한 관리 UI
- 멀티 리전 Active-Active
- 운영 수준의 DR 자동화
- AWS burst 앱에서 Proxmox/Ceph RBD 직접 마운트
- Proxmox 관리 UI 인터넷 공개
- EKS control plane 상시 운영
