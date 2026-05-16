# Build-up Guide (Demo Version)

13일 시스템 구축 + 3일 발표 준비를 위한 역할 기반 상세 구현 가이드.

---

## 1. 폴더 구조

`_workspace` 임시 경로는 제거하고, 역할별 폴더를 `build-up/` 바로 아래로 통합함.

| 폴더                         | 설명                                      | 진입 문서                                       |
| :--------------------------- | :---------------------------------------- | :---------------------------------------------- |
| `cloud_network_iac/`         | 클라우드/네트워크/IaC 관련 설계·구현 문서 | [README](./cloud_network_iac/README.md)         |
| `db_storage/`                | DB/스토리지 구축 및 검증 문서             | [README](./db_storage/README.md)                |
| `cicd_app_runtime/`          | CI/CD 및 앱 런타임 문서                   | [README](./cicd_app_runtime/README.md)          |
| `observability_integration/` | 관측/통합 문서                            | [README](./observability_integration/README.md) |

## 2. 문서 상태 라벨 규칙

`docs/architecture/build-up/` 하위 문서는 아래 3가지 상태 라벨 중 하나를 문서 상단에 명시함.

- `Unverified`: 미검증 상태
- `Verified`: 검증완료 상태
- `Deprecated`: 더 이상 유효하지 않음

표기 형식:

```md
> Status: Unverified
```

상태 변경 시 관련 `README.md` 표와 `docs/change_log.md`를 함께 갱신함.

## 3. 공통 원칙

- DB 노드는 Data Private Subnet에만 배치함
- DB 관련 포트는 인터넷에 열지 않음
- Terraform `apply`는 담당자 1명만 수행함
- 콘솔 수작업이 발생하면 Runbook에 반영함
- Day 14부터 신규 기능 추가 금지
