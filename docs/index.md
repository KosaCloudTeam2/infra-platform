# Cloud Infra Platform Docs

이 문서는 13일 시스템 구축 + 3일 발표 준비를 위한 문서 홈임.

## 1. 읽기 경계(필독/심화)

| 구분        | 대상        | 읽기 목표                                                | 기준 시간           |
| :---------- | :---------- | :------------------------------------------------------- | :------------------ |
| 전원 필독   | 모든 팀원   | 프로젝트 공통 기준, 책임 경계, 일정, 보안/운영 원칙 이해 | 5~7분(필요 시 확장) |
| 역할별 심화 | 담당자 중심 | 자기 역할의 상세 구현/Runbook/시연 절차 이해             | 역할별 상이         |

### 1.1 전원 필독(우선순위 순)

1. [Project Overview](./00_project_overview.md)
2. [Architecture](./01_architecture.md)
3. [Schedule 13+3](./02_schedule_13_plus_3.md)
4. [Roles and Work Packages](./03_roles_and_work_packages.md)
5. [Implementation Scope](./04_implementation_scope.md)
6. [Security Policy](./05_security_policy.md)
7. [Demo Presentation Plan](./06_demo_presentation_plan.md)
8. [Definition of Done](./07_definition_of_done.md)
9. [Risk Register](./08_risk_register.md)
10. [Cleanup Plan](./09_cleanup_plan.md)

역할 경계의 단일 기준 문서는 [Roles and Work Packages](./03_roles_and_work_packages.md)임.

## 2. 심화: 팀 운영 문서

| 문서                                                           | 목적                                       |
| :------------------------------------------------------------- | :----------------------------------------- |
| [Commit Strategy](./10_commit_strategy.md)                     | 브랜치, 커밋, PR 기준                      |
| [GitHub Setup](./11_github_setup.md)                           | GitHub OIDC, Secret, Branch Protection     |
| [Repository Sharing Policy](./12_repository_sharing_policy.md) | GitHub 공유/제외 기준                      |
| [Environment Setup](./ENVIRONMENT_SETUP.md)                    | 팀원 초기 환경 설정                        |
| [Daily Notice](./daily_notice/README.md)                       | 당일 공지와 작업 전 확인 사항              |
| [AI Collaboration Guide](./17_ai_collaboration_guide.md)       | AI 도구 작업 요청 기준                     |
| [Quality Checks](./18_quality_checks.md)                       | 품질 검증과 Terraform 검증                 |
| [Tool Troubleshooting](./19_tool_troubleshooting.md)           | winget, Terraform, Git Hook 문제 해결      |
| [MkDocs Guide](./20_mkdocs_guide.md)                           | 문서 사이트 로컬 미리보기                  |
| [Team Decision Checklist](./21_team_decision_checklist.md)     | 팀 회의에서 결정해야 할 선택지와 용어 확인 |
| [Glossary](./22_glossary.md)                                   | AWS와 인프라 약어 확인                     |
| [Technical Questions](./23_technical_questions.md)             | 회의 중 나온 기술 질문과 적용 판단 확인    |
| [Tech Stack Ownership](./24_tech_stack_ownership.md)           | 기술 스택별 담당자와 협업 경계 확인        |

## 3. 심화: 설계 보완 문서

| 문서                                                               | 목적                               |
| :----------------------------------------------------------------- | :--------------------------------- |
| [Ceph Usage Strategy](./13_ceph_usage_strategy.md)                 | Ceph RGW/RBD/CephFS 활용 범위      |
| [Existing Project Comparison](./14_existing_project_comparison.md) | 기존 프로젝트와 신규 프로젝트 비교 |
| [Structure Review](./15_structure_review.md)                       | 현재 구조와 보완 후보              |
| [Change Log](./16_change_log.md)                                   | 주요 변경 이력                     |
| [Architecture Decisions](./architecture/decisions/README.md)       | 주요 설계 결정과 근거              |

## 4. 심화: 역할별 구축 문서

