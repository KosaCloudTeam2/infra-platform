# 역할 분담 및 작업 패키지

## 1. 작업 패키지 목록

| ID    | 작업 패키지         | 구현 내용                                                                      | 주 담당 | 보조   |
| :---- | :------------------ | :----------------------------------------------------------------------------- | :------ | :----- |
| WP-01 | 저장소/협업 체계    | 브랜치 전략, PR 규칙, 이슈 템플릿, 작업 보드, Prettier/pre-commit/Husky 온보딩 | 팀원 1  | 전원   |
| WP-02 | 네트워크 IaC        | VPC, Subnet, Route Table, IGW, NAT 선택, SG                                    | 팀원 2  | 팀원 1 |
| WP-03 | ALB 진입점          | ALB, Target Group, Listener, Health Check                                      | 팀원 2  | 팀원 3 |
| WP-04 | DB용 EC2 IaC 골격   | Data Private Subnet, DB EC2, SSM Role, ProxySQL/PXC SG                         | 팀원 2  | 팀원 3 |
| WP-05 | Percona Cluster     | PXC 3노드, DB 계정/권한, Single Writer 운영                                    | 팀원 3  | 팀원 2 |
| WP-06 | ProxySQL            | DB 접근 단일화, 읽기/쓰기 라우팅, backend 상태 확인                            | 팀원 3  | 팀원 4 |
| WP-07 | Ceph 백업           | XtraBackup, Ceph RGW 업로드, 체크섬/복구 절차                                  | 팀원 3  | 팀원 1 |
| WP-08 | 컨테이너 레지스트리 | ECR Repository, 이미지 태그 정책                                               | 팀원 4  | 팀원 2 |
| WP-09 | K8s/App 런타임      | Kubernetes Deployment/Service/Ingress, 앱-DB 연결                              | 팀원 4  | 팀원 3 |
| WP-10 | CI/CD / GitOps      | Docker Build, Image Push, Argo CD GitOps 배포, AWS EC2 bootstrap 버전 관리     | 팀원 4  | 팀원 1 |
| WP-11 | IAM/OIDC            | GitHub OIDC Provider, Deploy Role, 최소 권한                                   | 팀원 4  | 팀원 1 |
| WP-12 | Secret 관리         | Kubernetes Secret 또는 External Secret, AWS Secret, DB 접속 Secret 주입        | 팀원 4  | 팀원 3 |
| WP-13 | WAF/보안            | WAF Managed Rule, SG 최소 허용, DB 내부망 점검                                 | 팀원 2  | 팀원 4 |
| WP-14 | 관측성              | Prometheus/Grafana 또는 CloudWatch, Logs, Metrics, Alarm, DB/Ceph 상태 지표    | 팀원 1  | 팀원 4 |
| WP-15 | Auto Scaling        | AWS EC2 Auto Scaling Group, CloudWatch Alarm, 부하 테스트 기준                 | 팀원 2  | 팀원 1 |
| WP-16 | 장애 대응           | Pod 장애, 배포 실패, SG 오설정, DB 노드 장애 복구 시나리오                     | 팀원 1  | 전원   |
| WP-17 | 비용 최적화         | EKS 미사용, EC2 burst 최소/최대 용량, EC2 DB, 로그 보존                        | 팀원 1  | 팀원 2 |
| WP-18 | 발표/시연           | 담당 영역별 슬라이드, 시연 스크립트, 캡처, Q&A                                 | 전원    | 팀원 1 |
| WP-19 | 발표 PDF 자동화     | Marp 원본 관리, PDF 변환 스크립트, 발표 산출물 버전 관리                       | 팀원 1  | 전원   |

## 2. RACI

| 산출물                    | Responsible | Accountable | Consulted  | Informed |
| :------------------------ | :---------- | :---------- | :--------- | :------- |
| 최종 아키텍처             | 팀원 1      | 팀원 1      | 팀원 2,3,4 | 전원     |
| Terraform 네트워크        | 팀원 2      | 팀원 2      | 팀원 1     | 전원     |
| DB용 EC2 네트워크/IaC     | 팀원 2      | 팀원 2      | 팀원 3     | 전원     |
| PXC/ProxySQL/Ceph 백업    | 팀원 3      | 팀원 3      | 팀원 2,4   | 전원     |
| K8s/App 런타임            | 팀원 4      | 팀원 4      | 팀원 2,3   | 전원     |
| CI/CD / GitOps 파이프라인 | 팀원 4      | 팀원 4      | 팀원 3     | 전원     |
| 관측성/통합 검증          | 팀원 1      | 팀원 1      | 팀원 2,3,4 | 전원     |
| 보안 정책                 | 팀원 2      | 팀원 1      | 팀원 3,4   | 전원     |
| 발표 자료                 | 전원        | 전원        | 전원       | 전원     |

