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

1. `main` 브랜치에 PR 병합
2. `Deploy to ECS` workflow 실행 확인
3. ECR 이미지 태그 확인
4. ECS Service Deployment 상태 확인
5. ALB Target Group Health Check 확인

## 4. 수동 배포 확인 명령

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

## 5. 완료 기준

- ECS Service `runningCount`가 `desiredCount`와 동일함
- Target Health가 `healthy`임
- ALB URL로 앱 응답 확인 가능함
- CloudWatch Logs에 신규 컨테이너 로그가 기록됨
