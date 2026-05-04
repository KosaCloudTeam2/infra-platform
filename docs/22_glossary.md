# 용어집

프로젝트 문서에서 반복 사용되는 AWS, 인프라, 배포 약어 정리

---

## AWS / 네트워크

| 약어 | Full name | 의미 |
| :--- | :-------- | :--- |
| ACM | AWS Certificate Manager | HTTPS 인증서 발급/관리 서비스 |
| ALB | Application Load Balancer | HTTP/HTTPS 요청을 여러 대상에 분산하는 L7 로드밸런서 |
| ASG | Auto Scaling Group | 부하나 정책에 따라 EC2 인스턴스 수를 자동 조정하는 그룹 |
| AZ | Availability Zone | AWS 리전 안의 독립 데이터센터 영역 |
| EC2 | Elastic Compute Cloud | AWS 가상 서버 서비스 |
| EKS | Elastic Kubernetes Service | AWS 관리형 Kubernetes 서비스 |
| IGW | Internet Gateway | VPC와 인터넷 연결 게이트웨이 |
| NAT | Network Address Translation | Private Subnet 리소스의 외부 통신 경로 |
| RDS | Relational Database Service | AWS 관리형 관계형 데이터베이스 서비스 |
| S3 | Simple Storage Service | AWS 객체 스토리지 서비스 |
| SG | Security Group | AWS 리소스 단위 가상 방화벽 |
| VPC | Virtual Private Cloud | AWS 계정 안의 격리된 가상 네트워크 |
| WAF | Web Application Firewall | 웹 요청 필터링과 공격 차단 서비스 |

## 배포 / 컨테이너

| 약어 | Full name | 의미 |
| :--- | :-------- | :--- |
| Argo CD | Argo Continuous Delivery | Git 저장소의 Kubernetes manifest를 클러스터에 동기화하는 GitOps 배포 도구 |
| CI/CD | Continuous Integration / Continuous Delivery | 코드 통합, 빌드, 테스트, 배포 자동화 흐름 |
| ECR | Elastic Container Registry | Docker 이미지 저장소 |
| ECS | Elastic Container Service | AWS 컨테이너 실행 서비스 |
| OIDC | OpenID Connect | GitHub Actions가 AWS 임시 권한을 받기 위한 인증 방식 |
| PR | Pull Request | 변경사항 병합 전 리뷰 요청 |

## 보안 / 운영

| 약어 | Full name | 의미 |
| :--- | :-------- | :--- |
| CLI | Command Line Interface | 터미널 기반 명령 실행 도구 |
| IAM | Identity and Access Management | AWS 사용자, 역할, 권한 관리 서비스 |
| MFA | Multi-Factor Authentication | 비밀번호 외 추가 인증 방식 |
| SSM | Systems Manager | EC2 접속, 명령 실행, 운영 자동화 서비스 |

## 데이터 / 스토리지

| 약어 | Full name | 의미 |
| :--- | :-------- | :--- |
| PMM | Percona Monitoring and Management | Percona DB 모니터링 도구 |
| PXC | Percona XtraDB Cluster | MySQL 호환 동기식 DB 클러스터 |
| RBD | RADOS Block Device | Ceph 블록 스토리지 |
| RGW | RADOS Gateway | Ceph S3 호환 객체 스토리지 게이트웨이 |
