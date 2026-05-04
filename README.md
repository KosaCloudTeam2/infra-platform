# Cloud Infra Deployment Platform

13일 시스템 구축 + 3일 시연 포함 발표 준비를 목표로 하는 4인 팀 클라우드 인프라 프로젝트 저장소

## 1. 프로젝트 목표

기존에 준비된 간단한 애플리케이션을 대상으로 클라우드 기반 배포 플랫폼을 구축함.

- AWS 기반 네트워크, 컴퓨팅, 배포, 보안, 관측성 체계 구성
- GitHub Actions와 OpenID Connect(OIDC)를 이용한 키 없는 이미지 빌드 자동화
- Argo CD 기반 GitOps 배포로 Kubernetes manifest 동기화
- 애플리케이션 로드 밸런서(Application Load Balancer, ALB), Elastic Container Service(ECS) Fargate,
  Elastic Container Registry(ECR)를 이용한 컨테이너 배포
- CloudWatch, 웹 방화벽(Web Application Firewall, WAF), Secrets Manager 기반 운영 가드레일 구성
- 장애 상황과 롤백 시나리오를 포함한 발표 데모 준비

현재 `app/` 디렉터리의 애플리케이션은 인프라 배포 파이프라인 검증을 위한 임시 샘플 앱임. 실제 서비스
앱이 준비되면 Dockerfile, 컨테이너 포트, Health Check 경로, GitHub Actions build 경로를 맞춰 교체할
수 있음.

## 2. 권장 MVP 범위

| 영역        | 구현 내용                                                                          | 담당 문서                                                             |
| :---------- | :--------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| 네트워크    | 가상 사설 클라우드(VPC), Public/Private Subnet, IGW, NAT 선택 기준, Security Group | [Architecture](docs/01_architecture.md)                               |
| 컴퓨팅      | 온프레미스 Kubernetes, AWS EC2 burst, ALB Target Group                             | [Implementation Scope](docs/04_implementation_scope.md)               |
| CI/CD       | GitHub Actions, Docker Build, ECR Push, Argo CD GitOps Deploy                      | [Deployment Runbook](docs/runbooks/deployment.md)                     |
| 보안        | IAM OIDC Role, 최소 권한, WAF, Secrets Manager, HTTPS                              | [Security Policy](docs/05_security_policy.md)                         |
| 데이터      | Percona XtraDB Cluster, ProxySQL, Ceph 백업                                        | [Architecture](docs/01_architecture.md)                               |
| 스토리지    | Ceph RGW/RBD/CephFS 활용 전략                                                      | [Ceph Usage Strategy](docs/13_ceph_usage_strategy.md)                 |
| DB 운영     | PXC, ProxySQL, Ceph 백업 점검 절차                                                 | [DB & Ceph Runbook](docs/runbooks/database_storage.md)                |
| 역할별 구축 | 팀원별 상세 구현 가이드                                                            | [Build-up Guide](docs/architecture/build-up/README.md)                |
| 관측성      | CloudWatch Logs/Metrics/Alarm, 배포 상태 추적                                      | [Monitoring Runbook](docs/runbooks/monitoring.md)                     |
| 발표        | 장애 복구, 롤백, 보안 설계, 비용 최적화 설명                                       | [Presentation Plan](docs/06_demo_presentation_plan.md)                |
| GitHub 설정 | OIDC Secret, Branch Protection, 플레이스홀더 교체                                  | [GitHub Setup](docs/11_github_setup.md)                               |
| 공유 정책   | GitHub에 올릴 자료와 제외할 자료                                                   | [Repository Sharing Policy](docs/12_repository_sharing_policy.md)     |
| 비교/채택   | 기존 프로젝트 대비 신규 프로젝트 적용 범위                                         | [Existing Project Comparison](docs/14_existing_project_comparison.md) |
| 구조 점검   | 현재 구조의 주의 사항과 보완 후보                                                  | [Structure Review](docs/15_structure_review.md)                       |
| 변경 이력   | 주요 설계 변경과 보완 이력                                                         | [Change Log](docs/16_change_log.md)                                   |
| AI 협업     | Codex/ChatGPT 작업 요청 기준                                                       | [AI Collaboration Guide](docs/17_ai_collaboration_guide.md)           |
| 용어집      | AWS와 인프라 약어 설명                                                             | [Glossary](docs/22_glossary.md)                                       |

## 3. 선택 확장 범위

일정에 여유가 있을 때만 적용함.

- Blue/Green 배포: CodeDeploy 또는 ECS Deployment Circuit Breaker 기반
- Route 53 + ACM 인증서 + HTTPS 도메인 연결
- S3 + CloudFront 정적 자산 오프로딩
- ProxySQL 이중화와 Internal NLB: `proxysql_count = 2`, `enable_proxysql_internal_nlb = true`
- AWS S3 2차 백업 복제
- Prometheus/Grafana 별도 구축

## 4. 저장소 구조

```text
.
├── .github/workflows/          # CI/CD 파이프라인 템플릿
├── app/                        # 임시 배포 검증용 샘플 앱, 실제 앱으로 교체 가능
├── docs/                       # 일정, 역할, 설계, 발표 자료
├── infra/
│   ├── terraform/              # AWS IaC 템플릿
│   └── ansible/                # 선택: EC2 운영 자동화
├── k8s/                        # 선택: 향후 K8s 확장 매니페스트
├── scripts/                    # 운영 보조 스크립트
└── tests/                      # 인프라 검증 체크리스트 및 스모크 테스트
```

## 5. 빠른 시작

```powershell
git status
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars
```

실제 배포 전 `infra/terraform/env/dev.tfvars`의 AWS 리전, 프로젝트명, 컨테이너 포트, 도메인 사용
여부를 팀 기준에 맞게 수정함.

## 6. 핵심 일정

- **Day 1-13:** 시스템 구축
- **Day 14-16:** 시연 포함 발표 자료 준비

상세 일정은 [13+3 상세 일정](docs/02_schedule_13_plus_3.md) 참조

## 7. 팀 환경 구축

팀원 초기 환경 설정은 [Environment Setup](docs/ENVIRONMENT_SETUP.md)을 기준으로 함. 개발/검증 도구는
`uv sync --group dev`로 설치하며, 여기에는 pre-commit, MkDocs, Ruff, pip-audit가 포함됨. 품질 검증과
도구 문제 해결은 [Docs Index](docs/index.md)의 팀 운영 문서를 따름.

## 8. 문서 홈

문서를 처음 읽을 때는 [Docs Index](docs/index.md)의 순서와 역할별 링크를 기준으로 함. MkDocs 도입
시에도 이 문서를 navigation 초안으로 사용함.

## 9. GitHub 공유 기준

인프라 프로젝트는 코드뿐 아니라 설계 근거, Runbook, 검증 기록까지 함께 공유해야 함. 자세한 기준은
[Repository Sharing Policy](docs/12_repository_sharing_policy.md)를 따름.

## 10. AI 협업 기준

Codex나 ChatGPT에 작업을 맡길 때는 루트의 `AGENTS.md`와
[AI Collaboration Guide](docs/17_ai_collaboration_guide.md)를 기준으로 함.
