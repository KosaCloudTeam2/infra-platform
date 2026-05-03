# AI Collaboration Guide

Codex, ChatGPT 등 AI 도구에 작업을 맡길 때 결과를 일관되게 만들기 위한 요청 기준

---

## 1. 기본 원칙

- 저장소 루트의 `AGENTS.md`를 AI 작업 기준으로 사용함
- 설계 변경은 코드만 수정하지 않고 관련 문서와 Runbook을 함께 갱신함
- 일정이 13+3 범위를 넘는 기능은 선택 확장 또는 향후 과제로 분리함
- 보안, 비용, 발표 가능성에 영향을 주는 변경은 한계와 검증 방법을 함께 기록함

---

## 2. 요청 템플릿

```text
목표:
변경 범위:
관련 문서:
건드리지 말 것:
검증 방법:
완료 기준:
```

예시:

```text
목표: DB 내부망 보안 정책을 Terraform과 문서에 맞게 정리
변경 범위: infra/terraform, docs/05_security_policy.md, docs/runbooks/database_storage.md
관련 문서: docs/01_architecture.md
건드리지 말 것: app 코드, 발표 자료
검증 방법: terraform fmt, terraform validate, terraform plan
완료 기준: DB 포트가 인터넷에 열리지 않고 앱은 ProxySQL endpoint만 사용
```

---

## 3. 작업 유형별 확인 문서

| 작업 유형                 | 함께 확인할 문서                                                                   |
| :------------------------ | :--------------------------------------------------------------------------------- |
| 아키텍처 변경             | `docs/01_architecture.md`, `docs/15_structure_review.md`                           |
| 일정/역할 변경            | `docs/02_schedule_13_plus_3.md`, `docs/03_roles_and_work_packages.md`              |
| Terraform 변경            | `infra/terraform/README.md`, 관련 Runbook                                          |
| DB/PXC/ProxySQL/Ceph 변경 | `docs/architecture/build-up/02_db_storage.md`, `docs/runbooks/database_storage.md` |
| CI/CD 변경                | `docs/architecture/build-up/03_cicd_app_runtime.md`, `docs/runbooks/deployment.md` |
| 보안 변경                 | `docs/05_security_policy.md`, `docs/08_risk_register.md`                           |
| 발표 변경                 | `docs/06_demo_presentation_plan.md`, `docs/presentation/`                          |

---

## 4. AI에게 명확히 말해야 하는 것

- 이번 작업이 MVP 필수인지 선택 확장인지
- 실제 AWS에 적용할 코드인지 발표용 문서인지
- 비용 발생 리소스를 추가해도 되는지
- Terraform `apply`까지 원하는지, `plan`까지만 원하는지
- 기존 사용자 작업을 보존해야 하는 파일이 있는지

---

## 5. 피해야 할 요청 방식

아래처럼 요청하면 AI가 범위를 과하게 넓힐 수 있음.

- “전체적으로 좋게 고쳐줘”
- “운영급으로 만들어줘”
- “가능한 기능 다 넣어줘”
- “문서도 알아서 정리해줘”

대신 다음처럼 범위를 고정함.

- “Day 8까지 가능한 MVP 기준으로 정리해줘”
- “Terraform과 Runbook만 수정해줘”
- “선택 확장은 구조 리뷰 문서에만 남겨줘”
- “실제 구현하지 말고 의사결정 문서로만 정리해줘”
