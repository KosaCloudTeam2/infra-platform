# Cloud Infra Platform Docs

이 문서는 13일 시스템 구축 + 3일 발표 준비를 위한 문서 홈임. 처음 보는 팀원은 아래 순서대로 읽고,
담당자는 자기 영역 문서와 구현 절차 문서를 함께 확인함.

> 전환 안내(2026-05-09 ~ 2026-05-16): 아키텍처 문서를 단일 대형 문서에서 통합(Level 0) + 상세(Level
> 1/2) 구조로 분리 중임. 기존 링크를 쓰던 팀원은 아래 "아키텍처 상세 문서"를 우선 확인함.

## 0. 아키텍처 상세 문서 (신규)

| 구분                  | 문서                                                                                         | 목적                               |
| :-------------------- | :------------------------------------------------------------------------------------------- | :--------------------------------- |
| Level 0 (통합)        | [Architecture](./01_architecture.md)                                                         | 전체 흐름과 설계 고정점 확인       |
| Level 1 (네트워크)    | [Network / LB](./architecture/details/network_and_lb.md)                                     | 네트워크/진입점 상세               |
| Level 1 (런타임/보안) | [Runtime / CI-CD / Security](./architecture/details/runtime_cicd_security.md)                | 배포/런타임/보안 경계 상세         |
| Level 1 (데이터/비용) | [Data / Ceph / Observability / Cost](./architecture/details/data_ceph_observability_cost.md) | DB/Ceph/관측/비용 상세             |
| Level 2 (운영 절차)   | [Ops Flow / Extensions](./architecture/details/ops_flow_and_extensions.md)                   | Runbook/운영 시퀀스/확장 연결 허브 |

## 1. 처음 읽는 순서

| 순서 | 문서                                                       | 목적                                        |
| :--- | :--------------------------------------------------------- | :------------------------------------------ |
| 1    | [Project Overview](./00_project_overview.md)               | 프로젝트 목표와 성공 기준 확인              |
| 2    | [Architecture](./01_architecture.md)                       | 전체 하이브리드 아키텍처와 설계 고정점 확인 |
| 3    | [Schedule 13+3](./02_schedule_13_plus_3.md)                | 13일 구축 + 3일 발표 일정 확인              |
| 4    | [Roles and Work Packages](./03_roles_and_work_packages.md) | 팀원별 책임과 작업 패키지 확인              |
| 5    | [Implementation Scope](./04_implementation_scope.md)       | MVP와 선택 확장 범위 확인                   |
| 6    | [Security Policy](./05_security_policy.md)                 | OIDC, SG, WAF, Secret 기준 확인             |
| 7    | [Demo Presentation Plan](./06_demo_presentation_plan.md)   | 발표/시연 흐름 확인                         |
| 8    | [Definition of Done](./07_definition_of_done.md)           | 완료 기준 확인                              |
| 9    | [Risk Register](./08_risk_register.md)                     | 주요 리스크와 대응 확인                     |
| 10   | [Cleanup Plan](./09_cleanup_plan.md)                       | 발표 후 비용 정리 계획 확인                 |

## 2. 팀 운영 문서

| 문서                                                           | 목적                                       |
| :------------------------------------------------------------- | :----------------------------------------- |
| [Commit Strategy](./10_commit_strategy.md)                     | 브랜치, 커밋, PR 기준                      |
| [GitHub Setup](./11_github_setup.md)                           | GitHub OIDC, Secret, Branch Protection     |
| [Repository Sharing Policy](./12_repository_sharing_policy.md) | GitHub 공유/제외 기준                      |
| [Environment Setup](./ENVIRONMENT_SETUP.md)                    | 팀원 초기 환경 설정                        |
| [Daily Notice](./daily_notice/README.md)                       | 당일 공지와 작업 전 확인 사항              |
| [AI Collaboration Guide](./17_ai_collaboration_guide.md)       | AI 도구 작업 요청 기준                     |
| [Quality Checks](./18_quality_checks.md)                       | 문서 변경 검증 기준(`uv run mkdocs build`) |
| [Tool Troubleshooting](./19_tool_troubleshooting.md)           | winget, Terraform, Git Hook 문제 해결      |
| [MkDocs Guide](./20_mkdocs_guide.md)                           | 문서 사이트 로컬 미리보기                  |
| [Team Decision Checklist](./21_team_decision_checklist.md)     | 팀 회의에서 결정해야 할 선택지와 용어 확인 |
| [Glossary](./22_glossary.md)                                   | AWS와 인프라 약어 확인                     |
| [Technical Questions](./23_technical_questions.md)             | 회의 중 나온 기술 질문과 적용 판단 확인    |
| [Tech Stack Ownership](./24_tech_stack_ownership.md)           | 기술 스택별 담당자와 협업 경계 확인        |

