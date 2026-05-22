# 05. ArgoCD GitOps — App-of-Apps 패턴

> ⭐ **한 줄 요약**: **ArgoCD** + **App-of-Apps** = root-app 1개로 모든 service 자동 부트스트랩. Git이 desired state의 single source of truth. selfHeal로 drift 자동 회복.

---

## 🎯 우리가 한 선택

| 항목 | 값 |
|---|---|
| 도구 | ArgoCD |
| 패턴 | **App-of-Apps** (root-app → 다른 Application들) |
| Git repo | `~/kosa-gitops` (= GitHub.com/kosacloudteam2/kosa-gitops) |
| 배치 | sys1, namespace `argocd` |
| 도메인 | https://argocd.kosa.team2 |
| Sync 정책 | `automated: { prune: false, selfHeal: true }` |
| Sync 주기 | 3분 (default polling) |

### 구조
```
~/kosa-gitops/
├── apps/
│   ├── _applications/           ← Application 정의 (root-app이 watch)
│   │   ├── cert-manager.yaml
│   │   ├── monitoring.yaml
│   │   ├── harbor.yaml
│   │   ├── jenkins.yaml
│   │   ├── ticket-app.yaml
│   │   └── ...
│   └── ticket-app/              ← raw manifest
│       └── deployment.yaml
```

### root-app이 _applications/ 디렉토리를 watch → 새 yaml 추가하면 자동으로 새 Application 등록 → 그 Application이 helm chart 또는 raw manifest 배포

---

## 🔍 고려한 대안들

### Q1. GitOps 도구 — ArgoCD vs Flux vs Jenkins X

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **ArgoCD (선택)** | UI 강력, 시각화, CNCF, 활발 | resource 많음 (4 Pod) | ★★★★★ |
| Flux v2 | 가볍고 단순 | UI 약함 (CLI 위주) | ★★★★ |
| Jenkins X | Jenkins 통합 | EOL 위기 | ★ |
| Spinnaker | Netflix 만든 강력 | 복잡 ★★★★★ | ★★ |

### Q2. 패턴 — App-of-Apps vs 단일 Application vs ApplicationSet

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **App-of-Apps (선택)** | declarative, 1 git push로 모든 service | 중첩 학습 필요 | ★★★★★ |
| 단일 Application | 단순 | 모든 manifest 한 Application에 → 충돌, 관리 어려움 | ★★ |
| ApplicationSet | 동적 (cluster당 자동 생성) | 학습 곡선, multi-cluster 시 좋음 | ★★★★ (확장 시) |

### Q3. Sync 정책 — automated vs manual

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **automated + selfHeal (선택)** | drift 자동 회복, GitOps 정신 | 사고 시 원복 어려움 | ★★★★ |
| automated (selfHeal X) | git 변경만 자동 deploy | drift는 OutOfSync로 남음 | ★★★★ |
| manual | 통제 ★★★★★ | GitOps 의미 없음 | ★★ |

---

## 💡 왜 ArgoCD + App-of-Apps?

### 1. 🎯 **선언적 GitOps**
> 🔥 **핵심**: 클러스터 상태는 git이 진리. 사람이 kubectl로 변경 → selfHeal이 되돌림.

- Disaster scenario: cluster 죽으면 git에서 다시 부트스트랩
- 사람 실수 (잘못된 kubectl) → 자동 원복
- Audit: 모든 변경이 git history

### 2. 🌳 **App-of-Apps = 1 git push로 전체 부트스트랩**
- 새 service 추가: `apps/_applications/new-service.yaml` commit
- ArgoCD root-app이 감지 → 새 Application 생성 → 자동 배포
- "infrastructure as code" 완성

### 3. 🖥️ **UI 강력**
- diff 시각화 (git vs cluster)
- 의존성 그래프
- live log/event

### 4. 🔌 **다양한 source 지원**
- Git (Helm, Kustomize, raw manifest, plain yaml)
- Helm repo (직접 chart pull)
- OCI registry

### 5. 📊 **selfHeal = 자동 회복**
- 누군가 `kubectl scale deploy ticket-app --replicas=5` → ArgoCD가 git의 replicas: 2로 원복
- 사람 실수 자동 보호

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| 자원 (sys1) | 4 Pod (server, repo-server, application-controller, redis), ~500MB RAM |
| 운영 | 0 (declarative) |
| Git 호스팅 | GitHub 무료 (private repo) |

