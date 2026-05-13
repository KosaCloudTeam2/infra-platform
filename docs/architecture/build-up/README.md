# Build-up Guide (Demo Version)

> **주의**: 본 문서는 프로젝트의 **데모(Demo) 버전** 또는 **임시 구조**를 설명하고 있습니다. 향후
> 전체적인 프로젝트 구조가 변경될 예정이므로 참고하시기 바랍니다.

13일 시스템 구축 + 3일 발표 준비를 위한 역할 기반 상세 구현 가이드

---

## 1. Build-up 구조 (데모)

현재 데모 버전에서는 핵심 인프라와 스토리지 구성을 중심으로 진행합니다.

## 2. 문서 목록

| 담당                  | 핵심 문서                                                                                                                                          | 목표                                              |
| :-------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------ |
| Cloud / Network / IaC | [README.md](./README.md)                                                                                                                           | VPC, NLB, EC2 ASG, WAF, App/Data Private Subnet   |
| DB / Storage          | [RBD Register Guide](./_workspace/db_storage/01_rbd_register_guide.md), [Template Clone Guide](./_workspace/db_storage/02_template_clone_guide.md) | Percona Operator, XtraBackup, Ceph RGW            |
| CI/CD / App Runtime   | [README.md](./README.md)                                                                                                                           | GitHub Actions, Docker Hub, Argo CD, K8s manifest |

## 3. 공통 원칙

- DB 노드는 Data Private Subnet에만 배치함
- DB 관련 포트는 인터넷에 열지 않음
- Terraform `apply`는 담당자 1명만 수행함
- 콘솔 수작업이 발생하면 Runbook에 반영함
- Day 14부터 신규 기능 추가 금지
