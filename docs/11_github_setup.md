# GitHub 저장소 설정

## 1. 필수 Secrets

| 이름                  | 값                                        |
| :-------------------- | :---------------------------------------- |
| `AWS_DEPLOY_ROLE_ARN` | Terraform output `github_deploy_role_arn` |

GitHub Actions 배포는 개인 AWS Access Key가 아니라 OIDC Role을 사용함. 팀원 개인 AWS 접근 계정과
GitHub Actions 배포 Role은 분리해서 관리함.

## 2. 수정이 필요한 플레이스홀더

### Terraform OIDC Trust Policy

`infra/terraform/env/dev.tfvars`의 다음 값을 실제 GitHub 저장소로 변경함.

```hcl
github_repository = "OWNER/REPO"
```

예시

```hcl
github_repository = "team-name/cloud-infra-platform"
```

### ECS Task Definition

`.github/task-definition.json`은 `__AWS_ACCOUNT_ID__` 플레이스홀더를 사용함. `Deploy to ECS`
workflow가 `aws sts get-caller-identity` 결과로 배포 시점에 치환하므로 저장소에 실제 AWS 계정 ID를
커밋하지 않음.

## 3. Branch Protection 권장

- `main` 직접 push 금지
- Pull Request 1명 이상 승인
- Terraform Check workflow 통과 필수
- 발표 기간 Day 14 이후에는 hotfix 외 변경 제한

## 4. Repository Description 예시

```text
13+3 day cloud infrastructure project: AWS ECS Fargate, ALB, ECR, GitHub Actions OIDC, CloudWatch, WAF
```
