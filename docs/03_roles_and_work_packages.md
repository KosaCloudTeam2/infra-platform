# 역할 분담 및 작업 패키지

## 1. 작업 패키지 목록

| ID    | 작업 패키지          | 구현 내용                                                                                                                   | 주 담당 | 보조     |
| :---- | :------------------- | :-------------------------------------------------------------------------------------------------------------------------- | :------ | :------- |
| WP-01 | 저장소/협업 체계     | 브랜치 전략, PR 규칙, 이슈 템플릿, 작업 보드, Prettier/pre-commit/Husky 온보딩                                              | 팀원 1  | 전원     |
| WP-02 | 네트워크 IaC         | VPC, Subnet, Route Table, IGW, NAT 선택, SG                                                                                 | 팀원 2  | 팀원 1   |
| WP-03 | ALB 진입점           | ALB, Target Group, Listener, Health Check                                                                                   | 팀원 2  | 팀원 3   |
| WP-04 | DB용 Proxmox VM 골격 | Proxmox VM 템플릿, Ceph RBD 풀, DB VM 네트워크/방화벽 기준                                                                  | 팀원 3  | 팀원 2   |
| WP-05 | Percona Cluster      | PXC 3노드, DB 계정/권한, Single Writer 운영                                                                                 | 팀원 3  | 팀원 2   |
| WP-06 | ProxySQL             | DB 접근 단일화, 읽기/쓰기 라우팅, backend 상태 확인                                                                         | 팀원 3  | 팀원 4   |
| WP-07 | Ceph 백업            | XtraBackup, Ceph RGW 업로드, 체크섬/복구 절차                                                                               | 팀원 3  | 팀원 1   |
| WP-08 | 컨테이너 레지스트리  | Docker Hub Repository, 이미지 태그 정책, Private Registry 확장 검토                                                         | 팀원 4  | 팀원 2   |
| WP-09 | K8s/App 런타임       | Kubernetes Deployment/Service/Ingress, 앱 런타임 배포                                                                       | 팀원 4  | 팀원 1   |
| WP-10 | CI/CD / GitOps       | Docker Build, Image Push, Argo CD GitOps 배포, manifest image tag 관리                                                      | 팀원 4  | 팀원 1   |
| WP-11 | IAM/OIDC             | GitHub OIDC Provider, Deploy Role, 최소 권한 Terraform                                                                      | 팀원 2  | 팀원 4   |
| WP-12 | Secret 관리          | Kubernetes Secret, GitHub Secret, DB 접속 Secret 전달 기준                                                                  | 팀원 4  | 팀원 2,3 |
| WP-13 | WAF/보안             | WAF Managed Rule, SG 최소 허용, DB 내부망 점검                                                                              | 팀원 2  | 팀원 4   |
| WP-14 | 관측성               | Prometheus/Grafana 또는 CloudWatch, Logs, Metrics, Alarm, DB/Ceph 상태 지표, 웹 서버 기동/접속 검증, 앱-DB 연결 검증        | 팀원 1  | 팀원 4   |
| WP-15 | Auto Scaling         | AWS EC2 Auto Scaling Group, CloudWatch Alarm, 부하 테스트 기준                                                              | 팀원 2  | 팀원 1   |
| WP-16 | 장애 대응            | Pod 장애, 배포 실패, SG 오설정, DB 노드 장애 복구 시나리오                                                                  | 팀원 1  | 전원     |
| WP-17 | 비용 최적화          | EKS 최소 PoC 비용/삭제 기준(주 담당: 팀원 2), 운영용 EKS 미전환, EC2 burst 최소/최대 용량, NAT/WAF/EC2 비용 제한, 정리 기준 | 팀원 2  | 팀원 1   |
| WP-18 | 발표/시연            | 담당 영역별 슬라이드, 시연 스크립트, 캡처, Q&A                                                                              | 전원    | 팀원 1   |
| WP-19 | 발표 PDF 자동화      | Marp 원본 관리, PDF 변환 스크립트, 발표 산출물 버전 관리                                                                    | 전원    | 팀원 1   |

