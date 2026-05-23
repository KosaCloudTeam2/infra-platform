# 05. ArgoCD GitOps — App-of-Apps 패턴

> ⭐ **한 줄 요약**: **ArgoCD를 App-of-Apps 패턴으로** 운영한다. root-app 하나가 다른 Application yaml들을 watch해서 자동으로 등록하니, 새 service 추가가 git commit 한 번이면 끝난다. selfHeal 활성으로 사람이 kubectl로 잘못 건드려도 자동 원복된다.

---

## 🎯 우리가 한 선택

ArgoCD를 sys1에 배치하고 kosa-gitops repo를 단일 source of truth로 운영한다. 모든 K8s manifest와 helm values가 git에 있고, ArgoCD가 3분 polling으로 git ↔ cluster 동기화를 자동 처리한다.

| 항목 | 값 |
|---|---|
| 도구 | ArgoCD |
| 패턴 | **App-of-Apps** (root-app → 다른 Application들) |
| Git repo | `~/kosa-gitops` (= GitHub.com/kosacloudteam2/kosa-gitops) |
| 배치 | sys1, namespace `argocd` |
| 도메인 | https://argocd.kosa.team2 |
| Sync 정책 | `automated: { prune: false, selfHeal: true }` |
| Sync 주기 | 3분 (default polling) |

### App-of-Apps 구조

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

핵심 아이디어는 **root-app 하나가 `_applications/` 디렉토리를 watch**한다는 점이다. 새 service를 추가하려면 그 디렉토리에 yaml 파일 하나 commit하면 끝이다. root-app이 자동으로 그 Application을 K8s에 등록하고, 등록된 Application이 helm chart 또는 raw manifest를 배포한다.

---

## 🔍 고려한 대안들

### GitOps 도구 — ArgoCD vs Flux vs Jenkins X

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **ArgoCD (선택)** | UI 강력, 시각화, CNCF, 활발 | resource 많음 (4 Pod) | ★★★★★ |
| Flux v2 | 가볍고 단순 | UI 약함 (CLI 위주) | ★★★★ |
| Jenkins X | Jenkins 통합 | EOL 위기 | ★ |
| Spinnaker | Netflix 만든 강력 | 복잡 ★★★★★ | ★★ |

ArgoCD vs Flux는 GitOps 도구의 양대 산맥이다. **Flux는 가볍고 단순**한 게 장점인데 UI가 약하고 CLI 위주라 시각화 학습이 부족하다. **ArgoCD는 UI가 강력**해서 diff 시각화, 의존성 그래프, 실시간 sync 상태 등을 한눈에 본다. 학습 환경에선 시각화가 학습 가치 ↑이라 ArgoCD가 합리적이다.

Spinnaker는 Netflix가 만든 강력한 deployment platform이지만 복잡도가 너무 크다 (4명 팀엔 과함). Jenkins X는 한때 Jenkins + K8s + GitOps 통합 솔루션이었는데 최근 사실상 EOL 상태라 제외.

### 패턴 — App-of-Apps vs 단일 Application vs ApplicationSet

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **App-of-Apps (선택)** | declarative, 1 git push로 모든 service | 중첩 학습 필요 | ★★★★★ |
| 단일 Application | 단순 | 모든 manifest 한 Application에 → 충돌, 관리 어려움 | ★★ |
| ApplicationSet | 동적 (cluster당 자동 생성) | 학습 곡선, multi-cluster 시 좋음 | ★★★★ |

**단일 Application 패턴**은 가장 단순하지만 모든 service의 manifest를 한 Application에 넣는 거라 충돌과 관리가 어려워진다. **App-of-Apps**는 root-app이 다른 Application yaml들을 watch하는 중첩 패턴인데, 한 번 익히면 매우 강력하다. **ApplicationSet**은 template 기반으로 cluster나 namespace당 자동 Application 생성 — multi-cluster 환경에서 진가를 발휘한다.

### Sync 정책 — automated vs manual

| 대안 | 장점 | 단점 |
|---|---|---|
| **automated + selfHeal (선택)** | drift 자동 회복, GitOps 정신 | 사고 시 원복 어려움 |
| automated (selfHeal X) | git 변경만 자동 deploy | drift는 OutOfSync로 남음 |
| manual | 통제 ★★★★★ | GitOps 의미 없음 |

selfHeal은 GitOps의 핵심 가치 중 하나다. 사람이 kubectl로 잘못 변경했을 때 (실수든 의도든), ArgoCD가 git의 정의대로 자동 원복한다. **"git이 진리"라는 원칙을 강제로 지키는 메커니즘**이다.

