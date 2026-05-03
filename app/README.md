# App 연결 가이드

기존 애플리케이션을 이 디렉터리에 배치하거나, Dockerfile이 있는 실제 앱 경로를 GitHub Actions의
`docker build` 경로에 맞게 수정함.

## 1. 기본 조건

- 컨테이너가 `8080` 포트로 HTTP 요청을 수신함
- Health Check 경로는 `/health`를 권장함
- 로그는 stdout/stderr로 출력함
- Secret 값은 환경 변수로 주입받음

## 2. 임시 샘플 앱

이 저장소에는 배포 파이프라인 검증용 최소 Node.js 앱이 포함되어 있음. 이 앱은 최종 서비스가 아니라
ALB, ECR, ECS, GitHub Actions, CloudWatch 연동을 확인하기 위한 임시 배포 대상임.

실제 프로젝트 앱이 준비되면 이 샘플을 교체함. 교체 시 함께 확인할 항목은 다음과 같음.

- Dockerfile 위치와 GitHub Actions `docker build` 경로
- 컨테이너 포트와 Terraform `container_port`
- ALB Health Check 경로
- stdout/stderr 로그 출력 여부
- DB 접속 환경변수와 Secrets Manager 연동 방식
