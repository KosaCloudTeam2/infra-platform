# 발표 자료 목차

> 다이어그램 정본은 기술 문서(`docs/01_architecture.md`, `docs/architecture/details/*`)를 기준으로
> 유지함. 발표 자료는 요약/시연 흐름 전달용으로 사용함.

## 1. 제목

Cloud Infra Deployment Platform: 안전하고 반복 가능한 컨테이너 배포 인프라

## 2. 슬라이드 구성

1. 프로젝트 배경과 목표
2. 13+3 일정과 팀 역할
3. 전체 아키텍처
4. 네트워크 설계
5. 온프레미스 Kubernetes 런타임
6. GitHub Actions와 Argo CD 기반 GitOps 배포
7. IAM OIDC와 보안 정책
8. CloudWatch 또는 Prometheus/Grafana 기반 관측성
9. 장애 대응 및 롤백 시연
10. 비용 최적화와 한계
11. 확장 계획
12. Q&A

원본 발표 자료는 [presentation.md](./presentation.md)에서 관리하고, PDF는 `pnpm run slides:pdf` 또는
`gen-pdf.ps1`로 생성함.

## 3. 시연 순서

1. GitHub Actions 이미지 빌드 실행
2. Docker Hub 이미지 확인
3. Argo CD Application sync 확인
4. Kubernetes rollout 확인
5. Service 또는 Ingress URL 접속
6. 장애 유도
7. 롤백 또는 자동 복구 확인
8. CloudWatch 또는 Grafana 지표 확인