---

## 💡 왜 ArgoCD + App-of-Apps?

### 1. 선언적 GitOps의 완성

> 🔥 **핵심**: 클러스터 상태는 git이 진리. 사람이 kubectl로 변경 → selfHeal이 되돌림.

이게 GitOps의 본질이다. **모든 변경은 git을 거친다.** Disaster scenario에서도 cluster가 죽으면 git에서 다시 부트스트랩 가능하고, 사고 진단 시 git history가 audit trail이 된다.

### 2. App-of-Apps = 1 git push로 전체 부트스트랩

새 service를 추가하려면 `apps/_applications/new-service.yaml` 한 파일 commit하면 끝이다. root-app이 그걸 감지해서 새 Application을 자동 등록하고, 그 Application이 helm chart 또는 raw manifest를 배포한다. **"infrastructure as code"가 진짜로 완성**된 셈이다.

### 3. UI가 강력하다

K8s 상태를 ArgoCD UI에서 시각적으로 본다. App별 diff (git vs cluster), 의존성 그래프, live log/event 등이 모두 한 화면에 있다. CLI보다 학습 + 운영 모두 효율적이다.

### 4. 다양한 source 지원

Git source (Helm, Kustomize, raw manifest, plain yaml), Helm repo (직접 chart pull), OCI registry까지 다 지원한다. 우리 use case마다 적절한 source를 골라 쓸 수 있다.

### 5. selfHeal = 자동 보호

누군가 `kubectl scale deploy ticket-app --replicas=5`로 임시 변경했다고 치자. ArgoCD가 그 변경을 감지해서 git의 `replicas: 2`로 자동 원복한다. **사람 실수가 자동으로 보호**된다. 단점은 진짜 임시 변경이 필요한 사고 시 ArgoCD를 일시 disable해야 한다는 점이다.

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| 자원 (sys1) | 4 Pod (server, repo-server, application-controller, redis), ~500MB RAM |
| 운영 | 0 (declarative) |
| Git 호스팅 | GitHub 무료 (private repo) |

비용 거의 0이다. 무료 도구 + 호스트 자원 ~500MB. 운영 부담도 declarative라 매우 낮다 (kubectl로 직접 작업하는 것보다 적다).

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| GitOps 모든 가치 | ArgoCD 학습 |
| 1 git push로 부트스트랩 | 사고 시 git에서 변경 후 다시 sync |
| selfHeal 자동 보호 | 임시 변경 (kubectl) 불가능 (원복됨) |
| UI 강력 | 4 Pod 메모리 |
| OutOfSync 알람 가능 | 사고 시 OutOfSync로 보여서 노이즈 |

가장 큰 trade-off는 **임시 변경 불편함**이다. 사고 디버깅 중 "이 설정 잠깐 바꿔서 테스트해보자" 같은 case에서 selfHeal이 즉시 원복해버린다. 해결은 ArgoCD UI에서 해당 app의 sync를 잠시 disable하거나, git에 임시 변경을 commit 후 테스트.

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

ArgoCD의 4 Pod 중에서 가장 중요한 건 **application-controller**다. 이게 git ↔ cluster reconcile을 담당한다. 죽으면 새 sync가 안 되지만 기존 워크로드는 영향 없다. 다행히 K8s Deployment라 자동 재시작된다.

GitHub.com이 죽는 시나리오도 가끔 발생하는데 (연 몇 번 outage), 그 동안 새 deploy를 못 한다. 기존 워크로드는 영향 없으니 사용자 입장에선 보통 모른다.

---

## 🚀 확장 가능성

### Option A: ⭐ Multi-cluster (EKS도 ArgoCD가 관리)

**현재는 ArgoCD가 온프레 K8s만 관리하고 EKS는 manual deploy**다. 그래서 새 코드 push 시 온프레만 업데이트되고 EKS는 옛 버전 그대로다. Burst 시점에 옛 버전 EKS Pod이 사용자에게 응답할 위험이 있다.

해결책은 bastion ArgoCD에 EKS cluster를 등록하고, git repo를 kustomize overlay 구조로 재편성하는 것이다. 같은 git push가 양쪽 cluster에 동기 배포된다. 작업 4~6시간.

- 🎯 **추천 시점**: burst 자주 + EKS 코드 일관성 중요해질 때

### Option B: ApplicationSet (template 기반 자동 생성)

새 cluster 또는 namespace 추가 시 자동으로 Application이 생성된다. Multi-cluster 환경 또는 dev/staging/prod tier 분리 환경에서 진가를 발휘.

