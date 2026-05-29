# Terraform Area

온프레미스 Proxmox 및 선택 AWS IaC 코드 영역.

## 현재 기준

- 우선순위: 온프레미스 Proxmox VM baseline
- 코드 위치: `infra/terraform/proxmox/`
- 상태: 실제 Proxmox API 조회값 반영, Terraform fmt/validate/plan 통과
- 적용 원칙: 기존 VM import 후 plan 검토
- 비밀값 원칙: `PROXMOX_VE_*` 환경변수 사용, 저장소 저장 금지

## 기존 AWS 초안

- 위치: `docs/architecture/build-up/cloud_network_iac/aws-hybrid-terraform/`
- 상태: 문서/초안 관리
- 원칙: 검증 완료 파일만 `infra/` 승격
