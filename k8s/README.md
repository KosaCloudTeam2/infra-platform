# Kubernetes Optional Area

본 프로젝트의 MVP는 ECS Fargate임. 이 디렉터리는 발표 확장 또는 향후 EKS/온프레미스 Kubernetes
전환을 설명하기 위한 선택 영역임.

## 활용 시점

- ECS 대신 EKS를 도입할 때
- 온프레미스 Kubernetes와 AWS EKS를 분리 운영하는 Cloud Burst 구조를 검증할 때
- Argo CD 기반 GitOps 배포를 확장할 때

## 기본 원칙

- Stateless 앱부터 전환함
- Secret은 External Secrets Operator 또는 AWS Secrets Manager 연동을 사용함
- HPA/KEDA는 CloudWatch 또는 Prometheus 지표 기준을 명확히 둠
