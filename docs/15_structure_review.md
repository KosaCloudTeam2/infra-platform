# Structure Review

`new_project_root` 구조 점검 결과와 보완 사항

---

## 1. 현재 구조 평가

전체적으로 13+3 일정의 실구축 프로젝트에 필요한 기본 뼈대는 갖춰져 있음.

- 문서: 일정, 역할, 아키텍처, 보안, Runbook, 발표 자료 존재
- 코드: Terraform, GitHub Actions, 샘플 앱 존재
- 운영: 배포/롤백/모니터링/DB 백업 Runbook 존재
- 품질: Prettier, pre-commit, Husky 존재

루트 `docs/` 바로 아래의 `00~17` 문서는 많아 보이지만, 현재는 프로젝트를 처음 이해하는 순서형 문서로
작동함. 따라서 MkDocs 도입 전 대규모 폴더 이동보다 `docs/index.md`와 MkDocs `nav`로 읽기 순서를
표현하는 방식을 우선함.

---

## 2. 보완한 구조

기존 프로젝트의 `docs/architecture/build-up` 구조를 새 프로젝트에 맞게 역할 기반으로 적용함.

| 신규 문서                                                | 목적                             |
| :------------------------------------------------------- | :------------------------------- |
| `docs/architecture/build-up/01_network_iac.md`           | Network/IaC 담당 상세 구현       |
| `docs/architecture/build-up/02_db_storage.md`            | DB/Storage 담당 상세 구현        |
| `docs/architecture/build-up/03_cicd_app_runtime.md`      | CI/CD/App Runtime 담당 상세 구현 |
| `docs/architecture/build-up/04_observability_demo.md`    | 관측성/시연 담당 상세 구현       |
| `docs/architecture/build-up/05_presentation_handover.md` | 발표/인계 상세 구현              |

---

## 3. 구조적 주의 사항

### 3.1 Terraform 상태 관리

현재는 로컬 state 기준임. 팀 협업에서는 S3 Backend와 DynamoDB Lock Table을 쓰는 것이 안전하지만,
13일 일정에서는 초기 복잡도를 줄이기 위해 “담당자 1명만 apply” 원칙으로 시작 가능함.

### 3.2 PXC/ProxySQL 설치 자동화

Terraform은 EC2와 네트워크 골격까지만 제공함. PXC/ProxySQL 설치는 아직 Ansible 또는 상세 스크립트로
자동화되어 있지 않음.

권장:

- Day 8까지 수동 설치 절차를 Runbook에 정리
- 시간이 남으면 Ansible Playbook으로 전환

### 3.3 ProxySQL 단일 장애점

MVP는 ProxySQL 1대임. 이는 DB 계층의 단일 장애점(SPoF)이므로 발표에서 한계로 명확히 말해야 함. 1대로
시작한 이유는 “ProxySQL 경유 접속, PXC 3노드 구성, 백업/복구, 앱 배포”를 13일 안에 안정적으로 끝내기
위한 일정상 절충임.

주의:

- ProxySQL EC2 장애 시 앱은 PXC가 살아 있어도 DB에 접속하지 못함
- ProxySQL 설정 파일과 런타임 설정이 어긋나면 재시작 후 라우팅 정책이 달라질 수 있음
- ProxySQL 2대를 만들더라도 설정 동기화, backend 상태 확인, 앱 접속 엔드포인트 단일화가 같이 필요함
- Internal NLB Health Check는 ProxySQL 프로세스가 살아 있는지만 볼 수 있으므로, 실제 PXC backend
  상태 검증은 별도 Runbook으로 확인해야 함

확장:

- ProxySQL 2대
- Internal NLB
- 또는 Keepalived 기반 VIP

즉시 보완한 내용:

- Terraform 변수 `proxysql_count` 추가
- Terraform 변수 `enable_proxysql_internal_nlb` 추가
- 기본값은 `proxysql_count = 1`, `enable_proxysql_internal_nlb = false`
- 일정 여유가 있으면 `proxysql_count = 2`, `enable_proxysql_internal_nlb = true`로 전환 가능

### 3.4 Ceph 연결 방식