## 3. 구현 우선순위

1. 온프레미스 Kubernetes 첫 배포
2. GitHub Actions 이미지 빌드와 Argo CD GitOps 배포
3. DB용 EC2 내부망 구성과 ProxySQL 경유 접속
4. PXC 3노드 구성과 Ceph RGW 백업
5. CloudWatch 로그와 기본 알람
6. WAF, Secrets Manager, IAM 최소 권한
7. AWS EC2 Auto Scaling burst와 장애 복구 시연
8. 비용 최적화와 발표 자료 완성

## 4. 책임 경계

| 경계               | 담당 원칙                                                                                                       |
| :----------------- | :-------------------------------------------------------------------------------------------------------------- |
| 클라우드 범위      | Cloud/Network/IaC 담당은 AWS 전체가 아니라 VPC, ALB, SG, WAF, EC2 ASG, Launch Template, Terraform 경계를 책임짐 |
| CI/CD 범위         | CI/CD 담당은 GitHub Actions, ECR, Argo CD, Kubernetes manifest, 앱 배포와 롤백을 책임짐                         |
| DB용 EC2 생성      | Cloud/Network/IaC 담당이 Terraform 골격과 내부망 배치를 책임지고, DB 담당이 스펙과 디스크 요구사항을 제시함     |
| DB 소프트웨어 구성 | DB/Storage 담당이 PXC, ProxySQL, 백업, 복구를 책임짐                                                            |
| 앱 배포            | CI/CD/App Runtime 담당이 Argo CD 기반 Kubernetes 배포와 AWS burst 앱 환경변수/Secret 주입을 책임짐              |
| 앱-DB 연결         | CI/CD/App Runtime 담당과 DB/Storage 담당이 공동 검증함                                                          |
| DB 보안그룹        | Cloud/Network/IaC 담당과 DB/Storage 담당이 공동 리뷰함                                                          |
| 관측성             | Observability 담당이 K8s, Argo CD, ALB/EC2, DB/Ceph 상태 확인 기준과 대시보드/캡처를 통합함                     |
| 발표/시연          | 전원이 발표에 참여하고, 각 담당자가 자기 영역의 설명, 캡처, 시연, Q&A 대응을 책임짐                             |

핵심 기준: **DB 담당은 DB가 접속 가능한 상태까지 책임지고, 앱 배포 담당은 앱이 ProxySQL endpoint를
사용하도록 연결하는 것을 책임짐.**

## 5. 역할별 상세 범위

### 5.1 Observability / Integration / Demo

- 관측성 도구 선택: CloudWatch 중심 또는 Prometheus/Grafana 최소 구성
- Kubernetes pod/deployment 상태 확인
- Argo CD Application sync/health 상태 확인
- ALB 5xx, UnhealthyHost, EC2 CPU 지표 확인
- PXC/ProxySQL/Ceph 상태 확인 항목 취합
- 장애 시나리오별 판단 지표 정리
- 발표 캡처, Runbook, Q&A 통합

### 5.2 Cloud / Network / IaC

- VPC, Subnet, Route Table, IGW, NAT 선택
- ALB, Target Group, Listener, Health Check
- Security Group, WAF, 내부망 접근 경계
- EC2 Auto Scaling Group, Launch Template
- DB용 EC2 네트워크 골격, SSM 접근 경로
- Terraform 실행 절차와 비용 리소스 정리 기준

### 5.3 DB / Storage

- PXC 3노드 구성과 Single Writer 운영 기준
- ProxySQL 라우팅과 backend 상태 확인
- DB 계정/권한과 앱 접속 계정 분리
- Percona XtraBackup 수행과 복구 기준
- Ceph RGW 백업 업로드와 체크섬 확인
- DB 장애 시나리오와 복구 Runbook

### 5.4 CI/CD / App Runtime

- GitHub Actions 이미지 빌드와 ECR push
- Argo CD 설치, Application 구성, sync 검증
- Kubernetes manifest 또는 Helm chart 관리
- 앱 환경변수와 Secret 주입
- 앱-DB 연결 확인
- 배포 실패 롤백과 이전 image tag 복구
- AWS burst 앱 bootstrap 절차 지원
