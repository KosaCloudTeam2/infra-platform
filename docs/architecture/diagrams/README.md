# Architecture Diagram Guide

전체 아키텍처와 역할별 아키텍처를 분리해 읽기 경계를 명확히 하기 위한 다이어그램 허브임.

## 1. 읽기 기준

| 구분        | 문서                                                                           | 대상                                    |
| :---------- | :----------------------------------------------------------------------------- | :-------------------------------------- |
| 전원 필독   | [00_system_context.md](./00_system_context.md)                                 | 모든 팀원                               |
| 역할별 심화 | [01_cloud_network_iac.md](./01_cloud_network_iac.md)                           | Cloud / Network / IaC 담당              |
| 역할별 심화 | [02_db_storage.md](./02_db_storage.md)                                         | DB / Storage 담당                       |
| 역할별 심화 | [03_cicd_app_runtime.md](./03_cicd_app_runtime.md)                             | CI/CD / App Runtime 담당                |
| 역할별 심화 | [04_observability_integration_demo.md](./04_observability_integration_demo.md) | Observability / Integration / Demo 담당 |

## 2. 운영 원칙

- 역할 경계의 단일 기준은 `docs/03_roles_and_work_packages.md`를 따름.
- 다이어그램 수정 시 관련 build-up 문서와 함께 정합성을 확인함.
- 문서 검증은 `uv run mkdocs build`로 수행함.
