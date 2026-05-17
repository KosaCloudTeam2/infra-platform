# 07. GitOps & ArgoCD

> **이 챕터에서 다루는 것**
> "git이 진실, 클러스터는 그것의 그림자"라는 GitOps 철학, ArgoCD 컴포넌트, App-of-Apps 패턴으로 수십 개 앱을 단일 root에서 관리하는 법, 그리고 cert-manager/Helm 등이 자동 채우는 필드를 ignoreDifferences로 처리하는 실전 노하우.

## 목차
1. [이론: GitOps](#1-이론-gitops)
2. [ArgoCD 컴포넌트](#2-argocd-컴포넌트)
3. [App-of-Apps 패턴](#3-app-of-apps-패턴)
4. [Helm vs raw manifest](#4-helm-vs-raw-manifest)
5. [Sync 상태 4가지](#5-sync-상태-4가지)
6. [ignoreDifferences 필수 케이스](#6-ignoredifferences-필수-케이스)
7. [우리 GitOps repo 구조](#7-우리-gitops-repo-구조)
8. [구축 절차](#8-구축-절차)
9. [운영 치트시트](#9-운영-치트시트)
10. [트러블슈팅](#10-트러블슈팅)
11. [다음 챕터](#11-다음-챕터)

---

## 1. 이론: GitOps

### 1.1 GitOps의 4가지 원칙 (CNCF)

1. **선언적 (Declarative)**: 시스템 상태를 코드로 표현 (YAML)
2. **버전 관리됨 (Versioned, Immutable)**: 모든 변경이 git history
3. **자동 pull**: 에이전트가 git을 watch + 자동 적용
4. **지속적 reconciliation**: drift를 자동 감지+복구

### 1.2 Push 모델 vs Pull 모델

```
Push 모델 (전통 CI/CD):
  CI 서버 ──(kubectl apply)──► 클러스터
  
  문제:
  - CI가 클러스터 자격증명을 보관 (유출 위험)
  - git 상태 ≠ 클러스터 실제 상태 (drift 모름)
  - 변경 audit 어려움

Pull 모델 (GitOps):
  CI 서버 ──(git push)──► git repo
                              ↑ watch
                          ArgoCD (클러스터 안에서 pull)
                              │
                              ▼
                          kubectl apply (자기 자신 클러스터에)
  
  장점:
  - CI는 클러스터 권한 X
  - git이 single source of truth
  - drift 자동 감지+복구
```

### 1.3 GitOps의 효과

- **롤백**: `git revert` 한 줄
- **감사 (Audit)**: 누가 언제 무엇을 바꿨나 git log
- **DR (Disaster Recovery)**: 클러스터 날아가도 git만 있으면 재현
- **PR-driven 변경**: 코드 리뷰 → 자동 배포
- **다중 클러스터**: 같은 git을 여러 클러스터가 watch (multi-env, multi-cloud)

---

## 2. ArgoCD 컴포넌트

```
┌──────────────────── ArgoCD Cluster ────────────────────┐
│                                                        │
│  ┌─────────────────┐   ┌──────────────────┐           │
│  │ argocd-server   │   │ argocd-repo-     │           │
│  │ (API + Web UI)  │   │ server           │           │
│  │                 │   │ (git clone,      │           │
│  │ :443 HTTPS      │   │  helm template,  │           │
│  └─────────────────┘   │  kustomize 등)   │           │
│                        └──────────────────┘           │
│                                                        │
│  ┌─────────────────┐   ┌──────────────────┐           │
│  │ argocd-         │   │ argocd-          │           │
│  │ application-    │   │ applicationset-  │           │
│  │ controller      │   │ controller       │           │
│  │ (reconcile)     │   │ (generator)      │           │
│  └─────────────────┘   └──────────────────┘           │
│                                                        │
│  ┌─────────────────┐   ┌──────────────────┐           │
│  │ argocd-notif-   │   │ argocd-          │           │
│  │ controller      │   │ dex-server       │           │
│  │ (Slack 등 알림) │   │ (OIDC)           │           │
│  └─────────────────┘   └──────────────────┘           │
│                                                        │
│  ┌─────────────────┐                                  │
│  │ argocd-redis    │                                  │
│  │ (캐시)          │                                  │
│  └─────────────────┘                                  │
└────────────────────────────────────────────────────────┘
```

핵심:
- **application-controller**: git ↔ cluster reconciliation (가장 중요)
- **repo-server**: git에서 manifest 가져와 렌더링 (Helm template 등)
- **server**: API/UI

### 2.1 Application CRD

ArgoCD가 관리하는 단위. `Application` 리소스:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticket-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:kosacloudteam2/kosa-gitops.git
    targetRevision: main
    path: apps/ticket-app
  destination:
    server: https://kubernetes.default.svc    # 자기 자신 클러스터
    namespace: kosa-tickets
  syncPolicy:
    automated:
      prune: true       # git에서 삭제된 리소스를 cluster에서도 삭제
      selfHeal: true    # 수동 cluster 변경을 git 상태로 자동 복구
    syncOptions:
      - CreateNamespace=true
```

---

## 3. App-of-Apps 패턴

### 3.1 문제

앱이 30개면 Application 리소스 30개. 추가/제거 시 수동.

### 3.2 해법

하나의 **root Application**이 다른 Application들을 정의한 디렉토리를 watch:

```
[root-app] ──watch──► apps/_applications/ 디렉토리
                       ├── cert-manager.yaml      (Application)
                       ├── monitoring.yaml        (Application)
                       ├── harbor.yaml            (Application)
                       ├── jenkins.yaml           (Application)
                       └── ticket-app.yaml        (Application)
                            │
                            └─watch─► apps/ticket-app/ (실제 manifest)
```

새 앱 추가: `_applications/`에 yaml 한 개 commit → root-app이 감지 → 새 Application 생성 → 그것이 또 자기 path를 watch.

### 3.3 root-app 정의

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:kosacloudteam2/kosa-gitops.git
    targetRevision: main
    path: apps/_applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

이거 한 번만 손으로 `kubectl apply` 하면 나머지는 git으로 관리.

---

## 4. Helm vs raw manifest

### 4.1 Helm chart 소스

```yaml
source:
  repoURL: https://charts.jetstack.io
  chart: cert-manager
  targetRevision: v1.15.0
  helm:
    values: |
      installCRDs: true
      nodeSelector:
        workload-type: system
```

장점: 외부 chart의 release 그대로 사용, values만 우리 환경에 맞춤.

### 4.2 raw manifest 소스

```yaml
source:
  repoURL: git@github.com:kosacloudteam2/kosa-gitops.git
  targetRevision: main
  path: apps/ticket-app    # YAML 파일들이 있는 디렉토리
```

장점: 완전 통제, custom 리소스.

### 4.3 우리 사용 패턴

| 앱 | 방식 | 이유 |
|---|---|---|
| cert-manager | Helm | 공식 chart |
| monitoring (kube-prom) | Helm | community standard |
| redis (Sentinel) | Helm (bitnami) | 검증된 chart |
| harbor | Helm (공식) | 복잡, chart 활용 |
| jenkins | Helm (공식) | 동일 |
| ticket-app | raw | 우리 앱 |
| cert-manager-issuer | raw | CRD라 단순 |

---

## 5. Sync 상태 4가지

ArgoCD UI에서 각 Application에 두 상태:

| Sync Status | 의미 |
|---|---|
| **Synced** | git 상태 = cluster 상태 |
| **OutOfSync** | git ≠ cluster (drift 발생) |

| Health Status | 의미 |
|---|---|
| **Healthy** | 워크로드 정상 (Pod Running, Service Endpoint 있음, ...) |
| **Progressing** | 변경 중 (Deployment rolling update 중 등) |
| **Degraded** | 비정상 (Pod CrashLoop 등) |
| **Missing** | 리소스가 cluster에 없음 |

조합 예:
- `Synced + Healthy`: 가장 좋은 상태
- `OutOfSync + Healthy`: 방금 git 변경, 곧 sync 됨 (selfHeal)
- `Synced + Degraded`: git대로 적용했는데 워크로드가 망가짐 (이미지 문제 등)
- `OutOfSync + Healthy (오래 지속)`: drift 발생 + ignoreDifferences 부족 (아래 6절)

---

## 6. ignoreDifferences 필수 케이스

### 6.1 왜 필요한가

git에 없는 필드를 K8s API/다른 컨트롤러가 자동 채움 → 영원히 OutOfSync.

### 6.2 우리가 실제로 만난 케이스

#### a) StatefulSet.spec.volumeClaimTemplates (immutable)

```yaml
ignoreDifferences:
  - group: apps
    kind: StatefulSet
    jsonPointers: [/spec/volumeClaimTemplates]
```

> 💡 K8s 자체가 volumeClaimTemplates를 immutable로 정의. helm upgrade로 변경 불가 → ArgoCD가 sync 시도 → API가 거부 → 영원히 OutOfSync.

#### b) Secret.data (random password 등)

```yaml
ignoreDifferences:
  - kind: Secret
    jsonPointers: [/data]
```

> 💡 bitnami 차트는 첫 install에 random password 생성 → 이후 git엔 없음 → drift.

#### c) MutatingWebhookConfiguration.webhooks[].caBundle (cert-manager 갱신)

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jsonPointers: [/webhooks]
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jsonPointers: [/webhooks]
```

> 💡 cert-manager가 자기 webhook cert 갱신하면서 `caBundle` 필드를 patch → git엔 빈 값 → drift.

#### d) HorizontalPodAutoscaler.spec.metrics (metrics-server normalization)

```yaml
ignoreDifferences:
  - group: autoscaling
    kind: HorizontalPodAutoscaler
    jsonPointers: [/spec/metrics]
```

### 6.3 패턴: managedFields로 더 정밀

ArgoCD 2.5+ 는 server-side apply의 managedFields 기반 ignore도 지원:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    managedFieldsManagers:
      - kube-controller-manager
```

→ kube-controller-manager가 채운 필드는 ignore. 더 깔끔.

---

## 7. 우리 GitOps repo 구조

```
~/kosa-gitops/   (= git@github.com:kosacloudteam2/kosa-gitops.git)
├── README.md
└── apps/
    ├── _applications/          # ★ root-app이 watch
    │   ├── cert-manager.yaml
    │   ├── cert-manager-issuer.yaml
    │   ├── monitoring.yaml
    │   ├── redis.yaml
    │   ├── harbor.yaml
    │   ├── jenkins.yaml
    │   ├── ticket-app.yaml
    │   ├── demo-nginx.yaml
    │   └── auto-demo.yaml
    │
    ├── cert-manager-issuer/    # raw manifest (ClusterIssuer)
    │   └── issuer.yaml
    │
    ├── ticket-app/             # raw manifest
    │   ├── namespace.yaml
    │   ├── deployment.yaml     # ← Jenkins가 image tag 자동 갱신
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   └── secret.yaml
    │
    └── demo-nginx/
        └── ...
```

### 7.1 ticket-app 예시 (deployment.yaml)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ticket-app
  namespace: kosa-tickets
spec:
  replicas: 2
  selector: { matchLabels: { app: ticket-app } }
  template:
    metadata: { labels: { app: ticket-app } }
    spec:
      imagePullSecrets:
        - name: harbor-pull-secret      # ← pod spec 레벨
      nodeSelector:
        workload-type: production       # ← production 워커에만
      containers:
        - name: ticket-app
          image: harbor.kosa.team2/library/kosa-tickets:4   # ← Jenkins가 sed
          ports: [{ containerPort: 8000 }]
          env:
            - name: DEBUG
              value: "false"
          readinessProbe:
            httpGet: { path: /healthz, port: 8000 }
          livenessProbe:
            httpGet: { path: /healthz, port: 8000 }
            initialDelaySeconds: 30
```

---

## 8. 구축 절차

### 8.1 ArgoCD 설치 (Helm)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set controller.nodeSelector.workload-type=system \
  --set repoServer.nodeSelector.workload-type=system \
  --set server.nodeSelector.workload-type=system \
  --set redis.nodeSelector.workload-type=system
```

### 8.2 초기 admin 비번 얻기

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 8.3 Ingress + cert-manager

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: haproxy
    cert-manager.io/cluster-issuer: kosa-ca-issuer
    ingress.kubernetes.io/ssl-passthrough: "true"    # ← ArgoCD 자체 TLS 종료
spec:
  ingressClassName: haproxy
  tls:
    - hosts: [argocd.kosa.team2]
      secretName: argocd-tls
  rules:
    - host: argocd.kosa.team2
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: argocd-server, port: { number: 443 } }
```

### 8.4 git repo credential 등록

bastion에서:
```bash
# SSH key 생성 (배포 키)
ssh-keygen -t ed25519 -f ~/.ssh/argocd-deploy

# GitHub repo → Settings → Deploy keys → 등록

# ArgoCD에 등록
argocd repo add git@github.com:kosacloudteam2/kosa-gitops.git \
  --ssh-private-key-path ~/.ssh/argocd-deploy
```

### 8.5 root-app 생성

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: root-app, namespace: argocd }
spec:
  project: default
  source:
    repoURL: git@github.com:kosacloudteam2/kosa-gitops.git
    targetRevision: main
    path: apps/_applications
  destination: { server: https://kubernetes.default.svc, namespace: argocd }
  syncPolicy:
    automated: { prune: true, selfHeal: true }
EOF
```

→ 이후 git에 _applications/foo.yaml commit/push만 하면 새 앱 추가.

---

## 9. 운영 치트시트

```bash
# Application 목록
kubectl get applications -n argocd
argocd app list

# 상세
argocd app get ticket-app

# 수동 sync
argocd app sync ticket-app

# 새로 등록 (CLI)
argocd app create my-app \
  --repo git@... --path apps/my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace my-app

# 리프레시 (git 다시 조회)
argocd app get ticket-app --hard-refresh

# 강제 재배포 (cluster 리소스 새로 만듦)
argocd app sync ticket-app --force

# 일시 자동 sync 끔
argocd app set ticket-app --sync-policy none

# 로그
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

---

## 10. 트러블슈팅

### 10.1 OutOfSync인데 Healthy

CLAUDE.md FAQ Q5 참고. 대부분 정상.
- `argocd app diff <name>` 로 어떤 필드가 다른지 확인
- 필요 시 ignoreDifferences 추가

### 10.2 Sync 실패: "rpc error: code = Unknown ..."

repo-server 로그:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=200
```

흔한 원인:
- git 접근 실패 (SSH key 만료, repo 권한)
- Helm chart download 실패 (네트워크)
- helm values 문법 오류

### 10.3 ImagePullBackOff

```bash
kubectl describe pod <name> -n <ns>
# Events: "Failed to pull image ..."
```

원인:
- 이미지 태그 오타
- imagePullSecret 미설정 (pod spec containers 안 X)
- containerd가 Harbor cert 신뢰 X (§6 06장)

### 10.4 helm chart 버전 불일치

helm chart의 새 버전이 nodeSelector/labels 등의 default를 바꿔서 sync 실패할 수 있음. `targetRevision` 고정 + 변경 시 changelog 확인.

### 10.5 webhook 호출 실패로 sync 실패

```
error: Internal error occurred: failed calling webhook "..."
```

cert-manager-webhook 등이 죽었을 가능성. 우선순위로 살림.

### 10.6 root-app이 다른 Application 안 만듦

```bash
argocd app get root-app
# path가 _applications 맞는지

kubectl get applications -n argocd
# 새로 commit한 게 보이는지

# 강제 새로고침
argocd app get root-app --hard-refresh
```

---

## 11. 다음 챕터

→ **[08. Harbor 레지스트리](08-harbor-registry.md)**

사설 레지스트리가 왜 필요하고, Harbor의 내부 구조, Ceph RGW S3 백엔드를 쓰는 이유, helm values의 미묘한 옵션들 (disableredirect 등).