## 3. 설계 보완 문서

| 문서                                                               | 목적                               |
| :----------------------------------------------------------------- | :--------------------------------- |
| [Ceph Usage Strategy](./13_ceph_usage_strategy.md)                 | Ceph RGW/RBD/CephFS 활용 범위      |
| [Existing Project Comparison](./14_existing_project_comparison.md) | 기존 프로젝트와 신규 프로젝트 비교 |
| [Structure Review](./15_structure_review.md)                       | 현재 구조와 보완 후보              |
| [Change Log](./16_change_log.md)                                   | 주요 변경 이력                     |
| [Architecture Decisions](./architecture/decisions/README.md)       | 주요 설계 결정과 근거              |

## 4. 역할별 구축 문서

역할별 설계/범위 문서와 실제 구현 절차 문서는 [Build-up Guide](./architecture/build-up/README.md)를
기준으로 확인함.

| 담당                               | 핵심 문서                                                                                                                                                                    |
| :--------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cloud / Network / IaC              | [01 Cloud / Network / IaC](./architecture/build-up/01_network_iac.md), [Implementation](./architecture/build-up/01_network_iac_implementation.md)                            |
| DB / Storage                       | [02 DB / Storage](./architecture/build-up/02_db_storage.md), [Implementation](./architecture/build-up/02_db_storage_implementation.md)                                       |
| CI/CD / App Runtime                | [03 CI/CD / App Runtime](./architecture/build-up/03_cicd_app_runtime.md), [Implementation](./architecture/build-up/03_cicd_app_runtime_implementation.md)                    |
| Observability / Integration / Demo | [04 Observability / Integration / Demo](./architecture/build-up/04_observability_demo.md), [Implementation](./architecture/build-up/04_observability_demo_implementation.md) |
| Presentation / Handover            | [05 Presentation / Handover](./architecture/build-up/05_presentation_handover.md), [Implementation](./architecture/build-up/05_presentation_handover_implementation.md)      |

## 5. 운영 Runbook

| Runbook                                                | 목적                                         |
| :----------------------------------------------------- | :------------------------------------------- |
| [Deployment](./runbooks/deployment.md)                 | Argo CD GitOps 배포 확인                     |
| [Rollback](./runbooks/rollback.md)                     | 배포 실패/서비스 장애 롤백                   |
| [Monitoring](./runbooks/monitoring.md)                 | CloudWatch 또는 Prometheus/Grafana 기반 관측 |
| [Database Storage](./runbooks/database_storage.md)     | PXC, ProxySQL, Ceph 백업 점검                |
| [Incident Scenarios](./runbooks/incident_scenarios.md) | 장애 시나리오                                |

## 6. 발표 자료

| 문서                                           | 목적           |
| :--------------------------------------------- | :------------- |
| [Presentation](./presentation/presentation.md) | Marp 발표 원본 |
| [Outline](./presentation/outline.md)           | 발표 목차      |
| [Demo Script](./presentation/demo_script.md)   | 시연 스크립트  |
| [Q&A](./presentation/qna.md)                   | 예상 질문      |

## 7. MkDocs 도입 기준

현재는 번호 기반 루트 문서를 유지하되, 아키텍처 문서는 Phase 1로 통합(Level 0) + 상세(Level 1/2)
구조를 병행 운영함. MkDocs는 `mkdocs.yml` nav에서 통합/상세 진입 경로를 함께 제공함.

디렉터리 재구성 확대는 다음 조건이 생기면 추가 검토함.

- 루트 문서가 25개 이상으로 늘어남
- 문서가 순서형 온보딩 문서가 아니라 영역별 참고 문서 중심으로 바뀜
- MkDocs navigation만으로 문서 탐색성이 부족함
- 문서 이동에 따른 링크 수정 비용을 감당할 수 있음
