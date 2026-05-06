# GitHub 저장소 설정

## 1. 필수 Secrets

| 이름                  | 값                                       |
| :-------------------- | :--------------------------------------- |
| `DOCKERHUB_USERNAME`  | Docker Hub 사용자 또는 조직 계정명       |
| `DOCKERHUB_TOKEN`     | Docker Hub Access Token                  |
| `AWS_DEPLOY_ROLE_ARN` | AWS burst ASG refresh용 Terraform output |

MVP 이미지 push는 Docker Hub Secret을 사용함. AWS burst ASG instance refresh는 개인 AWS Access Key가
아니라 OpenID Connect(OIDC) Role을 사용함. 팀원 개인 AWS 접근 계정과 GitHub Actions 배포 Role은
분리해서 관리함.

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

### AWS burst app image

`infra/terraform/env/dev.tfvars`의 `app_image` 값을 실제 Docker Hub 이미지로 변경함.

```hcl
app_image = "DOCKERHUB_USERNAME/cloud-infra-app:latest"
```

`DOCKERHUB_USERNAME`은 GitHub Secret 값과 일치해야 하며, 발표 전에는 `github.sha` 태그와 `latest`
태그 중 어떤 값을 AWS Launch Template에 넣을지 하나로 고정함.

## 3. Branch Protection 권장

- `main` 직접 push 금지
- Pull Request 1명 이상 승인
- Terraform Check workflow 통과 필수
- 발표 기간 Day 14부터는 hotfix 외 변경 제한

## 4. Deploy Workflow 활성화 기준

현재 AWS deploy workflow는 push 실패와 비용 증가를 막기 위해 수동 실행만 허용함. Argo CD 기반 GitOps
배포를 기본 경로로 검증하고, AWS burst ASG refresh는 아래 조건 확인 후 수동 실행함.

- Terraform apply 완료
- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` Secret 등록 완료
- `AWS_DEPLOY_ROLE_ARN` Secret 등록 완료
- OIDC Trust Policy의 `github_repository` 값이 실제 저장소와 일치
- 수동 `Refresh AWS Burst ASG` workflow 1회 성공
- Docker Hub Repository와 AWS burst용 ALB/ASG 리소스 생성 확인

발표 기간에는 `Refresh AWS Burst ASG` workflow를 수동 실행으로 유지함. 자동 refresh는 잘못된
이미지가 바로 burst 영역으로 반영될 수 있으므로 선택 확장으로 둠.

## 5. Repository Description 예시

```text
13+3 day hybrid infrastructure project: Kubernetes, Argo CD, AWS EC2 burst, ALB, Docker Hub, GitHub Actions
```
