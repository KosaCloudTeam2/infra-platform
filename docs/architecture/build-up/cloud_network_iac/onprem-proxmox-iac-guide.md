# On-prem Proxmox IaC Guide

> Status: Unverified

온프레미스 Proxmox 기반 Terraform/Ansible 코드 기준.

## 확인값

- 확인일: 2026-05-29
- Proxmox cluster: `team2`
- Proxmox VE: `9.1.9`
- Proxmox node: `kosa1`, `kosa2`, `kosa3`, `kosa4`
- Proxmox API 기준 node 상태: 4대 online
- VM template: `ubuntu-2204-template`, VMID `9000`, node `kosa1`
- VM disk storage: `ceph-rbd-team2`
- cloud-init storage: `local-lvm`
- Ceph monitor: `10.10.10.12`, `10.10.10.11`, `10.10.10.13`, `10.10.10.14`
- K8s node: `k8s-cp1`, `k8s-cp2`, `k8s-cp3`, `k8s-w1`, `k8s-w2`, `k8s-w3`, `k8s-sys1`
- Bastion: `172.16.24.10`
- Edge HAProxy: `172.16.22.10`, `172.16.22.11`

## 코드 위치

- Terraform: `infra/terraform/proxmox/`
- Terraform 변수 예시: `infra/terraform/proxmox/env/onprem.tfvars.example`
- Terraform 운영 변수: `infra/terraform/proxmox/env/onprem.tfvars`, gitignore 대상
- Terraform import block: `infra/terraform/proxmox/imports.tf`
- Ansible inventory: `infra/ansible/inventories/`
- Ansible playbook: `infra/ansible/playbooks/`
- Ansible role: `infra/ansible/roles/`

## Terraform 원칙

- 기존 VM import 우선
- `terraform apply` 직접 실행 금지
- `terraform plan` diff 검토 후 담당자 1명 적용
- `prevent_destroy = true` 적용
- Proxmox 인증값 환경변수 사용
- 비밀번호, API token, private key 저장소 저장 금지

## Ansible 원칙

- bastion 실행 우선
- `~/.ssh/kosa_iac` private key 로컬 보관
- `verify.yml` 우선 실행
- 변경 playbook 실행 전 `--check --diff` 실행
- `edge-haproxy.yml` 실행 시 TLS 인증서 존재 확인
- HAProxy stats password Ansible Vault 관리

## 실제 상태 요약

| 구분               | 값                                |
| :----------------- | :-------------------------------- |
| Kubernetes version | `v1.30.14`                        |
| containerd version | `2.2.1`                           |
| OS                 | `Ubuntu 24.04.4 LTS`              |
| StorageClass       | `team2-rbd-block`                 |
| MetalLB pool       | `172.16.23.50-172.16.23.99`       |
| PXC status         | `ready`, PXC `3`, ProxySQL `2`    |
| ProxySQL endpoint  | `kosa-pxc-proxysql.pii-protected` |
| PXC PVC            | `50Gi`, `team2-rbd-block`         |
| ProxySQL PVC       | `2Gi`, `team2-rbd-block`          |

## 제외 및 보류

- `pfsense-1`, `pfsense-2`: appliance 수동 운영
- `lb-1`, `lb-2`: linked clone disk path 추가 확인 필요
- `edge-haproxy`, `edge-haproxy2`: Terraform import 전 별도 검토
- Kubernetes join 자동화: 기존 cluster 안정성 우선, 별도 보류

## 검증 상태

- Proxmox API 조회: 완료
- QEMU guest agent 내부 조회: 완료
- Kubernetes API 조회: 완료
- Terraform fmt: 통과
- Terraform validate: 통과
- Terraform plan: `8 to import, 0 to add, 0 to change, 0 to destroy`
- Ansible syntax/check: 로컬 Ansible 미설치로 미검증
- MkDocs build: 통과
