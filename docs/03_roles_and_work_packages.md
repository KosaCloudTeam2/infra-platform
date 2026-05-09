# 역할 분담 및 작업 패키지

## 1. 작업 패키지 목록

| ID    | 작업 패키지         | 구현 내용                                                                                                            | 주 담당 | 보조     |
| :---- | :------------------ | :------------------------------------------------------------------------------------------------------------------- | :------ | :------- |
| WP-01 | 저장소/협업 체계    | 브랜치 전략, PR 규칙, 이슈 템플릿, 작업 보드, Prettier/pre-commit/Husky 온보딩                                       | 팀원 1  | 전원     |
| WP-02 | 네트워크 IaC        | VPC, Subnet, Route Table, IGW, NAT 선택, SG                                                                          | 팀원 2  | 팀원 1   |
| WP-03 | ALB 진입점          | ALB, Target Group, Listener, Health Check                                                                            | 팀원 2  | 팀원 3   |
| WP-04 | DB용 EC2 IaC 골격   | Data Private Subnet, DB EC2, SSM Role, ProxySQL/PXC SG                                                               | 팀원 2  | 팀원 3   |
| WP-05 | Percona Cluster     | PXC 3노드, DB 계정/권한, Single Writer 운영                                                                          | 팀원 3  | 팀원 2   |
| WP-06 | ProxySQL            | DB 접근 단일화, 읽기/쓰기 라우팅, backend 상태 확인                                                                  | 팀원 3  | 팀원 4   |
| WP-07 | Ceph 백업           | XtraBackup, Ceph RGW 업로드, 체크섬/복구 절차                                                                        | 팀원 3  | 팀원 1   |
| WP-08 | 컨테이너 레지스트리 | Docker Hub Repository, 이미지 태그 정책, Private Registry 확장 검토                                                  | 팀원 4  | 팀원 2   |
| WP-09 | K8s/App 런타임      | Kubernetes Deployment/Service/Ingress, 앱 런타임 배포                                                                | 팀원 4  | 팀원 1   |
| WP-10 | CI/CD / GitOps      | Docker Build, Image Push, Argo CD GitOps 배포, manifest image tag 관리                                               | 팀원 4  | 팀원 1   |
| WP-11 | IAM/OIDC            | GitHub OIDC Provider, Deploy Role, 최소 권한 Terraform                                                               | 팀원 2  | 팀원 4   |
| WP-12 | Secret 관리         | Kubernetes Secret, GitHub Secret, DB 접속 Secret 전달 기준                                                           | 팀원 4  | 팀원 2,3 |
| WP-13 | WAF/보안            | WAF Managed Rule, SG 최소 허용, DB 내부망 점검                                                                       | 팀원 2  | 팀원 4   |
| WP-14 | 관측성              | Prometheus/Grafana 또는 CloudWatch, Logs, Metrics, Alarm, DB/Ceph 상태 지표, 웹 서버 기동/접속 검증, 앱-DB 연결 검증 | 팀원 1  | 팀원 4   |
| WP-15 | Auto Scaling        | AWS EC2 Auto Scaling Group, CloudWatch Alarm, 부하 테스트 기준                                                       | 팀원 2  | 팀원 1   |
| WP-16 | 장애 대응           | Pod 장애, 배포 실패, SG 오설정, DB 노드 장애 복구 시나리오                                                           | 팀원 1  | 전원     |
| WP-17 | 비용 최적화         | EKS 최소 PoC 비용/삭제 기준, 운영용 EKS 미전환, EC2 burst 최소/최대 용량, NAT/WAF/EC2 비용 제한, 정리 기준           | 팀원 2  | 팀원 1   |
| WP-18 | 발표/시연           | 담당 영역별 슬라이드, 시연 스크립트, 캡처, Q&A                                                                       | 전원    | 팀원 1   |
| WP-19 | 발표 PDF 자동화     | Marp 원본 관리, PDF 변환 스크립트, 발표 산출물 버전 관리                                                             | 전원    | 팀원 1   |

## 2. RACI

