# Agent Instructions

이 저장소는 4인 팀의 클라우드 인프라 구축 프로젝트를 위한 독립 Git 저장소임. Codex, ChatGPT, Gemini
등 AI 도구가 이 저장소에서 작업할 때는 이 파일을 최우선 프로젝트 지침으로 사용함.

## 프로젝트 기준

- 문서는 한국어로 작성함.
- 일정은 13일 시스템 구축 + 3일 발표 준비를 기준으로 유지함.
- MVP는 비용 우선 하이브리드 구조로 정의함. 기본 런타임은 온프레미스 Proxmox 기반 Kubernetes이며,
  AWS는 EC2 Auto Scaling Group, Launch Template, ALB 기반 burst 영역으로 사용함.
- DB는 AWS RDS를 제외하고 EC2 기반 Percona XtraDB Cluster(PXC), ProxySQL, Ceph RGW 백업을 사용함.
- EKS Hybrid Nodes, 단일 Kubernetes 클러스터 기반 AWS EC2 worker 자동 join, CloudFront, Blue/Green
  배포, Route 53/ACM HTTPS, PMM/Prometheus는 선택 확장으로 분리함.
- 운영 키는 저장소에 저장하지 않음. GitHub Actions OIDC와 AWS IAM Role을 우선 사용함.
- Day 14 이후에는 신규 기능 추가보다 발표 안정화, 캡처, Runbook 검증을 우선함.

## AI 작업 원칙

- 사용자가 명확히 분석만 요청하지 않았다면 필요한 파일을 읽고 직접 수정함.
- 기존 문서와 Terraform 구조를 먼저 확인한 뒤 변경함.
- 일정이 13+3 범위를 벗어나는 제안은 선택 확장 또는 향후 과제로 분리함.
- 보안, 비용, 발표 가능성 중 하나라도 악화되는 변경은 문서에 근거와 한계를 함께 남김.
- 사용자의 미완성 작업, untracked 파일, 수동 작성 문서를 삭제하거나 되돌리지 않음.
- 대규모 구조 변경보다 현재 역할 분담과 일정표에 맞는 작은 변경을 우선함.
- 기술 용어는 처음 등장할 때 가능한 한 한국어(English/약어) 형식으로 설명함.
- 과장 표현을 피하고 검증 가능한 표현을 사용함.

## 변경 원칙

- 일정, 역할, 구현 범위 변경 시 `docs/02_schedule_13_plus_3.md`와
  `docs/03_roles_and_work_packages.md`를 함께 갱신함.
- 인프라 구조 변경 시 `docs/01_architecture.md`와 Terraform 파일을 함께 갱신함.
- 보안 정책 변경 시 `docs/05_security_policy.md`를 갱신함.
- 발표 시나리오 변경 시 `docs/06_demo_presentation_plan.md`를 갱신함.
- 구조적 한계, 일정상 제외, 운영 주의 사항 변경 시 `docs/15_structure_review.md`를 갱신함.
- 주요 설계/구현/문서 변경 시 `docs/16_change_log.md`에 변경 이력을 남김.
- 팀원별 작업 범위나 인계 기준 변경 시 `docs/architecture/build-up/` 하위 역할별 문서를 함께 갱신함.
- DB/PXC/ProxySQL/Ceph 변경 시 `docs/runbooks/database_storage.md`를 함께 갱신함.
- CI/CD, Kubernetes, AWS EC2 Auto Scaling, GitHub Actions 변경 시 `docs/runbooks/deployment.md`와
  `.github/workflows/`를 함께 확인함.
- 민감 정보, `.tfstate`, `.env`, 개인키, 인증서 파일은 커밋하지 않음.

## 설계 고정점

- AWS burst 영역의 외부 진입점은 ALB와 WAF로 제한함.
- 온프레미스 앱은 Kubernetes Ingress/Service를 통해 노출하고, AWS burst 앱은 ALB Target Group 뒤에
  배치함.
- ProxySQL과 PXC EC2는 Data Private Subnet에 배치하고 Public IP를 부여하지 않음.
- 앱은 PXC 노드에 직접 접속하지 않고 ProxySQL endpoint로만 접속함.
- ProxySQL 1대는 MVP 기준이며 단일 장애점(SPoF)임을 문서에 명시함.
- ProxySQL 이중화가 필요하면 `proxysql_count = 2`, `enable_proxysql_internal_nlb = true`를 사용함.
- PXC는 3노드와 Single Writer 운영 기준을 우선함.
- Ceph는 주 DB 디스크가 아니라 RGW 백업 저장소, RBD, CephFS 용도로 분리해서 설명함.
- Terraform state는 MVP에서 로컬 기준이지만, 팀 apply는 담당자 1명으로 제한함. 협업 고도화 시 S3
  Backend와 DynamoDB Lock Table을 사용함.
- 기존 ECS Fargate 구조는 AWS-only fallback 또는 비교안으로만 유지함. 비용 우선 하이브리드 MVP와
  충돌하는 경우 온프레미스 Kubernetes + AWS EC2 ASG/ALB 기준을 우선함.

## 검증 기준

- Terraform 변경 후 `terraform fmt`, `terraform validate`, `terraform plan` 결과를 확인함.
- GitHub Actions 변경 후 수동 실행 또는 PR 체크 결과를 확인함.
- 문서 변경 후 링크와 표가 깨지지 않는지 확인함.
- Markdown/YAML/JSON 변경 후 가능하면 `pnpm run format:check`를 실행함.
- 전체 품질 확인은 가능하면 `uv run pre-commit run --all-files`로 수행함.
- 도구가 설치되지 않았거나 권한 문제로 검증하지 못하면 최종 답변에 명확히 남김.

## AI에게 요청할 때 권장 형식

작업을 요청할 때 아래 정보를 포함하면 결과가 일관됨.

```text
목표:
변경 범위:
건드리지 말 것:
검증 방법:
발표/문서 반영 필요 여부:
```

예시:

```text
목표: ProxySQL 2대 + Internal NLB 구성을 실제 적용 가능한 수준으로 보완
변경 범위: infra/terraform, docs/01_architecture.md, DB runbook
건드리지 말 것: app 코드, 발표 자료
검증 방법: terraform fmt/validate/plan 가능 여부 확인
발표/문서 반영 필요 여부: 한계와 시연 포인트까지 문서화
```

## 커밋/보고 원칙

- 커밋과 푸시는 사용자가 명시적으로 요청한 경우에만 수행함.
- 작업 완료 시 변경 파일, 검증 결과, 미검증 사유를 요약함.
- 필요한 경우 한국어 커밋 메시지 초안을 제안함.
