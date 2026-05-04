# Architecture Decision Records

이 디렉터리는 프로젝트의 주요 설계 결정을 ADR(Architecture Decision Record) 형식으로 기록함.

Change Log가 “무엇이 바뀌었는가”를 기록한다면, ADR은 “왜 그렇게 결정했는가”를 기록함.

## 목록

| ID      | 제목                                                                                              | 상태       | 날짜       | 요약                                                                                      |
| :------ | :------------------------------------------------------------------------------------------------ | :--------- | :--------- | :---------------------------------------------------------------------------------------- |
| ADR-001 | [ECS Fargate를 MVP 런타임으로 선택](./ADR-001-ecs-fargate-mvp.md)                                 | Superseded | 2026-05-03 | ADR-007 채택 이후 ECS Fargate는 AWS-only fallback 또는 비교안으로 유지                    |
| ADR-002 | [RDS 제외와 PXC/ProxySQL 채택](./ADR-002-rds-exclusion-pxc-proxysql.md)                           | Accepted   | 2026-05-03 | 직접 운영 DB 경험과 장애/백업 시연을 위해 EC2 기반 PXC와 ProxySQL을 사용                  |
| ADR-003 | [ProxySQL 1대 MVP와 이중화 확장 경로](./ADR-003-proxysql-single-node-mvp.md)                      | Accepted   | 2026-05-03 | ProxySQL 1대는 MVP 기준이며 단일 장애점으로 명시, 여유 시 2대 + Internal NLB로 확장       |
| ADR-004 | [Proxmox 기반 Ceph 스토리지 역할 분리](./ADR-004-proxmox-ceph-storage-role.md)                    | Accepted   | 2026-05-03 | Proxmox/Ceph는 온프레미스 스토리지 계층이고 AWS 앱은 RGW S3 API로만 접근                  |
| ADR-005 | [GitHub Actions OIDC 기반 배포](./ADR-005-github-actions-oidc.md)                                 | Accepted   | 2026-05-03 | 장기 AWS Access Key 없이 GitHub Actions가 임시 권한으로 ECR/ECS 배포 수행                 |
| ADR-006 | [MkDocs navigation 기반 문서 사이트](./ADR-006-mkdocs-docs-navigation.md)                         | Accepted   | 2026-05-03 | 문서 파일 대이동보다 `docs/index.md`와 `mkdocs.yml` nav로 탐색성 확보                     |
| ADR-007 | [비용 우선 하이브리드 Kubernetes와 AWS EC2 버스팅](./ADR-007-hybrid-kubernetes-cloud-bursting.md) | Accepted   | 2026-05-04 | EKS 비용을 피하고 온프레미스 Kubernetes + AWS EC2 Auto Scaling/ALB burst 구조를 우선 채택 |
| ADR-008 | [Argo CD 기반 GitOps 배포 MVP 포함](./ADR-008-argocd-gitops-mvp.md)                              | Accepted   | 2026-05-04 | GitHub Actions는 이미지 빌드, Argo CD는 온프레미스 Kubernetes manifest 동기화 담당        |

## ADR 작성 템플릿

```md
# ADR-000: 결정 제목

## 상태

Proposed / Accepted / Superseded

## 날짜

YYYY-MM-DD

## 배경

왜 결정이 필요했는지 작성함.

## 결정

무엇을 선택했는지 작성함.

## 대안

검토한 다른 선택지를 작성함.

## 영향

좋아지는 점과 감수해야 하는 점을 작성함.

## 관련 문서

- ...
```