| 산출물                               | Responsible | Accountable | Consulted  | Informed |
| :----------------------------------- | :---------- | :---------- | :--------- | :------- |
| 최종 아키텍처                        | 팀원 1      | 팀원 1      | 팀원 2,3,4 | 전원     |
| Terraform 네트워크                   | 팀원 2      | 팀원 2      | 팀원 1     | 전원     |
| DB용 EC2 네트워크/IaC                | 팀원 2      | 팀원 2      | 팀원 3     | 전원     |
| PXC/ProxySQL/Ceph 백업               | 팀원 3      | 팀원 3      | 팀원 2,4   | 전원     |
| K8s/App 런타임                       | 팀원 4      | 팀원 4      | 팀원 2,3   | 전원     |
| 웹 서버 기동/접속 및 앱-DB 연결 검증 | 팀원 1      | 팀원 1      | 팀원 3,4   | 전원     |
| CI/CD / GitOps 파이프라인            | 팀원 4      | 팀원 4      | 팀원 3     | 전원     |
| GitHub OIDC / IAM Role               | 팀원 2      | 팀원 2      | 팀원 4     | 전원     |
| 관측성/통합 검증                     | 팀원 1      | 팀원 1      | 팀원 2,3,4 | 전원     |
| 보안 정책                            | 팀원 2      | 팀원 2      | 팀원 1,3,4 | 전원     |
| 발표 자료                            | 전원        | 전원        | 전원       | 전원     |

## 3. 구현 우선순위

1. 온프레미스 Kubernetes 첫 배포
2. GitHub Actions 이미지 빌드와 Argo CD GitOps 배포
3. DB용 EC2 내부망 구성과 ProxySQL 경유 접속
4. PXC 3노드 구성과 Ceph RGW 백업
5. CloudWatch 기본 알람과 Target Health 확인
6. WAF, Kubernetes/GitHub Secret, IAM 최소 권한
7. AWS EC2 Auto Scaling burst와 장애 복구 시연
8. 비용 최적화와 발표 자료 완성

## 4. 책임 경계

| 경계                | 담당 원칙                                                                                                                                                                                                                       |
| :------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 클라우드 범위       | Cloud/Network/IaC 담당은 AWS 전체가 아니라 VPC, ALB, SG, WAF, EC2 ASG, Launch Template, Terraform 경계를 책임함. 여기서 Network는 클라우드 네트워크(AWS VPC/서브넷/라우팅/SG)만 의미하며, EKS는 최소 PoC와 삭제 검증까지만 다룸 |
| CI/CD 범위          | CI/CD 담당은 GitHub Actions, Docker Hub, Argo CD, Kubernetes manifest, 앱 배포와 롤백을 책임짐                                                                                                                                  |
| DB용 EC2 생성       | Cloud/Network/IaC 담당이 Terraform 골격과 내부망 배치를 책임지고, DB 담당이 스펙과 디스크 요구사항을 제시함                                                                                                                     |
| DB 소프트웨어 구성  | DB/Storage 담당이 PXC, ProxySQL, 백업, 복구를 책임짐                                                                                                                                                                            |
| 온프레미스 네트워크 | DB/Storage 담당이 DB 관련 온프레미스 네트워크(pfSense/VLAN/라우팅/방화벽) 기준을 책임지고, 클라우드 네트워크와 접점은 Cloud/Network/IaC 담당과 공동 검토함                                                                      |
| 앱 배포             | CI/CD/App Runtime 담당이 Argo CD 기반 Kubernetes 배포와 앱 환경변수/Secret 연결을 책임지고, AWS burst bootstrap은 Cloud/IaC 담당과 공동 검증함                                                                                  |
| 앱-DB 연결          | Observability/Integration/Demo 담당이 웹 서버 기동 확인과 함께 검증을 주관하고, CI/CD/App Runtime 담당과 DB/Storage 담당이 설정/접속 정보를 지원함                                                                              |
| DB 보안그룹         | Cloud/Network/IaC 담당과 DB/Storage 담당이 공동 리뷰함                                                                                                                                                                          |
| 관측성              | Observability 담당이 K8s, Argo CD, ALB/EC2, DB/Ceph 상태 확인 기준과 대시보드/캡처를 통합함                                                                                                                                     |
| 발표/시연           | 전원이 발표에 참여하고, 각 담당자가 자기 영역의 설명, 캡처, 시연, Q&A 대응을 책임짐                                                                                                                                             |