Ceph RGW를 AWS 앱 또는 DB 백업 경로에서 사용하려면 네트워크 경로를 결정해야 함.

선택지:

- Site-to-Site VPN
- 제한된 IP 기반 HTTPS 공개
- 임시 시연용 수동 업로드

13일 일정에서는 “PXC 백업 산출물 → Ceph RGW 업로드 확인”을 우선함.

Proxmox를 온프레미스 플랫폼으로 사용할 경우 현재 AWS 아키텍처와 직접 충돌하지 않음. 다만 Proxmox는
VM/LXC와 Ceph 운영 계층이고, AWS ECS Fargate 앱의 런타임 또는 블록 스토리지 계층이 아님. 따라서 AWS
앱은 Proxmox/Ceph RBD를 직접 사용하지 않고 Ceph RGW의 S3 호환 API만 사용하도록 경계를 분리해야 함.

추가 주의:

- Proxmox 관리 UI를 인터넷에 공개하지 않음
- Proxmox VM 백업을 PXC 논리 백업으로 대체해서 설명하지 않음
- Ceph RGW endpoint는 VPN 또는 제한된 IP 기반 HTTPS로 보호함
- 2노드 Proxmox/Ceph 구성을 고가용성처럼 과장하지 않음

### 3.5 GitHub Actions Task Definition

`.github/task-definition.json`에는 `ACCOUNT_ID` 플레이스홀더가 있음. 실제 GitHub 저장소 생성 후
반드시 교체해야 함.

### 3.6 Argo CD MVP 편입

Argo CD를 MVP 배포 경로에 포함함. 이 결정으로 Kubernetes 배포 설명력은 높아지지만, 설치와 sync 검증
시간이 추가됨.

주의:

- Day 8까지 Application sync 성공 필요
- Day 13 이전 auto-sync 활성화 여부 결정 필요
- Argo CD admin 초기 비밀번호 저장소 커밋 금지
- AWS ECS workflow는 fallback 검증용으로 분리
- Argo CD HA 구성, SSO 연동, 고급 RBAC는 선택 확장

---

## 4. 추가 적용한 기존 프로젝트 요소

- Build-up 문서 구조
- Prettier/Husky/pre-commit 품질 자동화
- DB 내부망 보안 원칙
- Ceph RGW/RBD/CephFS 역할 분리
- Runbook 중심 운영 절차
- Marp 발표 원본 관리
- 리소스 정리 계획

---

## 5. 다음 보완 후보

| 후보                             | 우선순위 | 설명                                                                                                                          |
| :------------------------------- | :------- | :---------------------------------------------------------------------------------------------------------------------------- |
| Terraform S3 Backend             | 중       | 협업 중 state 충돌 방지                                                                                                       |
| Ansible PXC 설치 Playbook        | 중       | DB 설치 반복성 확보                                                                                                           |
| ProxySQL 2대 + Internal NLB      | 중       | Terraform 변수로 전환 가능, Day 9 이후 일정 여유 시                                                                           |
| 비용 우선 하이브리드 구조 재정렬 | 높음     | 온프레미스 Kubernetes + AWS EC2 ASG/ALB burst로 결정했으므로 기존 ECS 중심 Terraform, CI/CD, Runbook을 단계적으로 재정렬 필요 |
| Argo CD Application 구체화       | 높음     | MVP에 포함했으므로 설치 방법, Application manifest, sync 정책을 Day 8 전 확정 필요                                            |
| Ceph RGW 연결 방식 확정          | 중       | VPN 또는 제한된 IP 기반 HTTPS 중 하나를 결정해야 백업 시연 안정화                                                             |
| 실제 앱 교체 체크리스트          | 중       | 임시 앱과 실제 앱의 포트, health check, secret 조건 차이 흡수                                                                 |
| MkDocs 문서 사이트               | 낮음     | 물리적 문서 이동보다 `docs/index.md`와 `mkdocs.yml` nav 기반 도입 권장                                                        |
| PMM 또는 Prometheus              | 낮음     | DB 관측성 고도화                                                                                                              |
| S3 2차 백업 복제                 | 낮음     | DR 메시지 강화                                                                                                                |
