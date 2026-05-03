# 발표 자료 목차

## 1. 제목

Cloud Infra Deployment Platform: 안전하고 반복 가능한 컨테이너 배포 인프라

## 2. 슬라이드 구성

1. 프로젝트 배경과 목표
2. 13+3 일정과 팀 역할
3. 전체 아키텍처
4. 네트워크 설계
5. ECS Fargate 런타임
6. GitHub Actions 기반 자동 배포
7. IAM OIDC와 보안 정책
8. CloudWatch 기반 관측성
9. 장애 대응 및 롤백 시연
10. 비용 최적화와 한계
11. 확장 계획
12. Q&A

원본 발표 자료는 [presentation.md](./presentation.md)에서 관리하고, PDF는 `pnpm run slides:pdf` 또는
`gen-pdf.ps1`로 생성함.

## 3. 시연 순서

1. GitHub Actions 배포 실행
2. ECR 이미지 확인
3. ECS Service Deployment 확인
4. ALB URL 접속
5. 장애 유도
6. 롤백 또는 자동 복구 확인
7. CloudWatch Logs/Alarm 확인
