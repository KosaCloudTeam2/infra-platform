# 배포 Runbook

> 아키텍처 상세 참조:
> [Runtime / CI-CD / Security](../architecture/details/runtime_cicd_security.md),
> [Ops Flow / Extensions](../architecture/details/ops_flow_and_extensions.md)

## 1. 사전 조건

- Docker Hub 계정 또는 조직 repository 준비 완료
- GitHub Repository Secret `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` 등록 완료
- 온프레미스 Kubernetes 클러스터 준비 완료
- Argo CD 설치와 Application 생성 완료
- Kubernetes manifest 또는 Helm chart image 경로 확정
- AWS burst 검증 시 Terraform plan/apply 완료
- AWS burst ASG refresh 검증 시 GitHub Actions OpenID Connect(OIDC) Role과 `AWS_DEPLOY_ROLE_ARN`
  등록 완료
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

## 3. Docker Hub 이미지 빌드

MVP 이미지 저장소는 Docker Hub임. `.github/workflows/build-image.yml`은 수동 실행
`workflow_dispatch`로 동작함.

1. GitHub Actions에서 `Build and Push Image` workflow 수동 실행
2. Docker Hub login 단계 성공 확인
3. Docker Hub에 `github.sha` 태그와 `latest` 태그 생성 확인
4. Kubernetes manifest 또는 Helm values의 image tag 갱신
5. AWS burst Launch Template에 사용할 `app_image` 값을 같은 태그 기준으로 맞춤

발표 안정화 기간에는 `latest`만 의존하지 않고 `github.sha` 태그를 캡처해 어떤 버전이 배포됐는지
설명할 수 있게 함.

## 4. Argo CD 설치 지침

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

## 5. Argo CD Application 생성 기준

Application은 `k8s/` manifest 또는 Helm chart 경로를 추적함. 실제 경로는 앱 manifest 확정 후 조정함.

GitOps 운영 기준:

- Git 저장소를 Kubernetes 배포 상태의 기준으로 둠
- 클러스터에서 직접 `kubectl edit`로 수정한 내용은 임시 조치로만 기록
- 환경별 설정은 `values-dev.yaml`, `values-onprem.yaml`, `values-cloud.yaml`처럼 분리 가능
- Day 13 전에는 수동 sync를 기본으로 둠
- 발표 당일에는 수동 sync 또는 auto-sync 중 하나로 고정함
- Reloader Operator, Argo Rollouts, Blue/Green, Canary는 선택 확장

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

## 6. Argo CD GitOps 배포

1. Docker Hub 이미지 build/push 성공 확인
2. Kubernetes manifest 또는 Helm values image tag 갱신 확인
3. Argo CD Application sync 실행
4. Kubernetes Deployment rollout 상태 확인
5. Service 또는 Ingress Health Check 확인
6. 앱에서 ProxySQL endpoint 접속 확인

확인 명령:

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

## 7. AWS burst ASG refresh

AWS burst 영역은 ECS가 아니라 EC2 Auto Scaling Group과 Launch Template으로 구성함. 새 Docker Hub
이미지를 burst EC2에 반영해야 하면 `Refresh AWS Burst ASG` workflow를 수동 실행함.

사전 확인:

- Terraform output `app_autoscaling_group_name` 확인
- `infra/terraform/env/dev.tfvars`의 `app_image`가 발표에 사용할 태그와 일치
- `AWS_DEPLOY_ROLE_ARN` Secret 등록 완료
- ASG `app_min_size`, `app_desired_capacity`, `app_max_size`가 비용 제한과 일치

실행:

1. GitHub Actions에서 `Refresh AWS Burst ASG` workflow 수동 실행
2. 필요 시 `asg_name` 입력값에 Terraform output `app_autoscaling_group_name` 입력
3. AWS Console 또는 CLI에서 instance refresh 진행 상태 확인
4. ALB Target Group Health가 `healthy`인지 확인
5. ALB DNS로 `/health` 응답 확인

확인 명령:

```powershell
aws autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names <ASG_NAME> `
  --region ap-northeast-2
```

```powershell
aws elbv2 describe-target-health `
  --target-group-arn <TARGET_GROUP_ARN> `
  --region ap-northeast-2
```

## 8. 정리 명령

Argo CD 정리:

```powershell
kubectl delete application <app-name> -n argocd
kubectl delete namespace argocd
```

주의:

- Application 삭제 전 Argo CD가 관리하던 앱 리소스 삭제 여부 확인
- `prune` 활성화 상태에서는 Git에서 삭제한 리소스가 클러스터에서도 삭제됨
- AWS 리소스 정리는 `docs/09_cleanup_plan.md` 기준으로 담당자 1명만 수행함

## 9. 완료 기준

- Docker Hub에 발표 대상 이미지 태그가 있음
- Argo CD Application `Synced` 상태
- Argo CD Application `Healthy` 상태
- Kubernetes Deployment rollout 성공
- AWS burst ASG 사용 시 Target Health가 `healthy`임
- ALB URL 또는 온프레미스 Ingress URL로 앱 응답 확인 가능함
- 배포 실패 시 이전 Git revision 또는 image tag로 복구 가능함
