# 08. GitOps — ArgoCD

> Layer 3 / 학습 1일

---

## 1) GitOps란

> **"Git을 단일 진실 소스(Single Source of Truth)로 두고, K8s를 자동 동기화."**

기존 (CIOps):

```
[개발자] kubectl apply → K8s
   ↓ 누가 뭘 했는지 모름
   ↓ 환경 차이 발생
```

GitOps:

```
[개발자] git push → [Git repo]
                      ↓ ArgoCD가 감지
                    [K8s 자동 동기화]
   ↓ 모든 변경이 Git에 기록
   ↓ 환경 = Git 내용 그대로
```

---

## 2) ArgoCD vs Flux

|               | **ArgoCD**                 | Flux            |
| ------------- | -------------------------- | --------------- |
| UI            | 풍부 (Web)                 | CLI 위주        |
| App-of-Apps   | 강력                       | 기능적으로 가능 |
| 학습 자료     | 풍부                       | 보통            |
| **선택 이유** | UI 데모 임팩트 + 자료 풍부 | -               |

---

## 3) ArgoCD 핵심 개념

### Application CR

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kosa-tickets-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/<org>/kosa-manifests
    path: apps/kosa-tickets
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: kosa-tickets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

- `source` — Git 경로
- `destination` — 어느 K8s 클러스터의 어느 namespace
- `automated` — 자동 동기화 + 수동 변경 자동 복원

### App-of-Apps

부모 Application이 여러 자식 Application을 관리. 전체 클러스터 부트스트랩을 한 줄로:

```yaml
metadata: { name: bootstrap }
spec:
  source: { path: apps/ } # 이 디렉토리의 모든 Application CR을 적용
```

### ApplicationSet

template으로 여러 Application 자동 생성. 멀티 클러스터에 같은 앱 동시 배포할 때:

```yaml
generators:
  - clusters: {} # 등록된 모든 클러스터에
template:
  metadata:
    name: "app-{{name}}" # cluster 이름별로 Application
```

---

## 4) Helm chart + GitOps

ArgoCD는 Helm chart를 내부적으로 `helm template` 변환해서 적용. **K8s에 helm CLI 안 깔아도 됨**.

```yaml
source:
  repoURL: https://argoproj.github.io/argo-helm
  chart: argo-cd
  targetRevision: 5.x.x
  helm:
    values: |
      server:
        service:
          type: LoadBalancer
```

---

## 5) 우리 GitOps 흐름

```
[개발자 Push]
  github.com/<org>/kosa-tickets-app/          ← 앱 코드
       ↓ GitHub Actions
   ┌── docker build/push → ghcr.io/.../kosa-tickets-app:abc123
   │
   └── manifest 업데이트 → github.com/<org>/kosa-manifests/
              ↓ ArgoCD가 감지 (3분 polling)
        [ArgoCD]
              ↓
        K8s에 적용 (Deployment 이미지 tag 변경)
              ↓
        새 Pod 배포 (rolling update)
```

**별도 repo 2개:**

- `kosa-tickets-app` — 앱 소스 코드
- `kosa-manifests` — K8s 매니페스트 (ArgoCD가 보는 곳)

분리 이유: 매니페스트 변경이 앱 빌드 트리거 안 하게.

---

## 6) 멀티 클러스터 (온프레 + EKS)

```
[ArgoCD on 온프레 K8s]
        │
        ├──→ 온프레 K8s 클러스터 (자기 자신)
        │      └─ kosa-tickets-app
        │
        └──→ AWS EKS 클러스터 (Burst용)
               └─ kosa-tickets-app (같은 매니페스트, replicas 다름)
```

ApplicationSet으로 두 클러스터에 동일 앱 자동 배포. burst 시점에 EKS 활성.

---

## 7) 발표 어필

> _"모든 K8s 변경은 Git에 기록되고 ArgoCD가 자동 동기화합니다. 개발자가 kubectl을 직접 쓸 일이
> 없으며, 누가 무엇을 언제 바꿨는지 git log로 100% 추적 가능합니다. ApplicationSet으로 온프레
> 클러스터와 AWS EKS Burst 클러스터에 동일 매니페스트를 자동 배포합니다."_

---

## 다음 단원

[`09_AWS_하이브리드.md`](09_AWS_하이브리드.md)