### Option C: ArgoCD Image Updater (image tag 자동 갱신)

현재 Jenkins가 sed로 image tag를 갱신하고 git push하는데, ArgoCD Image Updater가 Harbor scan 후 자동 갱신할 수 있다. **Jenkins 없이 image tag 자동화** 가능. 단점은 빌드는 다른 도구가 필요.

### Option D: Argo Rollouts (canary/blue-green 배포)

새 버전을 5% → 25% → 100% 점진 배포하면서 Prometheus 메트릭을 자동 평가. 사고 시 자동 rollback. 잦은 배포 + 안전성 요구 시 유용.

### Option E: ArgoCD Notifications (Slack/email 알림)

sync 성공/실패, app 상태 변화를 Slack이나 email로 알림. 운영 진입 + 알림 정식 운영 시 추가.

### Option F: SSO (LDAP/SAML/OIDC)

현재는 admin/kubeadm secret으로 들어가는데, 진짜 운영급은 SSO 통합. 팀 5명+ + SSO 인프라 있을 때 검토.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| EKS deploy 수동 | A (multi-cluster) ⭐ |
| 잦은 배포 + 안전성 | D (Rollouts) |
| Slack 알림 필요 | E |

---

## 🔗 다른 파트와의 연결

ArgoCD는 Jenkins (`01/02 jenkins-*`)의 후속 단계다. Jenkins가 image build + git에 tag 갱신하면 ArgoCD가 sync로 cluster에 반영한다. `06-pipeline-flow.md`가 전체 E2E 흐름을 설명한다. 아키텍처 측면에선 Multi-cluster 확장이 `architecture/04-burst-architecture.md`와 연결된다. 보안 측면에선 ArgoCD RBAC, git access, Sealed Secrets 통합이 `security/05-secrets-rbac.md`와 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Flux 대신 ArgoCD를 선택한 이유는?**

A. 세 가지 이유입니다. **UI 강력함** (시각화 ★★★★★), **사용자 경험 ★★★★** (CLI보다 학습 곡선 ↓), **커뮤니티 ↑** (GitHub star 16k+). Flux는 가볍지만 UI가 약해서 디버깅/시각화에 손해입니다. 우리 팀 학습 + 발표 환경엔 ArgoCD가 맞았습니다.

**Q2. App-of-Apps 패턴의 핵심이 뭔가요?**

A. **root-app이라는 "메타 Application"이 다른 Application yaml 파일들을 watch**합니다. 새 service 추가 = `apps/_applications/foo.yaml` 한 파일 commit이면 끝입니다. root-app이 그걸 감지해서 새 Application 등록 → 그 Application이 service를 배포. **부트스트랩이 declarative**가 됩니다.

**Q3. selfHeal이 사람 실수 보호한다고 했는데, 사고 시 임시 변경은 어떻게?**

A. 세 가지 방법입니다. **첫째, ArgoCD UI에서 해당 app의 `Sync Disable` 토글** → 임시 변경 → 복구 후 sync 다시 활성. **둘째, git에 임시 변경 commit** (Single source of truth 유지). **셋째, sync window로 특정 시간만 sync 가능하게 제한**. 우리는 첫 번째 방법을 주로 씁니다.

**Q4. helm.values를 Application spec에 박는데 secret은 어떻게요?**

A. **솔직히 현재 K8s Secret을 별도 manual 생성**합니다. Helm values엔 reference만 (`existingSecret: harbor-creds`) 있고요. Phase 6에서 **Sealed Secrets**로 변환해서 git commit 가능하게 만들 예정입니다. 또는 External Secrets Operator + Vault도 옵션입니다.

**Q5. sync prune true vs false 차이는요?**

A. **true면 git에서 사라진 resource를 cluster에서도 자동 삭제**합니다. **false면 cluster에 남습니다**. 우리는 **false**입니다 — 실수로 git에서 누락한 manifest가 자동 삭제되는 위험을 회피했습니다. 단점은 git이 100% 진리가 아니게 되는 점이지만, 운영 안전성 우선이었습니다.

**Q6. helm chart source일 때 sync revision="HEAD" 안 된다는데?**

A. **Git source면 "HEAD" 가능, Helm source면 chart version (예 "85.0.2")을 명시**해야 합니다. 우리도 처음 이걸 모르고 "HEAD"로 설정해서 함정에 빠졌습니다. → CLAUDE.md 트러블슈팅 챕터에 정리돼 있습니다.
