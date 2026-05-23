# 01. Jenkins vs GitHub Actions — 우리는 왜 Jenkins?

> ⭐ **한 줄 요약**: GHA self-hosted runner를 시도했지만 **PVC fsGroup 함정과 ARC containerMode 학습 비용**으로 후퇴했다. **Jenkins SCM Polling이 NAT 환경 친화적**이고 기존 K8s 동적 agent 패턴이 이미 검증돼 있어 선택했다. 트레이드오프는 YAML 협업 효율을 포기한 것.

---

## 🎯 우리가 한 선택

| 항목 | 값 |
|---|---|
| CI 도구 | **Jenkins LTS** (lts-jdk17) |
| 배치 | sys1 namespace `jenkins` |
| Agent | K8s plugin (dynamic Pod agent) |
| Build tool | Kaniko (rootless container build) |
| Trigger | SCM Polling (`H/2 * * * *` = 2분마다) |
| Pipeline | Jenkinsfile (Declarative) |
| 주요 Plugin | kubernetes, git, workflow-aggregator, configuration-as-code |

Jenkins controller는 sys1의 jenkins namespace에 단일 Pod으로 떠있고, 빌드 시점에만 K8s plugin이 동적으로 Kaniko + git container를 가진 agent Pod을 생성한다. 빌드 끝나면 Pod이 자동 삭제되어 자원이 회수된다. **이게 K8s native CI/CD 패턴이고, 우리가 GHA 대신 Jenkins를 골랐을 때 가장 큰 이유 중 하나다.**

---

## 🔍 8 차원 비교

두 도구를 우리 환경 기준으로 8가지 차원에서 비교했다.

| 차원 | Jenkins (선택) | GitHub Actions |
|---|---|---|
| **호스팅** | 자체 (sys1) | GitHub 클라우드 + self-hosted runner 가능 |
| **워크플로 정의** | Jenkinsfile (Groovy) | `.github/workflows/*.yml` (YAML) |
| **학습 곡선** | ★★★★ (Groovy 가파름) | ★★ (YAML + Marketplace) |
| **플러그인 생태계** | ★★★★★ (1800+) | ★★★★ (성장 중) |
| **K8s 통합** | k8s plugin (검증, 단순) | ARC (Action Runner Controller, 신규/함정) |
| **비용 (private repo)** | 무료 (자체 호스팅) | 분당 과금 (cloud) 또는 self-hosted 무료 |
| **Trigger 옵션** | Polling, Webhook, cron, manual | Push, PR, Issue, Schedule, Manual |
| **시크릿 관리** | Jenkins Credentials | Repo/Org Secrets, OIDC federation (AWS 강력) |
| **UI 통합** | 별도 페이지 | GitHub PR check, Issue 통합 |
| **NAT 친화** | Polling = outbound only ✅ | Runner outbound only ✅, Webhook은 inbound ❌ |

### 두 도구의 본질적 차이

이 표를 읽기 전에 두 도구의 **철학적 차이**를 이해하는 게 중요하다.

**Jenkins**는 2011년부터 시작된 "**범용 CI/CD 플랫폼**"이다. 어떤 환경 (on-prem, cloud, hybrid)이든 동작하도록 설계됐고, 플러그인 1800개로 거의 모든 통합을 다 다룬다 (LDAP, JIRA, SonarQube, Slack, ...). Groovy로 정의하는 Jenkinsfile은 매우 유연해서 복잡한 워크플로도 표현 가능하다. 운영 부담은 자체 호스팅이라는 점에서 발생한다.

**GitHub Actions**는 2019년 출시된 "**GitHub 통합 CI/CD**"다. GitHub repo와의 통합이 매우 깊고 (PR check, Issue 자동화 등), Marketplace에 재사용 가능한 action들이 풍부하다. YAML이라 진입 장벽이 낮고, cloud runner면 운영 부담이 0이다. 단점은 GitHub 의존성과 그에 따른 vendor lock-in.

같은 일을 둘 다 할 수 있지만, **출발점이 다르다**. Jenkins는 "어디서나 동작하는 범용 도구", GHA는 "GitHub 생태계의 일부".

---

## 💡 우리가 Jenkins 고른 다섯 가지 이유

이 선택을 의식적으로 한 진짜 이유 5가지를 풀어 설명한다.

