# 배포 Runbook

## 1. 사전 조건

- AWS Command Line Interface(CLI) 인증 완료
- Terraform plan/apply 완료
- Elastic Container Registry(ECR) Repository 생성 완료
- GitHub Actions OpenID Connect(OIDC) Role 생성 완료
- 온프레미스 Kubernetes 클러스터 준비 완료
- Argo CD 설치와 Application 생성 완료
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

## 3. Argo CD 설치 지침

온프레미스 Kubernetes 클러스터에서 1회 수행함.

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd
```

로컬 접속 확인:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

브라우저 접속:

```text
https://localhost:8080
```

강의 실습에서는 NodePort 방식으로 Argo CD UI에 접속했음. 프로젝트에서도 발표 환경에서 port-forward
사용이 어려울 때만 NodePort 방식을 적용함.

```powershell
kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"NodePort\"}}'
kubectl get svc argocd-server -n argocd
```

NodePort 사용 기준:

- 사설망 또는 제한된 실습망에서만 사용
- 인터넷 전체 공개 금지
- 발표 종료 후 ClusterIP 복구 또는 Argo CD 접근 경로 차단

초기 admin 비밀번호 확인:

```powershell
kubectl get secret argocd-initial-admin-secret `
  -n argocd `
  -o jsonpath="{.data.password}" | %{ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

초기 설정 기준:

- 초기 admin 비밀번호 저장소 기록 금지
- 최초 로그인 후 admin 비밀번호 변경
- 비밀번호 변경 후 `argocd-initial-admin-secret` 삭제
- 발표용 접속은 port-forward 또는 제한된 내부망 접속 우선
- Argo CD Server를 인터넷에 직접 공개하지 않음

초기 비밀번호 Secret 삭제:

```powershell
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## 4. Argo CD Application 생성 기준

Application은 `k8s/` manifest 또는 Helm chart 경로를 추적함. 실제 경로는 앱 manifest 확정 후 조정함.

예시:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloud-infra-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<OWNER>/<REPO>.git
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: app
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

적용:

```powershell
kubectl apply -f k8s/argocd-application.yaml
kubectl get application -n argocd
```

Sync 정책:

- Day 13 전: 수동 sync 기본
- 수동 sync 1회 이상 성공 후 auto-sync 전환 검토
- 발표 당일: 수동 sync 또는 auto-sync 중 하나로 고정
- `CreateNamespace=true`: destination namespace가 없으면 생성
- `prune`: Git에서 삭제된 리소스를 클러스터에서도 삭제
- `selfHeal`: 클러스터 직접 변경을 Git 상태로 복구

자동 sync 예시:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

자동 sync는 실수한 commit도 반영될 수 있으므로 MVP 안정화 전에는 수동 sync를 기본값으로 둠.

## 5. Argo CD GitOps 배포

MVP 배포 기준은 GitHub Actions 이미지 빌드와 Argo CD GitOps 동기화임.

1. GitHub Actions에서 이미지 build/push 성공 확인
2. Kubernetes manifest 또는 Helm values image tag 갱신 확인
3. Argo CD Application sync 실행
4. ECR 이미지 태그 확인
5. Kubernetes Deployment rollout 상태 확인
6. Service 또는 Ingress Health Check 확인

## 6. ECS fallback 배포

현재 `Deploy to ECS` workflow는 AWS OIDC Role과 GitHub Secret 준비 전 push 실패를 막기 위해 수동
실행만 허용함. 이 workflow는 AWS-only fallback 검증이 필요할 때 사용함.

1. Terraform apply와 GitHub Secret 설정 완료 확인
2. GitHub Actions에서 `Deploy to ECS` workflow 수동 실행
3. ECR 이미지 태그 확인
4. ECS Service Deployment 상태 확인
5. ALB Target Group Health Check 확인

## 7. ECS 자동 배포 재활성화 기준

아래 조건이 모두 충족되면 `main` push 자동 배포를 다시 활성화할 수 있음.

- Terraform apply 완료
- ECR Repository 생성 확인
- Elastic Container Service(ECS) Cluster, Service, Task Execution Role 생성 확인
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

## 8. Argo CD 확인 명령

```powershell
kubectl get application -n argocd
kubectl describe application <app-name> -n argocd
kubectl rollout status deployment/<app-deployment-name> -n <app-namespace>
```

Drift 감지와 Self Heal 검증:

```powershell
kubectl scale deployment/<app-deployment-name> --replicas=5 -n <app-namespace>
kubectl get application <app-name> -n argocd
kubectl get deployment/<app-deployment-name> -n <app-namespace> -w
```

확인 기준:

- 수동 sync 모드: Application이 `OutOfSync`로 표시됨
- `selfHeal: true`: replica 수가 Git 선언값으로 복구됨

정리 명령:

```powershell
kubectl delete application <app-name> -n argocd
kubectl delete namespace argocd
```

주의:

- Application 삭제 전 Argo CD가 관리하던 앱 리소스 삭제 여부 확인
- `prune` 활성화 상태에서는 Git에서 삭제한 리소스가 클러스터에서도 삭제됨

## 9. ECS 수동 배포 확인 명령

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

## 10. 완료 기준

- Argo CD Application `Synced` 상태
- Argo CD Application `Healthy` 상태
- Kubernetes Deployment rollout 성공
- AWS-only ECS fallback 사용 시 ECS Service `runningCount`가 `desiredCount`와 동일함
- Target Health가 `healthy`임
- ALB URL로 앱 응답 확인 가능함
- CloudWatch Logs에 신규 컨테이너 로그가 기록됨
