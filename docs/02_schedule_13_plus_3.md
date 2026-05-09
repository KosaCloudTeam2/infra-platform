# 13일 구축 + 3일 발표 상세 일정

> 문서 전환 메모: 아키텍처 상세 조회는 `docs/architecture/details/*`와 역할별 Build-up 문서를 함께
> 사용함.

## 1. 일정 요약

- **Day 1-2:** 요구사항 확정, 저장소/계정/권한 준비, 아키텍처 확정
- **Day 3-5:** 네트워크, IaC, 컨테이너, CI/CD 기반 구축
- **Day 6-9:** 온프레미스 Kubernetes 배포, AWS EC2 burst, 보안, 데이터 계층, Ceph 백업, 관측성 구현
- **Day 10-13:** 통합 테스트, 장애 시나리오, 비용/성능 정리, 구축 마감
- **Day 14:** 14일 내 발표 가능 상태 고정, 신규 기능 추가 중단, 캡처와 Runbook 검증
- **Day 15-16:** 시간이 남을 때만 발표 자료 다듬기, 시연 영상/스크립트, 리허설

## 2. 팀 역할

| 역할                                  | 담당자 | 핵심 책임                                                                                         |
| :------------------------------------ | :----- | :------------------------------------------------------------------------------------------------ |
| A. Observability / Integration / Demo | 팀원 1 | 관측성 판단 기준, 통합 검증, 장애 시나리오, Runbook 품질, 발표 흐름과 캡처 통합                   |
| B. Cloud / Network / IaC Engineer     | 팀원 2 | VPC, Subnet, ALB, SG, WAF, EC2 ASG, Launch Template, IAM/OIDC, 비용 제한, DB용 EC2 Terraform 골격 |
| C. DB / Storage Engineer              | 팀원 3 | Percona Cluster, ProxySQL, DB 계정/권한, XtraBackup, Ceph 백업                                    |
| D. CI/CD / App Runtime Engineer       | 팀원 4 | GitHub Actions, Argo CD, Docker Hub, K8s manifest, 앱 배포, 앱-DB 연결, 롤백                      |

역할 경계:

- Cloud 담당은 AWS 전체가 아니라 네트워크, IaC, AWS burst 인프라를 책임짐
- CI/CD 담당은 이미지 빌드, GitOps 배포, 앱 런타임 연결을 책임짐
- DB 담당은 DB 클러스터, DB 접근 경로, 백업/복구를 책임짐
- Observability 담당은 Prometheus/Grafana 또는 CloudWatch 기준 관측성, 통합 검증, 발표 흐름 품질을
  책임짐
- 발표와 시연은 전원이 참여하고, 각자 담당 영역의 설명, 캡처, Q&A 대응을 책임짐
- 아키텍처 결정과 일정 조율은 전원 참여, 최종 문서 형식과 흐름은 Observability / Integration 담당이
  통합함
- 각 담당자는 자기 영역의 발표 설명, 캡처, Q&A, Runbook 원본을 직접 준비함

## 3. 일자별 세부 계획