### 1. 이미 검증된 GitOps 패턴이 있었다

K8s plugin + Kaniko + ArgoCD 조합이 이미 동작하고 있었다. 새 도구 (GHA + ARC)로 옮기려면 같은 패턴을 처음부터 다시 구축해야 한다. **이미 동작하는 검증된 인프라를 굳이 깨뜨릴 이유가 없었다.** 학습 가치는 GHA가 더 크지만, 학습 시간이 너무 길었다.

### 2. ARC self-hosted runner 시도 후 함정 발견

처음엔 GHA로 가려 했다. 실제로 ARC (Actions Runner Controller)를 설치하고 시도했는데 함정이 잇따라 발견됐다.

- Controller 설치 OK
- Runner Pod 시작 OK
- 워크플로 실행 시작 OK
- **하지만 워크플로 안에서 PVC 권한 거부 (fsGroup 1001 필요)**
- `containerMode: kubernetes` 모드로 가면 워크스페이스 권한 함정이 추가로 발생

이 함정들을 풀어가는 게 학습 가치는 있지만, **학습 시간 vs 결과 가치 trade-off가 안 맞았다**. 같은 시간으로 다른 작업 (sys2 추가, backup 자동화 등)을 하는 게 ROI가 더 좋았다. 그래서 후퇴해서 Jenkins로 정착했다.

이 경험 자체는 **트러블슈팅 자료**로 남아 있어 면접에서 활용 가치가 있다. "GHA self-hosted runner 시도했지만 PVC fsGroup 함정으로 ROI 안 맞아 Jenkins 후퇴" 같은 스토리는 엔지니어링 판단력을 보여준다.

### 3. NAT 환경에 친화적

강의장 NAT 뒤라 **GitHub Webhook이 우리 Jenkins로 inbound 불가**하다. Jenkins SCM Polling은 outbound only라 NAT 무관하게 동작한다. GHA runner도 outbound only지만, 그건 ARC 학습이 추가로 필요하다. 결과적으로 SCM Polling이 가장 단순한 해결책이었다.

### 4. 플러그인 풍부 (미래 확장)

Jenkins 플러그인 1800개는 미래 확장의 여유다. LDAP/SAML SSO (org 통합 시), SonarQube (코드 품질 게이트), JIRA (이슈 자동 close), Slack (알림 등) 모두 plugin 한 줄로 통합된다. GHA Marketplace도 좋지만 enterprise integration은 Jenkins가 여전히 우위다.

### 5. 학습 가치와 보편성

Jenkins는 전통적이지만 보편적이다. 구인 시장에서 "Jenkins 운영 경험"이 "GHA 운영 경험"보다 더 자주 등장한다. GHA는 모던하고 스타트업/MSA에서 자주 보이지만, 대기업 + on-prem 환경엔 Jenkins가 여전히 표준이다. **두 도구 다 학습 가치 있지만, 우리 학습 시간이 한정적이라면 Jenkins부터 깊이 익히는 게 보편성 측면에서 유리**하다.

---

## 💰 비용 비교 — 빌드량별

이게 가장 명확한 비교다.

| 항목 | Jenkins (자체) | GHA Cloud | GHA Self-hosted |
|---|---|---|---|
| **라이선스** | 무료 | private repo 분당 과금 ($0.008/min) | 무료 |
| **인프라** | sys1 1GB 메모리 | $0 (cloud) | sys1 + ARC 추가 |
| **운영 부담** | 중간 (직접 관리) | 낮음 (managed) | 중간 |
| **월 비용 (5000분 빌드)** | $0 | $40 | $0 |
| **월 비용 (50000분)** | $0 | **$400** | $0 |

빌드량이 적으면 (월 1000분 이하) GHA cloud의 무료 tier로 충분하다. 하지만 빌드량이 늘면 GHA cloud는 분당 과금이 누적적이라 큰 비용이 된다. **자체 호스팅 (Jenkins 또는 GHA self-hosted) 둘 다 빌드량 무관하게 $0**이라, 진짜 운영급 빌드량이면 둘 중 어느 거든 자체 호스팅이 정답이다.

우리는 학습 환경이라 빌드량이 적지만, 어차피 sys1 자원이 여유 있어 (메모리 60% 사용) Jenkins 1GB 추가가 부담 없었다.

