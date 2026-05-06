# ADR-009 Docker Hub 기반 MVP 이미지 저장소

## 상태

Accepted

## 날짜

2026-05-06

## 배경

MVP 배포 흐름은 GitHub 저장소, GitHub Actions, Argo CD, 온프레미스 Kubernetes를 기준으로 함. Elastic
Container Registry(ECR)는 AWS burst 영역과 잘 맞지만 저장 용량과 전송량에 따라 비용이 발생할 수
있음. 팀은 비용 부담을 줄이고 설정 난이도를 낮추기 위해 Docker Hub 또는 Private Registry 사용을
검토함.

## 결정

MVP 이미지 저장소는 Docker Hub를 기본값으로 사용함.

Private Registry 또는 Harbor는 온프레미스 독립 운영, 폐쇄망, 내부 이미지 보관 요구가 있을 때 선택
확장으로 분리함. ECR은 AWS-only 비교안 또는 AWS 배포를 강하게 묶어야 할 때의 대체안으로 유지함.

## 이유

- GitHub Actions에서 Docker Hub push 구성이 단순함
- Kubernetes image pull 구성이 단순함
- ECR 저장 비용 부담을 피할 수 있음
- Private Registry 직접 운영보다 발표 안정성이 높음
- 폐쇄망 요구가 생기면 Harbor 또는 GitLab Container Registry로 확장 가능함

## 영향

- CI/CD 문서의 기본 이미지 저장소는 Docker Hub 기준으로 설명함
- Docker Hub 인증 정보는 GitHub Secrets로 관리함
- Private Registry/Harbor는 선택 확장 문서에서 다룸
- Terraform과 workflow 기본 경로는 Docker Hub 이미지를 사용하는 EC2 ASG burst 기준으로 정리함
- ECR은 AWS-only 비교안이 필요할 때 별도 확장으로 검토함

## 후속 작업

- GitHub Actions Docker Hub push workflow 수동 실행 검증
- Kubernetes manifest image 경로와 Terraform `app_image` 값을 Docker Hub 기준으로 정리
- Private Registry/Harbor 도입 여부 팀 결정