| 일자   | 공통 목표                   | 팀원 1: Observability/Integration                                 | 팀원 2: Cloud/Network/IaC                                          | 팀원 3: DB/Storage                                                          | 팀원 4: CI/CD/App Runtime                                                  |
| :----- | :-------------------------- | :---------------------------------------------------------------- | :----------------------------------------------------------------- | :-------------------------------------------------------------------------- | :------------------------------------------------------------------------- |
| Day 1  | 프로젝트 킥오프             | 목표/제외 범위 확정, Definition of Done 작성, 환경 구축 완료 확인 | AWS 리전, CIDR, Subnet 계획 초안                                   | PXC/ProxySQL/Ceph 요구사항과 포트 목록 확정                                 | GitHub Repository 설정, 브랜치/PR 규칙 초안, Prettier/pre-commit 동작 확인 |
| Day 2  | 설계 확정                   | 아키텍처 다이어그램 확정, 역할별 작업 보드 구성                   | Terraform Backend/Provider 구조 작성, App/Data Subnet 분리 설계    | DB EC2 사양, 디스크, 백업 저장소 요구사항 제시                              | OIDC 배포 방식 설계, 앱 포트/헬스체크 경로 확인                            |
| Day 3  | 네트워크 골격               | 설계 리뷰 및 리스크 점검                                          | VPC, Public/App Private/Data Private Subnet, IGW, Route Table 구현 | PXC 설치 절차와 ProxySQL 라우팅 초안 작성                                   | GitHub Actions 기본 workflow 작성                                          |
| Day 4  | 외부 진입점                 | ALB/SG 설계 리뷰                                                  | AWS burst ALB, Target Group, Listener, EC2 SG 구현                 | DB 계정/권한 모델, PXC 노드 구성 계획 확정                                  | Docker build/push job 작성, 이미지 태그 전략 수립                          |
| Day 5  | 첫 배포 준비                | MVP 범위 재점검, 일정 조정                                        | DB용 EC2 Terraform 골격, ProxySQL/PXC SG, SSM Role 구성            | PXC/ProxySQL 설치 준비, Ceph RGW 접근 방식 확정                             | Docker Hub push 권한, GitHub Actions Secret 검증                           |
| Day 6  | 첫 배포 성공                | 첫 배포 체크리스트 운영                                           | ALB Health Check 경로와 SG 수정                                    | DB EC2 접속 경로(SSM/Bastion) 검증                                          | 온프레미스 K8s 첫 배포, GitHub Actions 이미지 빌드, Argo CD 설치 착수      |
| Day 7  | 보안 기본선                 | 보안 리뷰 회의 진행                                               | Private 라우팅, NAT 비용 선택안, IAM/OIDC, DB 내부망 접근 확인     | PXC 3노드 구성 착수, ProxySQL 접속 정보 분리                                | Kubernetes Secret, 앱 환경변수/Secret 연결                                 |
| Day 8  | 데이터 계층                 | DB/Ceph 시연 범위 확정                                            | DB Subnet/SG 규칙 검토, 0.0.0.0/0 DB 포트 차단 확인                | PXC 3노드, ProxySQL 1대 MVP 구성 완료 목표                                  | Argo CD Application 구성/sync, 앱에서 ProxySQL endpoint 접속 테스트        |
| Day 9  | 관측성/백업                 | Argo CD/K8s/ALB/DB/Ceph 판단 지표 확정                            | ALB 4xx/5xx Metric, EC2 ASG CPU Alarm 확인                         | Percona XtraBackup → Ceph RGW 업로드 테스트, ProxySQL 이중화 적용 여부 결정 | Docker Hub 이미지, K8s rollout, AWS burst app 이미지 기준 확인             |
| Day 10 | Auto Scaling/복구           | 부하 시나리오 정의                                                | AWS EC2 Auto Scaling, Launch Template, ALB Target Health 확인      | PXC 노드 장애, ProxySQL backend 제외 시나리오 검토                          | 앱 배포 실패/롤백, ASG instance refresh 절차 공동 검증                     |
| Day 11 | 롤백/복구                   | 장애 시나리오 표준화                                              | 네트워크 차단/SG 오설정 복구 절차 작성                             | DB 장애/백업 복구 시연 절차 작성                                            | Pod 장애/헬스체크 실패/배포 실패 롤백 runbook 작성                         |
| Day 12 | 통합 테스트                 | 전체 시연 흐름 1차 리허설                                         | Terraform 재현성 검증                                              | DB 백업, Ceph 업로드, ProxySQL 경유 접속 검증                               | GitHub Actions/Argo CD 재실행과 실패 케이스, 앱-DB 연결 검증               |
| Day 13 | 비용/성능 정리 및 구축 마감 | 최종 산출물 점검, 발표 핵심 메시지 작성, 누락 항목 결정           | ALB, EC2 burst, EC2 DB 비용 추정 정리, IaC README 정리             | EC2 DB, ProxySQL, Ceph 운영 기준과 명령 정리                                | WAF/CloudWatch/CI/CD 비용과 보안 효과 정리, 로그 캡처 정리                 |
| Day 14 | 발표 가능 상태 고정         | 발표 목차, 스토리라인, 시연 순서 고정                             | 네트워크/IAM/비용 캡처 고정                                        | DB/Storage 캡처 고정                                                        | CI/CD/App Runtime 캡처 고정                                                |
| Day 15 | 시연 자료 준비              | 발표 스크립트 통합                                                | Terraform plan/apply, SG 캡처 보강                                 | PXC/ProxySQL/Ceph 백업 캡처 보강                                            | GitHub Actions, K8s 배포, AWS EC2 Auto Scaling, CloudWatch 캡처 보강       |
| Day 16 | 최종 리허설                 | 시간 측정, 질의응답 준비                                          | 네트워크/보안그룹/비용 질문 대응 준비                              | DB 클러스터/Ceph 질문 대응 준비                                             | CI/CD/K8s/EC2 burst 장애 대응 질문 준비                                    |

