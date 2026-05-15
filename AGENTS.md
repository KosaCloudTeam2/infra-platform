# Agent Instructions

이 저장소는 4인 팀의 클라우드 인프라 구축 프로젝트 저장소임. AI 도구(Codex/ChatGPT/Gemini 등)는 이
파일을 최우선 지침으로 사용함.

## 프로젝트 기준

- 문서는 한국어로 작성함.
- 일정은 **13일 구축 + 3일 발표 준비** 기준을 유지함.
- 기본 런타임은 온프레미스 Proxmox 기반 Kubernetes임.
- DB는 **온프레미스 VM 기반 PXC + ProxySQL + Ceph(RBD/CephFS/RGW)** 기준을 우선함.
- EKS는 검증/학습용 PoC 트랙으로 관리함.
- 운영 키/비밀값은 저장소에 저장하지 않음(OIDC + IAM Role 우선).
- Day 14 이후에는 신규 기능보다 발표 안정화/캡처/Runbook 검증을 우선함.

## AI 작업 원칙

- 분석만 요청받은 경우가 아니면 필요한 파일을 읽고 직접 수정함.
- 기존 문서 구조를 먼저 확인하고 작은 변경 단위로 반영함.
- 보안/비용/발표 가능성을 악화시키는 변경은 근거와 한계를 함께 기록함.
- 사용자의 미완성 작업, untracked 파일, 수동 작성 문서를 임의 삭제/복원하지 않음.
- 기술 용어는 처음 등장 시 한국어(English/약어)로 병기함.

## 변경 원칙

- 아키텍처/구현 절차 변경 시 `docs/architecture/build-up/` 하위 문서와 해당 폴더 `README.md`를 함께
  갱신함.
- 보안 정책 변경 시 `docs/project_info/05_security_policy.md`를 함께 갱신함.
- 운영/장애 대응 변경 시 `docs/runbooks/` 문서를 함께 갱신함.
- 주요 설계/구현/문서 변경 시 `docs/change_log.md`에 이력을 남김.
- 민감 정보(`.tfstate`, `.env`, 개인키, 인증서, Access Key`)는 커밋하지 않음.

## 설계 고정점

- 온프레미스 앱은 Kubernetes Ingress/Service 경로로 노출함.
- DB 앱 접속은 PXC 직접 연결이 아니라 ProxySQL endpoint 경유를 원칙으로 함.
- ProxySQL 단일 구성은 SPOF임을 문서에 명시함.
- PXC는 3노드 + Single Writer 운영 기준을 우선함.
- Ceph는 주 DB 디스크가 아니라 RBD/CephFS/RGW 용도로 분리해서 설명함.
- Terraform apply는 담당자 1명 원칙을 유지함.

## 검증 기준

- 문서/설정 변경 검증은 `uv run mkdocs build` 기준으로 수행함.

## 커밋/보고 원칙

- 커밋/푸시는 사용자가 명시적으로 요청한 경우에만 수행함.
- 작업 완료 시 변경 파일, 검증 결과, 미검증 사유를 요약함.
- 필요 시 한국어 커밋 메시지 초안을 제안함.
