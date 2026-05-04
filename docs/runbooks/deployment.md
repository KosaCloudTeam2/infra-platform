# 배포 Runbook

## 1. 사전 조건

- AWS CLI 인증 완료
- Terraform plan/apply 완료
- ECR Repository 생성 완료
- GitHub Actions OIDC Role 생성 완료
- 기존 앱 Dockerfile 준비 완료

## 2. 로컬 이미지 검증

```powershell
docker build -t cloud-infra-app:local ./app
docker run --rm -p 8080:8080 cloud-infra-app:local
```

브라우저 또는 CLI로 Health Check 확인

```powershell
curl http://localhost:8080/health
```

## 3. GitHub Actions 배포

현재 `Deploy to ECS` workflow는 AWS OIDC Role과 GitHub Secret 준비 전 push 실패를 막기 위해 수동 실행만
허용함.

1. Terraform apply와 GitHub Secret 설정 완료 확인
2. GitHub Actions에서 `Deploy to ECS` workflow 수동 실행
3. ECR 이미지 태그 확인
4. ECS Service Deployment 상태 확인
5. ALB Target Group Health Check 확인

## 4. 자동 배포 재활성화 기준

아래 조건이 모두 충족되면 `main` push 자동 배포를 다시 활성화할 수 있음.

- Terraform apply 완료
- ECR Repository 생성 확인
- ECS Cluster, Service, Task Execution Role 생성 확인
- GitHub OIDC Provider와 `GitHubDeployRole` 생성 확인
- `infra/terraform/env/dev.tfvars`의 `github_repository`가 실제 저장소명으로 설정됨
- GitHub Repository Secret `AWS_DEPLOY_ROLE_ARN` 등록 완료
- `Deploy to ECS` workflow 수동 실행 1회 성공

재활성화 절차:

1. `.github/workflows/deploy.yml`의 주석 처리된 `push` 트리거 복원
2. PR로 workflow 변경 리뷰
3. `main` 병합 후 자동 배포 실행 확인
4. 실패 시 push 트리거를 다시 비활성화하고 수동 실행 기준으로 복구

복원할 트리거:

```yaml
on:
  push:
    branches:
      - main
  workflow_dispatch:
```

## 5. 수동 배포 확인 명령

```powershell
aws ecs describe-services `
  --cluster cloud-infra-dev-cluster `
  --services cloud-infra-dev-app `
  --region ap-northeast-2
```

```powershell
aws elbv2 describe-target-health `
  --target-group-arn <TARGET_GROUP_ARN> `
  --region ap-northeast-2
```

## 6. 완료 기준

- ECS Service `runningCount`가 `desiredCount`와 동일함
- Target Health가 `healthy`임
- ALB URL로 앱 응답 확인 가능함
- CloudWatch Logs에 신규 컨테이너 로그가 기록됨