---

## ⚖️ Trade-off

Jenkins 선택으로 우리가 의식적으로 포기한 것들이 있다.

| 잃은 것 | 의미 |
|---|---|
| YAML 워크플로 (가독성) | Groovy = 진입 장벽 ★★★ |
| GHA Marketplace | uses: 한 줄로 끝나는 편의 X |
| GitHub UI PR check 통합 | 별도 페이지 (Jenkins URL) |
| OIDC federation (AWS) | 별도 IRSA/static key 필요 |
| 자동 secret 회전 | 수동 |

가장 큰 trade-off는 **GitHub과의 deep integration**을 못 누린다는 점이다. GHA였으면 PR을 열 때 자동으로 build status가 PR 페이지에 표시되고, "Merge when passing" 같은 자동 머지도 가능하다. Jenkins는 별도 URL로 가서 확인해야 한다. 협업 흐름이 더 깨끗하지 않다.

또한 **OIDC federation으로 AWS와 통합하는 게 GHA가 훨씬 강력**하다. GHA가 GitHub OIDC token을 발급하면 AWS IAM이 그걸 신뢰해서 임시 credential을 발급하는 패턴이 가능한데, Jenkins로 같은 일을 하려면 IRSA + Jenkins ServiceAccount 같은 우회 패턴이 필요하다.

대신 얻은 것은 **검증된 패턴 + NAT 친화 + 빌드량 무관 무료**다. 데모/학습 환경엔 이 셋이 더 가치 있었다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Jenkins controller 죽음** | 새 빌드 트리거 X (기존 빌드도 중단) | sys1 fix → Jenkins Pod 재시작 |
| **Jenkins PVC 손실** | job history 손실 (코드는 git에 있어 OK) | backup에서 복구 (현재 backup 없음) |
| **Kaniko Pod 죽음** | 그 빌드만 실패 | 재시도 (Jenkins replay) |
| **agent 노드 fork 실패 (Pending)** | 빌드 지연 | k8s plugin 확인, ResourceQuota |

Jenkins controller가 죽으면 새 빌드를 못 트리거하는 게 critical이다. **현재 단일 Pod이라 SPoF**고, sys1과 운명을 같이 한다. sys1 추가 (sys2)와 함께 Jenkins 분리 (VM으로 옮김)을 검토하는 게 Phase 6 우선 작업 중 하나다 (`architecture/07-bootstrap-resilience.md` 참고).

---

## 🚀 확장 가능성

### Option A: Jenkins → GHA로 마이그레이션 (미래)

언젠가 GHA로 옮길 수 있다. 장점은 YAML 단순함, Marketplace, GitHub PR 통합, OIDC AWS 인증. 단점은 기존 Jenkinsfile 재작성 + NAT 환경 ARC 함정 다시 풀어야 함. 작업 1~2주 정도. **팀 5명+로 협업이 활발해지고 YAML 효율이 가치를 가지면** 검토할 만하다.

### Option B: Jenkins + Webhook (외부 노출, off-prem 환경)

NAT 풀린 환경 (off-prem 이전 후)에선 Webhook을 추가할 수 있다. Edge HAProxy에 jenkins 도메인을 외부 노출하고, GitHub Webhook을 설정하면 즉시 트리거된다. 폴링 1~2분 지연 → 즉시. 단점은 Jenkins 외부 노출 = 공격 표면 ↑.

### Option C: Hybrid (Jenkins + GHA 같이 운영)

Jenkins로 빌드, GHA로 PR check 자동화. 운영 2배 부담이지만 단계적 마이그레이션이 필요한 큰 프로젝트에서 일시적으로 쓸 만하다.

### Option D: Tekton Pipelines

K8s native + YAML + CRD 기반. 진짜 K8s native CI/CD를 원하면 매력적인 옵션이지만, 자료가 적고 학습 곡선이 있다.

### Option E: ArgoCD Image Updater (Jenkins 없이)

Jenkins 없이 ArgoCD Image Updater가 Harbor를 스캔해서 image tag를 자동으로 갱신한다. 빌드는 다른 도구 (GHA cloud 등)에 위탁. **단순화의 끝판왕**이지만 빌드와 배포가 분리돼 추적이 약간 복잡해진다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 팀 5명+ + 협업 ↑ | A (GHA) |
| off-prem 환경 + 즉시 트리거 | B (Webhook) |
| K8s native 진짜 원함 | D (Tekton) |
| Jenkins 폐기 + 단순화 | E (Image Updater) |

