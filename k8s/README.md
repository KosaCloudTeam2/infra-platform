# Kubernetes MVP Area

본 프로젝트의 MVP 기본 런타임은 온프레미스 Kubernetes임. 이 디렉터리는 Kubernetes manifest, Argo CD
Application, 향후 Helm chart를 관리하는 영역임.

## 활용 시점

- 온프레미스 Kubernetes에 앱을 배포할 때
- Argo CD 기반 GitOps 배포를 구성할 때
- AWS EC2 burst 영역과 같은 이미지 태그를 맞출 때

## 기본 원칙

- Stateless 앱부터 전환함
- GitHub Actions는 이미지 빌드와 push 담당
- Argo CD는 manifest sync 담당
- Secret은 External Secrets Operator 또는 AWS Secrets Manager 연동을 사용함
- HPA/KEDA는 CloudWatch 또는 Prometheus 지표 기준을 명확히 둠