→ 비용 0, 운영 부담 ↓ (declarative)

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| GitOps 모든 가치 | ArgoCD 학습 |
| 1 git push로 부트스트랩 | 사고 시 git에서 변경 후 다시 sync |
| selfHeal 자동 보호 | 임시 변경 (kubectl) 불가능 (원복됨) |
| UI 강력 | 4 Pod 메모리 |
| OutOfSync 알람 가능 | 사고 시 OutOfSync로 보여서 노이즈 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **ArgoCD server 죽음** | UI/API down (sync는 controller가 계속) | Pod 재시작 |
| **application-controller 죽음** | 새 sync 안 됨, 기존 워크로드 동작 | Pod 재시작 |
| **repo-server 죽음** | git pull/render 실패 → sync 멈춤 | Pod 재시작 |
| **redis 죽음** | 캐시 손실, 성능 ↓ | Pod 재시작 |
| **PVC 손실** | ArgoCD 설정 손실 (git에서 재구축 가능) | git에서 restore |
| **git server 죽음** | 새 sync X (기존 워크로드 정상) | git 회복 |

---

## 🚀 확장 가능성

### Option A: ⭐ Multi-cluster (EKS도 ArgoCD가 관리)
- 현재: 온프레 K8s만 관리. EKS는 manual.
- 확장: bastion ArgoCD에 EKS cluster 등록
- 작업: kustomize overlay (onprem vs eks)
- ⏱️ **작업**: 4~6시간
- 🎯 **추천 시점**: burst 자주 + EKS 코드 일관성 필요

### Option B: ⭐ ApplicationSet (template 기반 자동 생성)
- ✅ **장점**: 새 cluster 또는 namespace 추가 시 자동 Application 생성
- 🎯 **추천 시점**: Multi-cluster 또는 dev/staging/prod tier

### Option C: ArgoCD Image Updater (image tag 자동 갱신)
- 현재: Jenkins가 sed로 image tag 갱신 후 git push
- 확장: ArgoCD Image Updater가 Harbor scan 후 자동 갱신
- ✅ **장점**: Jenkins 없이 image tag 자동
- ❌ **단점**: 빌드는 따로 (다른 도구)
- 🎯 **추천 시점**: Jenkins 단순화

### Option D: Argo Rollouts (canary/blue-green)
- ✅ **장점**: 새 버전 5% → 100% 점진 (Prometheus 메트릭 기반)
- ❌ **단점**: Rollout CRD 학습
- 🎯 **추천 시점**: 잦은 배포 + 안전성 ↑

### Option E: ArgoCD Notifications (Slack/email 알림)
- ✅ **장점**: sync 성공/실패 알림
- 🎯 **추천 시점**: 운영 진입 + 알림 정식 운영

### Option F: SSO (LDAP/SAML/OIDC)
- 현재: admin/kubeadm secret
- 확장: org SSO
- 🎯 **추천 시점**: 팀 5명+ + SSO 인프라 있을 때

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| EKS deploy 수동 | A (multi-cluster) |
| 잦은 배포 + 안전성 | D (Rollouts) |
| Slack 알림 필요 | E |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 (`01/02 jenkins`) | Jenkins가 git에 image tag 갱신 → ArgoCD sync |
| 🔧 자기 (`06-pipeline-flow.md`) | E2E 흐름 |
| 🏛️ 아키텍처 | Multi-cluster 확장 (`architecture/04-burst`) |
| 🔒 보안 | ArgoCD RBAC, Git access, sealed-secrets 통합 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Flux 대신 ArgoCD?**
A. (1) UI 강력 (시각화 ★★★★★), (2) 사용자 경험 ★★★★ (CLI보다 학습 곡선 ↓), (3) 커뮤니티 ↑ (Github star 16k+). Flux는 가볍지만 UI 약함 → 디버깅/시각화 손해. 우리 팀 + 발표 환경엔 ArgoCD가 맞음.

**Q2. App-of-Apps 패턴 핵심?**
A. root-app이라는 "메타 Application"이 다른 Application yaml 파일을 watch. 새 service 추가 = `apps/_applications/foo.yaml` commit만. 부트스트랩 declarative.

**Q3. selfHeal이 사람 실수 보호한다는데, 사고 시 어떻게 임시 변경?**
A. (1) ArgoCD UI에서 해당 app `Sync Disable` 토글, (2) 임시 변경, (3) 복구 후 sync 다시 활성. 또는 git에 임시 변경 commit (Single source of truth).

**Q4. helm.values를 Application spec에 박는데 secret은? Git에 commit?**
A. **Sealed Secrets** (현재 미구현, Phase 6). 또는 External Secrets Operator로 Vault에서 가져오기. 현재는 K8s Secret 별도 (manual). Helm values엔 reference만 (`existingSecret: harbor-creds`).

**Q5. sync prune true vs false?**
A. true면 git에서 사라진 resource를 cluster에서 삭제. false면 cluster에 남음. **우리 false** (실수로 git에서 누락 → 자동 삭제 위험). 단점은 git이 진리가 아니게 됨. 운영 성숙 시 true 검토.

**Q6. helm chart source일 때 sync revision="HEAD" 안 됨**
A. Git source면 "HEAD" 가능. Helm source면 chart version (예 "85.0.2") 명시. 우리가 만난 함정. → CLAUDE.md 트러블슈팅 챕터.
