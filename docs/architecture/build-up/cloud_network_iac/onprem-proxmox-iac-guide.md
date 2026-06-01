# On-prem Proxmox IaC Guide

> Status: Unverified

온프레미스 Proxmox 최초 구축용 Terraform/Ansible 기준.

## 목적

- 최초 설치 기준 가이드
- Proxmox VM 템플릿 생성
- Terraform VM clone 생성
- Ansible 운영 검증
- 기존 VM 편입 절차 별도 분리

## 이미지 전략

- 프로젝트 기준 OS: Ubuntu Server 24.04 LTS Noble
- 프로젝트 기준 원본: Ubuntu 공식 cloud image
- 프로젝트 기준 파일: `noble-server-cloudimg-amd64.img`
- 공식 확인 경로: `https://cloud-images.ubuntu.com/noble/current/`
- 최신 전체 목록: `https://cloud-images.ubuntu.com/`, 프로젝트 기준과 별도
- Terraform VM 생성 방식: cloud image 직접 사용 아님
- Terraform VM 생성 방식: Proxmox cloud-init template full clone
- 운영 흐름: cloud image 다운로드 -> Proxmox template 생성 -> Terraform clone

## cloud image 장점

- ISO 설치 과정 생략
- cloud-init 기본 포함
- SSH 공개키 주입 용이
- user, hostname, DNS, IP 설정 자동화 용이
- serial console 사용 용이
- disk grow 처리 용이
- VM 대량 생성 재현성 향상
- Terraform/Proxmox 자동화 적합

## ISO 이미지 대비 차이

| 구분         | cloud image                    | 일반 ISO                    |
| :----------- | :----------------------------- | :-------------------------- |
| 설치 방식    | 설치 완료 disk image import    | 설치 화면 기반 수동 설치    |
| 초기 설정    | cloud-init 주입                | 설치 후 수동 설정           |
| 자동화       | Terraform/Ansible 친화         | 추가 템플릿 작업 필요       |
| 대량 생성    | template clone 적합            | 반복 설치 부적합            |
| 커스터마이징 | cloud-init/Ansible 후처리 중심 | 설치 단계 커스터마이징 중심 |

## 최초 구축 흐름

- 1단계: Proxmox cluster 준비
- 2단계: Ceph RBD storage 준비
- 3단계: Ubuntu Noble cloud image 다운로드
- 4단계: Proxmox cloud-init template 생성
- 5단계: `env/onprem.tfvars` 작성
- 6단계: Terraform plan 검토
- 7단계: Terraform apply 담당자 1명 실행
- 8단계: Ansible `verify.yml` 검증

## Noble 템플릿 생성 예시

Proxmox node에서 실행.

```bash
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create 9000 \
  --name ubuntu-2404-noble-template \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26

qm importdisk 9000 noble-server-cloudimg-amd64.img ceph-rbd-team2
qm set 9000 --scsihw virtio-scsi-pci --scsi0 ceph-rbd-team2:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

## 템플릿 생성 주의

- `qm importdisk` 후 실제 disk 이름 확인 필요
- storage 이름 환경별 확인 필요
- `ceph-rbd-team2` 없으면 실제 RBD storage 이름 사용
- `local-lvm` 없으면 실제 cloud-init datastore 사용
- VMID `9000` 충돌 시 다른 template VMID 사용
- Terraform `template_vm_id` 값 동기화
- Terraform `template_node_name` 값 동기화

## 코드 위치

- Terraform: `infra/terraform/proxmox/`
- Terraform 변수 예시: `infra/terraform/proxmox/env/onprem.tfvars.example`
- Terraform 운영 변수: `infra/terraform/proxmox/env/onprem.tfvars`, gitignore 대상
- 기존 VM import 예시: `infra/terraform/proxmox/imports.existing.example`
- Ansible inventory: `infra/ansible/inventories/`
- Ansible playbook: `infra/ansible/playbooks/`
- Ansible role: `infra/ansible/roles/`

## Terraform 최초 설치 원칙

- 기본 경로: VM 신규 생성
- 생성 방식: Proxmox template full clone
- `imports.tf` 기본 미사용
- `terraform apply` 단독 실행 금지
- `terraform plan` diff 검토 후 담당자 1명 적용
- `prevent_destroy = true` 적용
- Proxmox 인증값 환경변수 사용
- 비밀번호, API token, private key 저장소 저장 금지

## 기존 VM import 의미

- 의미: 이미 존재하는 Proxmox VM을 Terraform state로 편입
- 목적: 기존 VM 재생성 방지
- 사용 시점: 수동 구축 후 Terraform 관리로 전환할 때
- 최초 설치 기본값: 사용 안 함
- 사용 파일: `imports.existing.example` -> `imports.tf` 복사
- `imports.tf`: gitignore 대상

## Ansible 원칙

- bastion 실행 우선
- `~/.ssh/kosa_iac` private key 로컬 보관
- `verify.yml` 우선 실행
- 변경 playbook 실행 전 `--check --diff` 실행
- `edge-haproxy.yml` 실행 시 TLS 인증서 존재 확인
- HAProxy stats password Ansible Vault 관리

## 실환경 참고값

아래 값은 2026-05-29 조회 기준 참고값. 최초 설치 기본값 아님.

| 구분                        | 값                                                |
| :-------------------------- | :------------------------------------------------ |
| Proxmox cluster             | `team2`                                           |
| Proxmox VE                  | `9.1.9`                                           |
| Proxmox node                | `kosa1`, `kosa2`, `kosa3`, `kosa4`                |
| 기존 template               | `ubuntu-2204-template`, VMID `9000`, node `kosa1` |
| 프로젝트 기준 신규 template | `ubuntu-2404-noble-template`                      |
| VM disk storage             | `ceph-rbd-team2`                                  |
| cloud-init storage          | `local-lvm`                                       |
| Kubernetes version          | `v1.30.14`                                        |
| containerd version          | `2.2.1`                                           |
| OS                          | `Ubuntu 24.04.4 LTS`                              |
| StorageClass                | `team2-rbd-block`                                 |
| MetalLB pool                | `172.16.23.50-172.16.23.99`                       |
| PXC status                  | `ready`, PXC `3`, ProxySQL `2`                    |
| ProxySQL endpoint           | `kosa-pxc-proxysql.pii-protected`                 |

## 제외 및 보류

- `pfsense-1`, `pfsense-2`: appliance 수동 운영
- `lb-1`, `lb-2`: linked clone disk path 추가 확인 필요
- `edge-haproxy`, `edge-haproxy2`: Ansible 관리 우선
- Kubernetes join 자동화: 별도 bootstrap 가이드 필요

## 검증 상태

- Proxmox API 조회: 완료
- QEMU guest agent 내부 조회: 완료
- Kubernetes API 조회: 완료
- Terraform fmt: 통과
- Terraform validate: 이전 구성 기준 통과
- Terraform plan: 이전 import 구성 기준 통과
- Ansible syntax/check: 로컬 Ansible 미설치로 미검증
- MkDocs build: 통과