---

## 🔗 다른 파트와의 연결

이 Jenkins 결정은 CI/CD 파트의 다른 문서들과 연결된다. `02-jenkins-trigger-modes.md`는 polling vs webhook vs runner를 더 깊이 다루고, `03-jenkins-build-tools.md`는 Kaniko vs Docker vs Buildah를 비교한다. `05-argocd-gitops.md`는 Jenkins가 git에 image tag를 갱신한 후 ArgoCD가 어떻게 sync하는지 설명한다. 보안 측면에선 Jenkins admin/credential 관리가 `security/05-secrets-rbac.md`와 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. GHA가 모던인데 왜 Jenkins로 가셨나요?**

A. 네 가지 이유입니다. **첫째, 이미 검증된 K8s plugin + Kaniko 패턴 활용** — 굳이 새로 깔 이유 없었습니다. **둘째, ARC self-hosted runner 시도 후 PVC fsGroup 함정으로 후퇴** — 학습 시간 vs 결과 가치 trade-off가 안 맞았습니다. **셋째, NAT 환경 친화** — SCM Polling은 outbound only라 강의장 NAT 무관. **넷째, 플러그인 풍부 + 보편성** — 구인 시장 + 미래 확장 모두 유리. 단점은 YAML 협업 효율 ↓ + GHA Marketplace 못 쓰는 거고, 트레이드오프 인지하고 있습니다.

**Q2. SCM Polling 1~2분 지연인데 비효율 아닌가요?**

A. **데모/학습 환경엔 충분합니다**. 빌드 자체가 5~10분 걸리니 polling 지연 1~2분은 무시 가능한 비율입니다. 진짜 즉시 트리거가 필요하면 off-prem 환경 이동 후 Webhook + Edge HAProxy 노출하면 됩니다. polling 주기도 30초로 줄일 수 있지만 GitHub API rate limit 주의해야 합니다.

**Q3. GHA self-hosted runner 시도했다고 하셨는데 정확히 어디서 실패?**

A. 단계별로 설명드리면, **Controller 설치는 OK** (helm chart로), **Runner Pod 시작 OK**, 워크플로 실행도 시작은 됩니다. **하지만 워크플로 안에서 PVC에 쓰려고 할 때 권한 거부가 발생**합니다. fsGroup 1001 설정이 필요한데, 우리 Ceph CSI rbd가 그걸 자동으로 안 잡아줬습니다. `containerMode: kubernetes` 모드로 가면 워크스페이스 공유 PVC가 추가로 필요한데 거기서 또 권한 문제가 발생. **풀어가는 게 학습 가치 있지만 시간 ROI가 안 맞아 Jenkins로 후퇴**했습니다.

**Q4. 나중에 GHA로 갈 계획 있나요?**

A. **팀 5명+로 협업이 활발해지고 YAML 효율의 가치가 커지면 검토**합니다. 우선순위는 (1) Phase 6 다른 작업 (sys2, backup, NetworkPolicy 확장 등), (2) NAT 환경 해소 (off-prem 이전) 후에 두는 게 합리적입니다.

**Q5. Jenkins K8s dynamic agent vs static agent 차이는요?**

A. **Dynamic agent는 job 시작할 때 Pod을 생성하고 끝나면 삭제**합니다. 격리도 좋고 자원 효율도 ★★★★ (idle 시 Pod 0). **Static agent는 항상 떠있는 agent**라 빨리 시작하지만 자원 낭비. 우리는 dynamic agent를 K8s plugin으로 운영합니다. Pod template에 Kaniko + git container를 정의해두고, 빌드 시점에만 spawn됩니다.

**Q6. Jenkinsfile은 scripted vs declarative 중 뭘 골랐나요?**

A. **Declarative** (`pipeline { ... }`)입니다. 가독성 ★★★★ + syntax 강제 → 일관성. Scripted는 Groovy 자유도 ★★★★★이지만 진입장벽도 ★★★★★. 학습 + 협업엔 Declarative 권장입니다. 복잡한 로직이 필요하면 `script { }` 블록으로 부분적 Groovy 사용도 가능합니다.
