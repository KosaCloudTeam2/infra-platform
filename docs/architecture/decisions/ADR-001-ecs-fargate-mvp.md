# ADR-001: ECS Fargate를 MVP 런타임으로 선택

## 상태

Superseded by [ADR-007](./ADR-007-hybrid-kubernetes-cloud-bursting.md) and
[ADR-008](./ADR-008-argocd-gitops-mvp.md)

## 날짜

2026-05-03

## 배경

13일 안에 네트워크, 배포, 보안, 관측성, 장애 대응까지 연결해야 함. Kubernetes(EKS)는 포트폴리오
관점에서 장점이 있지만, 클러스터 운영, Ingress, GitOps, 관측성까지 안정화하려면 일정 부담이 큼.

## 결정

MVP 애플리케이션 런타임은 AWS ECS Fargate로 구성함.

2026-05-04에 비용 우선 요구와 Argo CD GitOps MVP 포함이 확정되면서 이 결정은
[ADR-007](./ADR-007-hybrid-kubernetes-cloud-bursting.md),
[ADR-007](./ADR-007-hybrid-kubernetes-cloud-bursting.md)과
[ADR-008](./ADR-008-argocd-gitops-mvp.md)로 대체됨. ECS Fargate는 MVP에서 제외하고 비용/운영 편의성
비교안으로만 유지함.

## 대안

- EKS 기반 Kubernetes
- EC2 직접 배포
- App Runner 또는 Elastic Beanstalk

## 영향

장점:

- ALB, ECR, CloudWatch, Auto Scaling과 연결이 단순함
- 서버 패치와 컨테이너 호스트 관리 부담이 작음
- 13일 일정에서 배포 자동화와 장애 대응 시연까지 도달하기 쉬움

감수할 점:

- Kubernetes 운영 경험을 직접 보여주기는 어려움
- 복잡한 서비스 메시와 EKS Ingress 시연은 선택 확장으로 남김
- GitOps 시연은 ADR-008 이후 Argo CD 기반 MVP로 이동

## 관련 문서

- [Architecture](../../01_architecture.md)
- [Implementation Scope](../../04_implementation_scope.md)
- [CI/CD App Runtime Implementation](../build-up/03_cicd_app_runtime_implementation.md)