## 2. RACI

| 산출물                               | Responsible | Accountable | Consulted  | Informed |
| :----------------------------------- | :---------- | :---------- | :--------- | :------- |
| 최종 아키텍처                        | 팀원 1      | 팀원 1      | 팀원 2,3,4 | 전원     |
| Terraform 네트워크                   | 팀원 2      | 팀원 2      | 팀원 1     | 전원     |
| DB용 Proxmox VM/RBD 배치             | 팀원 3      | 팀원 3      | 팀원 2     | 전원     |
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
3. DB용 Proxmox VM/Ceph RBD 구성과 ProxySQL 경유 접속
4. PXC 3노드 구성과 Ceph RGW 백업
5. CloudWatch 기본 알람과 Target Health 확인
6. WAF, Kubernetes/GitHub Secret, IAM 최소 권한
7. AWS EC2 Auto Scaling burst와 장애 복구 시연
8. 비용 최적화와 발표 자료 완성

## 4. 책임 경계

| 경계                 | 담당 원칙                                                                                                                                                                                                                       |
| :------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 클라우드 범위        | Cloud/Network/IaC 담당은 AWS 전체가 아니라 VPC, ALB, SG, WAF, EC2 ASG, Launch Template, Terraform 경계를 책임함. 여기서 Network는 클라우드 네트워크(AWS VPC/서브넷/라우팅/SG)만 의미하며, EKS는 최소 PoC와 삭제 검증까지만 다룸 |
| CI/CD 범위           | CI/CD 담당은 GitHub Actions, Docker Hub, Argo CD, Kubernetes manifest, 앱 배포와 롤백을 책임지고 Argo CD sync 운영 기준은 수동으로 고정함                                                                                       |
| DB용 Proxmox VM 생성 | DB/Storage 담당이 Proxmox VM, Ceph RBD, 온프레미스 네트워크 기준을 책임지고, Cloud/Network/IaC 담당이 AWS 연동 경계를 공동 검토함                                                                                               |
| DB 소프트웨어 구성   | DB/Storage 담당이 PXC, ProxySQL, 백업, 복구를 책임짐                                                                                                                                                                            |
| 온프레미스 네트워크  | DB/Storage 담당이 DB 관련 온프레미스 네트워크(pfSense/VLAN/라우팅/방화벽) 기준을 책임지고, 클라우드 네트워크와 접점은 Cloud/Network/IaC 담당과 공동 검토함                                                                      |
| 앱 배포              | CI/CD/App Runtime 담당이 Argo CD 기반 Kubernetes 배포와 앱 환경변수/Secret 연결을 책임지고, AWS burst bootstrap은 Cloud/IaC 담당과 공동 검증함                                                                                  |
| 앱-DB 연결           | Observability/Integration/Demo 담당이 웹 서버 기동 확인과 함께 검증을 주관하고, CI/CD/App Runtime 담당과 DB/Storage 담당이 설정/접속 정보를 지원함                                                                              |
| DB 보안그룹          | Cloud/Network/IaC 담당과 DB/Storage 담당이 공동 리뷰함                                                                                                                                                                          |
| 관측성               | Observability 담당이 K8s, Argo CD, ALB/EC2, DB/Ceph 상태 확인 기준과 대시보드/캡처를 통합함                                                                                                                                     |
| 발표/시연            | 전원이 발표에 참여하고, 각 담당자가 자기 영역의 설명, 캡처, 시연, Q&A 대응을 책임짐                                                                                                                                             |

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
- EKS 최소 PoC(클러스터 생성/샘플 앱 배포/삭제 검증) 주 담당
- NAT Gateway, ALB, WAF, EC2 burst 비용 제한과 정리 기준
- AWS burst와 온프레 DB 경계(접속 정책/라우팅) 점검
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
- Argo CD 설치, Application 구성, 수동 sync 기준 검증
- Kubernetes manifest 또는 Helm chart 관리
- 앱 환경변수와 Kubernetes Secret 주입
- 앱-DB 연결에 필요한 환경변수/Secret 설정 지원
- 배포 실패 롤백과 이전 image tag 복구
- AWS burst 앱 bootstrap 절차 지원