핵심 기준: **DB 담당은 DB가 접속 가능한 상태까지 책임지고, Observability/Integration/Demo 담당은 웹
서버 기동/접속 확인과 앱-DB 연결 검증을 책임짐. CI/CD/App Runtime 담당은 배포와 Secret/환경변수
설정을 지원함.**

부하 분산 기준:

- 팀원 1은 통합 기준, 관측 지표, 캡처 품질과 웹 서버 기동/접속 및 앱-DB 연결 검증을 책임지되 각
  영역의 발표 자료 원본까지 혼자 작성하지 않음
- 팀원 2는 AWS 비용, 보안그룹, WAF, IAM/OIDC, ASG/Launch Template까지 책임져 Cloud/IaC 경계를 명확히
  함
- 팀원 3은 PXC/ProxySQL/Ceph 백업, DB 관련 온프레미스 네트워크, DB 장애 시연을 책임지고 앱 manifest
  수정까지 떠안지 않음
- 팀원 4는 Docker Hub, GitHub Actions, Argo CD, K8s 배포, 앱 Secret/환경변수 설정을 책임지되 AWS IAM
  Terraform은 팀원 2와 공동 검증함
- 발표와 시연은 전원이 자기 영역 캡처, 설명, Q&A를 준비하고 팀원 1은 순서와 톤을 통합함

## 5. 역할별 상세 범위

### 5.1 Observability / Integration / Demo

- 관측성 도구 선택: CloudWatch 중심 또는 Prometheus/Grafana 최소 구성
- Kubernetes pod/deployment 상태 확인
- 웹 서버 기동 확인과 Ingress/ALB 접속 검증
- Argo CD Application sync/health 판단 기준과 캡처 취합
- ALB 5xx, UnhealthyHost, EC2 CPU 지표 확인
- PXC/ProxySQL/Ceph 상태 확인 항목 취합
- 앱-DB 연결 검증(ProxySQL endpoint 기준) 주관
- 장애 시나리오별 판단 지표 정리
- 발표 캡처, Runbook, Q&A 통합

### 5.2 Cloud / Network / IaC

- AWS 클라우드 네트워크(VPC, Subnet, Route Table, IGW, NAT) 설계/구성
- ALB, Target Group, Listener, Health Check
- Security Group, WAF, 내부망 접근 경계
- EC2 Auto Scaling Group, Launch Template, user data bootstrap
- GitHub Actions OIDC Provider와 AWS Deploy Role
- NAT Gateway, ALB, WAF, EC2, DB EC2 비용 제한과 정리 기준
- DB용 EC2 네트워크 골격, SSM 접근 경로
- Terraform 실행 절차와 비용 리소스 정리 기준

### 5.3 DB / Storage

- DB 관련 온프레미스 네트워크(pfSense/VLAN/라우팅/방화벽) 기준 수립
- PXC 3노드 구성과 Single Writer 운영 기준
- ProxySQL 라우팅과 backend 상태 확인
- DB 계정/권한과 앱 접속 계정 분리
- Percona XtraBackup 수행과 복구 기준
- Ceph RGW 백업 업로드와 체크섬 확인
- DB 장애 시나리오와 복구 Runbook

### 5.4 CI/CD / App Runtime

- GitHub Actions 이미지 빌드와 Docker Hub push
- Argo CD 설치, Application 구성, sync 검증
- Kubernetes manifest 또는 Helm chart 관리
- 앱 환경변수와 Kubernetes Secret 주입
- 앱-DB 연결에 필요한 환경변수/Secret 설정 지원
- 배포 실패 롤백과 이전 image tag 복구
- AWS burst 앱 bootstrap 절차 지원
