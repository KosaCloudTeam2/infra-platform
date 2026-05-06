# GitHub 저장소 설정

## 1. 필수 Secrets

| 이름                  | 값                                   |
| :-------------------- | :----------------------------------- |
| `DOCKERHUB_USERNAME`  | Docker Hub 사용자 또는 조직 계정명   |
| `DOCKERHUB_TOKEN`     | Docker Hub Access Token              |
| `AWS_DEPLOY_ROLE_ARN` | AWS-only fallback용 Terraform output |

MVP 이미지 push는 Docker Hub Secret을 사용함. AWS-only fallback 배포는 개인 AWS Access Key가 아니라
OpenID Connect(OIDC) Role을 사용함. 팀원 개인 AWS 접근 계정과 GitHub Actions 배포 Role은 분리해서
관리함.

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

### Elastic Container Service(ECS) fallback Task Definition

`.github/task-definition.json`은 AWS-only fallback 검증용 파일임. `__AWS_ACCOUNT_ID__`
플레이스홀더를 사용하며, `Deploy to ECS` workflow가 `aws sts get-caller-identity` 결과로 배포 시점에
치환하므로 저장소에 실제 AWS 계정 ID를 커밋하지 않음.

## 3. Branch Protection 권장

- `main` 직접 push 금지
- Pull Request 1명 이상 승인
- Terraform Check workflow 통과 필수
- 발표 기간 Day 14 이후에는 hotfix 외 변경 제한

## 4. Deploy Workflow 활성화 기준

현재 AWS deploy workflow는 push 실패 방지를 위해 수동 실행만 허용함. Argo CD 기반 GitOps 배포를 기본
경로로 검증하고, AWS-only fallback 자동 배포는 아래 조건 확인 후 활성화함.

- Terraform apply 완료
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` Secret 등록 완료
- `AWS_DEPLOY_ROLE_ARN` Secret 등록 완료
- OIDC Trust Policy의 `github_repository` 값이 실제 저장소와 일치
- 수동 `Deploy to ECS` 또는 해당 fallback workflow 1회 성공
- Docker Hub Repository와 AWS fallback용 ECS/ALB 리소스 생성 확인

fallback 자동 배포가 필요하면 `.github/workflows/deploy.yml`의 `push` 트리거 주석을 복원함.

## 5. Repository Description 예시

```text
13+3 day hybrid infrastructure project: Kubernetes, Argo CD, AWS EC2 burst, ALB, Docker Hub, GitHub Actions
```
