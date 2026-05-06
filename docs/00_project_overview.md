# 프로젝트 개요

## 1. 한 줄 정의

기존 애플리케이션을 온프레미스 Kubernetes에서 기본 운영하고, 부하 증가 시 AWS Elastic Compute
Cloud(EC2) Auto Scaling과 애플리케이션 로드 밸런서(Application Load Balancer, ALB) 기반 burst
영역으로 확장하는 비용 우선 하이브리드 인프라 플랫폼 구축 프로젝트

## 2. 성공 기준

- GitHub `main` 브랜치에 병합된 코드가 GitHub Actions를 통해 Docker 이미지로 빌드됨
- 빌드된 이미지가 Docker Hub 또는 팀 표준 컨테이너 레지스트리에 태그와 함께 저장됨
- 온프레미스 Kubernetes Deployment가 최신 이미지로 갱신됨
- Argo CD 기반 GitOps 배포로 Kubernetes manifest 동기화 가능함
- AWS burst 영역의 ALB Health Check가 정상이고 부하 증가 시 EC2 인스턴스가 Target Group에 등록됨
- Kubernetes logs 또는 EC2 Docker logs에서 컨테이너 로그 확인 가능함
- CloudWatch Alarm 또는 대시보드로 AWS EC2 CPU/Request/5xx/Unhealthy Host를 확인 가능함
- 웹 방화벽(Web Application Firewall, WAF) 또는 Security Group으로 최소 보안 정책이 적용됨
- AWS Relational Database Service(RDS) 없이 Percona XtraDB Cluster(PXC)와 ProxySQL 기반 DB 접근이
  가능함
- Percona XtraBackup 결과를 Ceph RADOS Gateway(RGW)에 저장할 수 있음
- 배포 실패 또는 앱 장애 상황에서 롤백/복구 시연 가능함

## 3. MVP와 확장 범위

### MVP

- 가상 사설 클라우드(Virtual Private Cloud, VPC) 1개
- Public Subnet 2개, Private Subnet 2개
- Proxmox VM 기반 온프레미스 Kubernetes
- Argo CD 기반 GitOps 배포
- AWS burst ALB 1개
- AWS EC2 Auto Scaling Group 1개
- Docker Hub Repository 또는 팀 표준 컨테이너 레지스트리 1개
- CloudWatch Metrics/Alarm, Kubernetes 또는 EC2 local logs
- GitHub Actions OpenID Connect(OIDC) 배포 Role
- Security Group 최소 허용 정책
- WAF 기본 Managed Rule 적용
- Percona XtraDB Cluster 3노드
- ProxySQL 기반 DB 접근 단일화
- Ceph RGW 기반 DB 백업 저장소

### 선택 확장

- Route 53 + AWS Certificate Manager(ACM) 인증서
- CloudFront + Simple Storage Service(S3) 정적 자산 오프로딩
- Blue/Green 배포
- Prometheus/Grafana 별도 구성
- 부하 테스트와 Auto Scaling 정책 고도화
- Private Registry 또는 Harbor 기반 온프레미스 이미지 저장소
- Elastic Container Registry(ECR) 기반 AWS-only 비교안 이미지 저장소
- ECS Fargate 기반 AWS-only 비교안
- ProxySQL 2대 + Internal NLB
- Ceph RADOS Block Device(RBD)/CephFS 고급 활용
- AWS S3 2차 백업 복제
- Elastic Kubernetes Service(EKS) Hybrid Nodes 전환
- AWS EC2를 직접 구축 Kubernetes worker node로 자동 join

## 4. 프로젝트에서 제외할 항목

- 신규 백엔드/프론트엔드 기능 개발
- 복잡한 마이크로서비스 분리
- EKS 기반 운영 클러스터 전면 구축
- 단일 Kubernetes 클러스터 기반 AWS worker node 자동 확장 전체 구현
- 장기 운영 비용 최적화 자동화 전체 구현

## 5. 발표 핵심 메시지

- 클라우드 인프라의 핵심은 “서비스를 띄우는 것”이 아니라 “반복 가능하고 안전하게 운영하는 구조”임
- 기본 실행은 온프레미스 Kubernetes에서 담당하고, AWS는 필요한 순간에만 burst capacity로 사용함
- GitHub Actions OIDC로 장기 Access Key 없이 배포함
- 장애가 발생해도 Health Check, Auto Scaling, 롤백 절차로 복구 가능함