## 4. 역할별 산출물

### 팀원 1: Observability / Integration / Demo

- Prometheus/Grafana 또는 CloudWatch 기준 관측성 구성
- Argo CD sync/health 판단 기준, Kubernetes rollout, ALB/EC2 지표 확인
- PXC/ProxySQL/Ceph 상태 확인 항목 취합
- K8s/ALB/EC2 burst/DB/Ceph 장애 시나리오 통합
- Runbook 품질 점검
- 발표 목차, 시연 흐름, 공통 캡처 품질, Q&A 통합
- `docs/01_architecture.md`와 설계 의사결정 기록 최종 정리

### 팀원 2: Cloud / Network / IaC

- VPC/Subnet/Route Table/IGW/ALB/Security Group Terraform 코드
- WAF, EC2 Auto Scaling Group, Launch Template Terraform 코드
- GitHub Actions OIDC Provider와 AWS Deploy Role Terraform 코드
- App Private Subnet과 Data Private Subnet 분리
- DB용 EC2 Terraform 골격, IAM Role, SSM 접근 경로
- ProxySQL/PXC Security Group 내부망 접근 정책
- Terraform 변수 파일과 실행 절차
- 네트워크 장애 복구 runbook
- 상세 구현 가이드: [Cloud / Network / IaC Build-up](./architecture/build-up/01_network_iac.md)

### 팀원 3: DB / Storage

- DB용 EC2 사양, 디스크, 패키지 요구사항 정의
- Percona XtraDB Cluster 3노드 구성
- ProxySQL 기반 DB 접근 단일화
- DB 계정/권한, Single Writer 운영 기준
- Percona XtraBackup과 Ceph RGW 백업 검증
- 상세 구현 가이드: [DB / Storage Build-up](./architecture/build-up/02_db_storage.md)

### 팀원 4: CI/CD / App Runtime

- Docker Hub 또는 팀 표준 이미지 레지스트리 구성
- Argo CD 설치와 Application 구성
- Kubernetes manifest 또는 Helm chart 배포 절차
- AWS EC2 Launch Template 앱 bootstrap 절차 정의 지원
- Docker 이미지 실행 조건 정리
- AWS EC2 Auto Scaling 정책은 Cloud/Network/IaC 담당과 공동 검증
- Kubernetes/EC2 burst 장애 복구 runbook
- GitHub Actions workflow
- Docker Hub 이미지 workflow
- 앱 환경변수와 Kubernetes Secret 연동
- 앱에서 ProxySQL endpoint 접속 확인
- 배포 실패 롤백 runbook
- 상세 구현 가이드: [CI/CD / App Runtime Build-up](./architecture/build-up/03_cicd_app_runtime.md)

## 5. 매일 운영 규칙

- 매일 시작 15분: 어제 완료, 오늘 목표, 막힌 점 공유
- 매일 종료 20분: 산출물 링크, 스크린샷, 미완료 항목 기록
- Day 1 종료 전 전원 `pnpm install`, `uv sync`, `pnpm run format:check`,
  `uv run pre-commit run --all-files` 확인
- Day 5, Day 9, Day 13: 통합 검수 회의
- Day 14부터는 신규 기능 추가 금지, 발표 안정화만 수행
- EKS 최소 PoC는 메인 운영 MVP를 흔들지 않는 범위에서 Day 13 전까지 클러스터 생성, 샘플 앱 배포,
  삭제 검증만 수행하며, Day 14 이후에는 신규 EKS 구축을 시작하지 않음