## 6. 2차 개편 실행형 WBS (docs/03 확장)

아래 WBS는 기존 WP-01~19를 유지한 상태에서 실행 단위로 분해한 계획임. 실제 구현/문서 반영은 각
단위의 완료 기준과 검증을 만족해야 완료로 인정함.

> 순차/독립 작업표와 상세 진행 방법은 [WBS Execution Mapping](./25_wbs_execution_mapping.md)을
> 기준으로 따름.

| WBS ID   | 연계 WP           | 목적                             | 주 담당(보조)       | 선행조건              | 주요 작업                                                                            | 완료 기준(DoD)                              | 검증                               |
| :------- | :---------------- | :------------------------------- | :------------------ | :-------------------- | :----------------------------------------------------------------------------------- | :------------------------------------------ | :--------------------------------- |
| WBS-2-01 | WP-01,18          | 2차 개편 기준선 고정             | 팀원 1 (전원)       | 본 문서/일정표 최신화 | 필독/심화 경계, 역할 단일 소스(docs/03), 변경 범위 합의                              | 기준선 합의 내용이 문서화됨                 | `uv run mkdocs build` 전 수동 리뷰 |
| WBS-2-02 | WP-02,03,04,11,13 | 클라우드/IaC 실행 게이트 확정    | 팀원 2 (팀원 1,3,4) | WBS-2-01              | NAT/HTTPS 범위, IAM/OIDC 검증 순서, 포트/VLAN/라우팅 기준 고정                       | 클라우드/IaC 선행조건이 추적 가능하게 고정  | runbook/문서 교차 점검             |
| WBS-2-03 | WP-05,06,07       | DB/Storage 실행 단위 고정        | 팀원 3 (팀원 2,1)   | WBS-2-02              | PXC/ProxySQL/Ceph 작업을 단계화, ProxySQL 2대+Internal NLB는 선택 확장으로 별도 분리 | MVP(ProxySQL 1대)와 선택 확장 경계가 명확함 | DB Runbook 교차 점검               |
| WBS-2-04 | WP-08,09,10,12    | CI/CD/App Runtime 실행 단위 고정 | 팀원 4 (팀원 1,2)   | WBS-2-02              | Docker/Argo/K8s 배포 작업 세분화, Argo CD 수동 sync 운영 기준 고정                   | 배포 단계와 롤백 단계가 분리되어 추적 가능  | 배포 Runbook 점검                  |
| WBS-2-05 | WP-14,16          | 통합 검증/장애 대응 WBS 고정     | 팀원 1 (전원)       | WBS-2-03, WBS-2-04    | 웹 서버 기동/접속, 앱-DB 연결, 장애 시나리오 검증 단위 정의                          | 통합 검증 체크리스트 완성                   | 시연 리허설 체크리스트 점검        |
| WBS-2-06 | WP-17             | 비용/확장 경계 재확인            | 팀원 2 (팀원 1)     | WBS-2-02, WBS-2-03    | EKS PoC 비용/삭제, ProxySQL HA 선택 확장, AWS 비용 상한 확인                         | MVP/선택 확장 혼선 없음                     | 비용 점검표 업데이트               |
| WBS-2-07 | WP-18,19          | 발표/산출물 동기화               | 전원 (팀원 1)       | WBS-2-05, WBS-2-06    | 역할별 캡처·Q&A·PDF 자동화 반영 단위 정의                                            | Day14 이후 안정화 중심 운영 가능            | 발표 리허설 점검                   |
| WBS-2-08 | 전 WP 공통        | 문서 정합/이력/검증 완료         | 팀원 1 (전원)       | WBS-2-01~07           | `docs/02`·`docs/03`·`docs/24`·runbook 동시 정합, change log 기록                     | 문서 충돌 없이 최종 상태 확정               | `uv run mkdocs build` 통과         |