역할별 설계/범위 문서와 실제 구현 절차 문서는 [Build-up Guide](./architecture/build-up/README.md)를
기준으로 확인함.

| 담당                               | 핵심 문서                                                                                                                                                                                                                                                                                                        |
| :--------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cloud / Network / IaC              | [01 Cloud / Network / IaC](./architecture/build-up/01_network_iac.md), [Implementation](./architecture/build-up/01_network_iac_implementation.md)                                                                                                                                                                |
| DB / Storage                       | [02 DB / Storage](./architecture/build-up/02_db_storage.md), [Implementation](./architecture/build-up/02_db_storage_implementation.md), [RBD Register Guide](./architecture/build-up/db_storage/01_rbd_register_guide.md), [Template Clone Guide](./architecture/build-up/db_storage/02_template_clone_guide.md) |
| CI/CD / App Runtime                | [03 CI/CD / App Runtime](./architecture/build-up/03_cicd_app_runtime.md), [Implementation](./architecture/build-up/03_cicd_app_runtime_implementation.md)                                                                                                                                                        |
| Observability / Integration / Demo | [04 Observability / Integration / Demo](./architecture/build-up/04_observability_demo.md), [Implementation](./architecture/build-up/04_observability_demo_implementation.md)                                                                                                                                     |
| Presentation / Handover            | [05 Presentation / Handover](./architecture/build-up/05_presentation_handover.md), [Implementation](./architecture/build-up/05_presentation_handover_implementation.md)                                                                                                                                          |

## 5. 심화: 운영 Runbook

| Runbook                                                | 목적                                         |
| :----------------------------------------------------- | :------------------------------------------- |
| [Deployment](./runbooks/deployment.md)                 | Argo CD GitOps 배포 확인                     |
| [Rollback](./runbooks/rollback.md)                     | 배포 실패/서비스 장애 롤백                   |
| [Monitoring](./runbooks/monitoring.md)                 | CloudWatch 또는 Prometheus/Grafana 기반 관측 |
| [Database Storage](./runbooks/database_storage.md)     | PXC, ProxySQL, Ceph 백업 점검                |
| [Incident Scenarios](./runbooks/incident_scenarios.md) | 장애 시나리오                                |

## 6. 심화: 발표 자료

| 문서                                           | 목적           |
| :--------------------------------------------- | :------------- |
| [Presentation](./presentation/presentation.md) | Marp 발표 원본 |
| [Outline](./presentation/outline.md)           | 발표 목차      |
| [Demo Script](./presentation/demo_script.md)   | 시연 스크립트  |
| [Q&A](./presentation/qna.md)                   | 예상 질문      |

## 7. 아키텍처 다이어그램 읽기

전체/역할별 다이어그램은 [Architecture Diagram Guide](./architecture/diagrams/README.md)에서 확인함.

- 전원 필독: [Overall System Context](./architecture/diagrams/00_system_context.md)
- 역할별 심화:
  - [Cloud / Network / IaC View](./architecture/diagrams/01_cloud_network_iac.md)
  - [DB / Storage View](./architecture/diagrams/02_db_storage.md)
  - [CI/CD / App Runtime View](./architecture/diagrams/03_cicd_app_runtime.md)
  - [Observability / Integration / Demo View](./architecture/diagrams/04_observability_integration_demo.md)

## 8. MkDocs 도입 기준

현재는 번호 기반 루트 문서를 유지함. 이유는 첫 커밋과 팀 온보딩 단계에서 읽는 순서가 명확하기
때문임. MkDocs를 도입할 때도 파일을 대규모 이동하기보다 `mkdocs.yml`의 `nav`를 번호 흐름에 맞춰
표현하는 방식을 우선함.

디렉터리 재구성은 다음 조건이 생기면 검토함.

- 루트 문서가 25개 이상으로 늘어남
- 문서가 순서형 온보딩 문서가 아니라 영역별 참고 문서 중심으로 바뀜
- MkDocs navigation만으로 문서 탐색성이 부족함
- 문서 이동에 따른 링크 수정 비용을 감당할 수 있음
