# Cloud Infra Platform Docs (Demo Version)

> **주의**: 본 문서는 프로젝트의 **데모(Demo) 버전** 또는 **임시 구조**를 설명하고 있습니다. 향후
> 전체적인 프로젝트 구조가 변경될 예정이므로 참고하시기 바랍니다.

이 문서는 13일 시스템 구축 + 3일 발표 준비를 위한 문서 홈임. 처음 보는 팀원은 아래 순서대로 읽고,
담당자는 자기 영역 문서와 구현 절차 문서를 함께 확인함.

## 1. 필수 가이드

| 순서 | 문서                                        | 목적                        |
| :--- | :------------------------------------------ | :-------------------------- |
| 1    | [Cleanup Plan](./01_cleanup_plan.md)        | 발표 후 비용 정리 계획 확인 |
| 2    | [Environment Setup](./ENVIRONMENT_SETUP.md) | 팀원 초기 환경 설정         |
| 3    | [Commit Strategy](./02_commit_strategy.md)  | 브랜치, 커밋, PR 기준       |
| 4    | [MkDocs Guide](./03_mkdocs_guide.md)        | 문서 사이트 로컬 미리보기   |

## 2. 운영 및 참고 문서

| 문서                                     | 목적                          |
| :--------------------------------------- | :---------------------------- |
| [Glossary](./04_glossary.md)             | AWS와 인프라 약어 확인        |
| [Daily Notice](./daily_notice/README.md) | 당일 공지와 작업 전 확인 사항 |
| [Change Log](./change_log.md)            | 프로젝트 변경 이력 확인       |

## 3. 프로젝트 상세 정보 (Project Info)

기존의 상세 설계 및 보안 정책 등은 아래 링크에서 확인할 수 있습니다.

- [Security Policy](./project_info/05_security_policy.md)
- [Definition of Done](./project_info/07_definition_of_done.md)
- [Risk Register](./project_info/08_risk_register.md)
- [GitHub Setup](./project_info/11_github_setup.md)
- [Quality Checks](./project_info/18_quality_checks.md)
- [Troubleshooting Index](./troubleshooting/README.md)
- [Troubleshooting Issues](./troubleshooting/issues/TS-01-winget-terraform.md)
- [Team Decision Checklist](./project_info/21_team_decision_checklist.md)

## 4. 아키텍처 및 구축 문서

상세 구현 절차 문서는 [Build-up Guide](./architecture/build-up/README.md)를 기준으로 확인함.

- [Architecture Decisions](./architecture/decisions/README.md)

## 5. 운영 Runbook

| Runbook                                                | 목적                                         |
| :----------------------------------------------------- | :------------------------------------------- |
| [Rollback](./runbooks/rollback.md)                     | 배포 실패/서비스 장애 롤백                   |
| [Monitoring](./runbooks/monitoring.md)                 | CloudWatch 또는 Prometheus/Grafana 기반 관측 |
| [Incident Scenarios](./runbooks/incident_scenarios.md) | 장애 시나리오                                |

## 6. 발표 자료

- [Presentation](./presentation/presentation.md)
- [Outline](./presentation/outline.md)
- [Demo Script](./presentation/demo_script.md)
- [Q&A](./presentation/qna.md)