### 6.1 단계별 게이트

1. **Gate A (기준선):** WBS-2-01 완료
2. **Gate B (클라우드/DB 게이트):** WBS-2-02, WBS-2-03 완료
3. **Gate C (배포/통합 게이트):** WBS-2-04, WBS-2-05 완료
4. **Gate D (비용/발표 게이트):** WBS-2-06, WBS-2-07 완료
5. **Gate E (문서 게이트):** WBS-2-08 및 `uv run mkdocs build` 통과

### 6.2 비범위 (이번 WBS)

- 운영용 EKS 전환
- EKS Hybrid Nodes
- ProxySQL 2대+Internal NLB 필수화
- Argo CD auto-sync 운영 전환

## 6.3 하위 작업 분해표 (세부 실행 단위)

| Parent WBS | Task ID | 작업                                | 선행           | 산출물/완료 기준                    |
| :--------- | :------ | :---------------------------------- | :------------- | :---------------------------------- |
| WBS-2-02   | T-02-1  | 포트/VLAN/라우팅 정책 확정          | WBS-2-01       | 온프레 runbook 정책표 확정          |
| WBS-2-02   | T-02-2  | IAM/OIDC 실행 순서 확정             | T-02-1         | 배포 권한 흐름 문서화               |
| WBS-2-03   | T-03-1  | PXC 상태 점검/기준값 고정           | WBS-2-02       | 상태 확인 명령/판단 기준 표         |
| WBS-2-03   | T-03-2  | ProxySQL 경유 접속 경계 확정        | T-03-1         | 앱->ProxySQL 단일 경로 기준 문서화  |
| WBS-2-03   | T-03-3  | 백업(XtraBackup->RGW) 절차 고정     | T-03-2         | 백업/복구 절차 체크리스트           |
| WBS-2-04   | T-04-1  | 이미지 빌드/태그 규칙 고정          | WBS-2-02       | 배포 태그 규칙 표                   |
| WBS-2-04   | T-04-2  | Argo CD 수동 sync/롤백 경로 고정    | T-04-1         | 배포/롤백 단계 문서화               |
| WBS-2-05   | T-05-1  | 앱-DB 연결 통합 검증                | T-03-2, T-04-2 | 통합 체크리스트                     |
| WBS-2-05   | T-05-2  | 장애 시나리오(배포실패/DB장애) 점검 | T-05-1         | 장애 대응 시나리오 표               |
| WBS-2-06   | T-06-1  | 비용 상한/확장 경계 표 업데이트     | WBS-2-05       | MVP/선택확장 경계표                 |
| WBS-2-07   | T-07-1  | 발표 캡처/스크립트 동기화           | WBS-2-06       | 역할별 발표 산출물 체크리스트       |
| WBS-2-08   | T-08-1  | 문서 최종 정합 및 변경이력 마감     | WBS-2-01~07    | 문서 충돌 없음 + 변경이력 반영 완료 |

## 6.4 독립 트랙: EKS 최소 PoC

EKS 최소 PoC는 운영 MVP의 크리티컬 패스와 분리된 독립 트랙으로 관리함.

| Track ID | 목적                             | 선행조건 | 완료 기준                           |
| :------- | :------------------------------- | :------- | :---------------------------------- |
| EKS-I-01 | 클러스터 생성/접속 흐름 점검     | WBS-2-02 | 클러스터 생성 + `kubectl` 연결 확인 |
| EKS-I-02 | 샘플 앱 배포/기본 확인           | EKS-I-01 | 샘플 배포 + 기본 응답 확인          |
| EKS-I-03 | 삭제 검증 및 비용 정리 기준 반영 | EKS-I-02 | 삭제 완료 + 비용/정리 기준 문서화   |

독립 트랙 원칙:

- 운영 MVP(온프레 K8s + AWS EC2 burst) 일정/안정화를 저해하지 않음.
- Day 14 이후에는 신규 EKS 구축을 시작하지 않고 결과 정리만 수행함.
