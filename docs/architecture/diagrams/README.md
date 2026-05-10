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

## 2. 문서 공통 해석 규칙

각 다이어그램 문서는 아래 항목을 공통으로 포함함.

1. 범위/비범위(이번 문서가 다루는 경계)
2. 컴포넌트 역할 요약
3. 핵심 트래픽/데이터 흐름
4. 보안 경계 및 운영 체크포인트
5. 연계 문서(상세 build-up / runbook)

## 3. 운영 원칙

- 역할 경계의 단일 기준은 `docs/03_roles_and_work_packages.md`를 따름.
- 다이어그램 수정 시 관련 build-up 문서와 함께 정합성을 확인함.
- 문서 검증은 `uv run mkdocs build`로 수행함.

## 4. 권장 읽기 순서

1. `00_system_context.md`로 전체 경계 이해
2. 본인 역할 문서(01~04)로 책임 범위 상세 확인
3. build-up / runbook으로 실제 절차와 검증 기준 확인
