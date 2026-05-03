# Git 작업 전략

## 1. 브랜치

- `main`: 발표 가능한 안정 상태
- `feature/network-iac`: VPC/ALB/SG
- `feature/ecs-runtime`: ECS/ECR/Task Definition
- `feature/cicd-security`: GitHub Actions/IAM/WAF
- `feature/observability`: CloudWatch/Alarm/Runbook
- `docs/presentation`: 발표 자료

## 2. 커밋 메시지

```text
type(scope): summary
```

예시

- `feat(terraform): add vpc and alb baseline`
- `feat(ecs): add fargate service definition`
- `ci(github): add oidc based deploy workflow`
- `docs(plan): add 13 plus 3 schedule`

## 3. PR 기준

- 변경 목적이 명확함
- 관련 문서가 함께 갱신됨
- Terraform 변경 시 `fmt/validate/plan` 결과를 남김
- 배포 관련 변경 시 롤백 방법을 적음
- GitHub 공유 정책은 [Repository Sharing Policy](./12_repository_sharing_policy.md)를 따름
