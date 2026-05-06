# ADR-008: Argo CD 기반 GitOps 배포 MVP 포함

## 상태

Accepted

## 날짜

2026-05-04

## 배경

프로젝트 MVP 기본 런타임은 온프레미스 Kubernetes임. GitHub Actions만으로 `kubectl apply`를 수행하면
배포 자동화는 가능하지만, Kubernetes 운영 포트폴리오에서 GitOps 흐름을 설명하기 어려움.

## 결정

Argo CD를 MVP 배포 경로에 포함함. GitHub Actions는 Docker 이미지 빌드와 Docker Hub push를 담당하고,
Argo CD는 Git 저장소의 Kubernetes manifest 또는 Helm chart를 온프레미스 Kubernetes에 동기화함.

AWS ECS 배포 workflow는 AWS-only fallback 또는 비교안으로 유지함.

## 대안

- GitHub Actions에서 직접 `kubectl apply`
- Helm CLI 기반 수동 배포
- Flux CD 기반 GitOps
- Argo CD를 선택 확장으로 유지

## 영향

장점:

- Kubernetes GitOps 배포 흐름 설명 가능
- Git 상태와 클러스터 상태 차이 확인 가능
- 배포 이력과 rollback 설명 용이

감수할 점:

- Argo CD 설치와 접속 경로 구성 필요
- Application sync 실패 대응 Runbook 필요
- admin 초기 비밀번호, repository credential 관리 필요
- Day 13 전 수동 sync와 auto-sync 중 하나 결정 필요

## 관련 문서

- [Architecture](../../01_architecture.md)
- [Implementation Scope](../../04_implementation_scope.md)
- [Deployment Runbook](../../runbooks/deployment.md)
- [CI/CD App Runtime Build-up](../build-up/03_cicd_app_runtime.md)
