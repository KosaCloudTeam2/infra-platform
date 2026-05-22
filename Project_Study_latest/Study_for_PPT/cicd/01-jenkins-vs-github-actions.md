# 01. Jenkins vs GitHub Actions — 우리는 왜 Jenkins?

> ⭐ **한 줄 요약**: GHA self-hosted runner 시도했으나 PVC fsGroup 함정 + ARC 학습 비용으로 후퇴. **Jenkins SCM Polling 안착**. NAT 환경 친화 + 기존 K8s 동적 agent 검증된 패턴.

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
| Plugin | kubernetes, git, workflow-aggregator, configuration-as-code |

---

## 🔍 8 차원 비교

| 차원 | Jenkins (선택) | GitHub Actions |
|---|---|---|
| **호스팅** | 자체 (sys1) | GitHub 클라우드 + self-hosted runner 가능 |
| **워크플로 정의** | Jenkinsfile (Groovy) | `.github/workflows/*.yml` (YAML) |
| **학습 곡선** | ★★★★ (Groovy 가파름) | ★★ (YAML + Marketplace) |
| **플러그인 생태계** | ★★★★★ (1800+) | ★★★★ (성장 중) |
| **K8s 통합** | k8s plugin (검증, 단순) | ARC (Action Runner Controller, 신규/함정 ★★★) |
| **비용 (private repo)** | 무료 (자체 호스팅) | 분당 과금 (cloud) 또는 self-hosted 무료 |
| **Trigger 옵션** | Polling, Webhook, cron, manual, build promotion | Push, PR, Issue, Schedule, Manual, repository_dispatch |
| **시크릿 관리** | Jenkins Credentials | Repo/Org Secrets, OIDC federation (AWS 강력) |
| **UI 통합** | 별도 페이지 | GitHub PR check, Issue 통합 |
| **NAT 친화** | Polling = outbound only ✅ | Runner outbound only ✅, Webhook은 inbound ❌ |
| **모니터링** | JMX/Prometheus | API |

---

## 🌟 두 도구의 핵심 차이

### Jenkins 본질
- "**범용 CI/CD 플랫폼**" — 모든 환경 (on-prem, cloud, hybrid) 지원
- 플러그인 1800개 (LDAP, JIRA, SonarQube, Slack, ... 뭐든)
- Groovy로 매우 유연한 워크플로
- 운영 부담 = 자체 호스팅 (vs SaaS)

### GitHub Actions 본질
- "**GitHub 통합 CI/CD**" — GitHub repo와 깊은 통합
- Marketplace (재사용 가능 action) ★★★★★
- YAML 단순
- 운영 부담 ↓ (cloud runner)
- vendor lock-in (GitHub 의존)

---

## 💡 우리가 Jenkins 고른 이유 (5가지)

### 1. 🔧 **이미 검증된 GitOps 패턴**
- Kaniko + K8s dynamic agent → 이미 동작
- GitHub Actions로 옮기면 ARC 학습 비용 ★★★

### 2. ⚠️ **ARC self-hosted runner 시도 후 함정**
- Controller 설치 OK
- Runner Pod 시작 OK
- 하지만 워크플로 실행 시 **PVC fsGroup 1001 권한 거부**
- `containerMode: kubernetes` 사용 시 추가 함정 (Workspace 권한)
- 학습 시간 vs 가치 trade-off 안 맞음 → 후퇴

### 3. 🌐 **NAT 환경 친화**
- 강의장 NAT 뒤 → GitHub Webhook inbound 불가
- Jenkins SCM Polling = outbound only → NAT 무관
- (GHA runner도 outbound only지만 ARC 학습 추가)

### 4. 🔌 **플러그인 풍부 (미래 확장)**
- LDAP/SAML SSO (org auth 추가 시)
- SonarQube (코드 품질)
- JIRA (이슈 자동 close)
- Slack (알림)

### 5. 📚 **학습 가치**
- Jenkins = 전통 + 보편적 (구인 시장에서 자주 등장)
- GHA = 모던 + 신규 (스타트업/MSA에서 자주)
- 둘 다 알면 베스트, 하나만 깊이면 Jenkins가 보편적

---

## 💰 비용 비교

| 항목 | Jenkins (자체) | GHA Cloud | GHA Self-hosted |
|---|---|---|---|
| **라이선스** | 무료 | private repo 분당 과금 ($0.008/min) | 무료 |
| **인프라** | sys1 1GB 메모리 | $0 (cloud) | sys1 + ARC 추가 |
| **운영 부담** | 중간 (직접 관리) | 낮음 (managed) | 중간 |
| **월 비용 (5000분 빌드)** | $0 | $40 | $0 |
| **월 비용 (50000분)** | $0 | $400 | $0 |

→ **빌드량 많으면 self-hosted (Jenkins 또는 GHA self-hosted)가 무조건 유리**

---

## ⚖️ Trade-off

### Jenkins 선택의 잃은 것
| 잃은 것 | 의미 |
|---|---|
| YAML 워크플로 (가독성) | Groovy = 진입 장벽 ★★★ |
| GHA Marketplace | uses: 한 줄로 끝나는 편의 X |
| GitHub UI PR check 통합 | 별도 페이지 (Jenkins URL) |
| OIDC federation (AWS) | 별도 IRSA/static key 필요 |
| 자동 secret 회전 | 수동 |

### Jenkins 선택의 얻은 것
| 얻은 것 | 의미 |
|---|---|
| 통제 ★★★★★ | 모든 설정 자체 결정 |
| 플러그인 풍부 | LDAP/SAML/JIRA/SonarQube/Slack |
| NAT 친화 (polling) | 외부 노출 0 |
| 무료 | 빌드량 무관 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Jenkins controller 죽음** | 새 빌드 트리거 X (기존 빌드도 중단) | sys1 fix → Jenkins Pod 재시작 |
| **Jenkins PVC 손실** | job history 손실 (코드는 git에 있어 OK) | backup에서 복구 (현재 backup 없음 — Phase 6) |
| **Kaniko Pod 죽음** | 그 빌드만 실패 | 재시도 (Jenkins replay) |
| **agent 노드 fork 실패 (Pending)** | 빌드 지연 | k8s plugin 확인, namespace ResourceQuota |

---

## 🚀 확장 가능성

### Option A: ⭐ Jenkins → GHA로 마이그레이션 (미래)
- ✅ **장점**: YAML 단순, Marketplace, GitHub PR 통합, OIDC AWS
- ❌ **단점**: 기존 Jenkinsfile 재작성, NAT 함정 재학습, ARC fsGroup 문제 풀어야
- 💰 **비용**: 0 (self-hosted) ~ $40+/월 (cloud)
- ⏱️ **작업**: 1~2주 (재작성 + 검증)
- 🎯 **추천 시점**: 팀 규모 5명+ + YAML 협업 효율 ↑ 원할 때

### Option B: ⭐ Jenkins + Webhook (외부 노출)
- ✅ **장점**: 즉시 트리거 (Polling 1~2분 지연 0)
- ❌ **단점**: Jenkins 외부 노출 = 공격 표면 ↑
- 💰 **비용**: Edge HAProxy ACL 추가만
- 🎯 **추천 시점**: off-prem (NAT 풀린 환경)

### Option C: Hybrid (Jenkins + GHA 같이)
- ✅ **장점**: Jenkins로 빌드, GHA로 PR check
- ❌ **단점**: 운영 2배
- 🎯 **추천 시점**: 큰 프로젝트 단계별 마이그레이션

### Option D: Tekton Pipelines
- ✅ **장점**: K8s native, YAML, CRD 기반
- ❌ **단점**: 학습 곡선, 자료 적음
- 🎯 **추천 시점**: 진짜 K8s native 원할 때

### Option E: Drone CI / GitLab CI
- ✅ **장점**: 가볍고 빠름
- ❌ **단점**: 생태계 작음
- 🎯 **추천 시점**: 단순한 use case

### Option F: ArgoCD Image Updater (Jenkins 없이)
- ✅ **장점**: Jenkins 없이 image tag 자동 갱신
- ❌ **단점**: 빌드는 따로 (다른 도구 필요)
- 🎯 **추천 시점**: 빌드를 외부 (GHA cloud)에 위탁

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 팀 5명+ + 협업 ↑ | A (GHA) |
| off-prem 환경 + 즉시 트리거 | B (Webhook) |
| K8s native 진짜 좋음 | D (Tekton) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 (`02-trigger-modes.md`) | Polling vs Webhook vs Runner 깊이 |
| 🔧 자기 (`05-argocd-gitops.md`) | Jenkins가 git에 image tag 갱신 → ArgoCD sync |
| 💾 데이터 | Jenkins Pod PVC (RBD) → backup 필요 |
| 🔒 보안 | Jenkins admin/credential, K8s RBAC |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. GHA가 모던인데 왜 Jenkins?**
A. (1) 이미 검증된 패턴 활용, (2) ARC self-hosted runner 시도 후 PVC 함정으로 후퇴, (3) NAT 환경 친화 (polling outbound), (4) 플러그인 풍부 (미래 확장). 단점은 YAML 협업 효율 ↓ + GHA Marketplace 못 씀 → 트레이드오프 인지.

**Q2. SCM Polling 1~2분 지연인데 비효율 아닌가?**
A. 데모/학습 환경엔 충분 (3분 지연 OK). 진짜 즉시 트리거 필요시 → off-prem 환경 이동 후 Webhook + Edge HAProxy 노출. 또는 polling 주기 30초로 줄임 (GitHub API rate limit 주의).

**Q3. GHA self-hosted runner 시도했다고? 어디서 실패?**
A. (1) Controller 설치 OK, (2) Runner Pod 시작 OK, (3) 워크플로 실행 시 fsGroup 1001 권한 거부 (PVC), (4) `containerMode: kubernetes`로 가면 추가 함정. 학습 시간 vs 가치 trade-off 안 맞아서 Jenkins로 후퇴. **트러블슈팅 경험 자체가 가치 있음** (발표 어필).

**Q4. 나중에 GHA로 갈 계획?**
A. 팀 규모 ↑ + 협업 효율 우선시 검토. 우선순위는 (1) Phase 6 다른 작업, (2) NAT 환경 해소.

**Q5. Jenkins K8s dynamic agent vs static agent?**
A. Dynamic = job 시작할 때 Pod 생성, 끝나면 삭제 → 격리 + 자원 효율. Static = 항상 떠있는 agent → 빠르지만 자원 낭비. 우리는 dynamic (Kaniko + git Pod template).

**Q6. Jenkinsfile vs scripted vs declarative?**
A. Declarative (`pipeline { ... }`) 우리 선택. 가독성 ★★★★, syntax 강제 → 일관성. Scripted는 Groovy 자유도 ★★★★★이지만 진입장벽 ★★★★★. 학습 + 협업엔 Declarative 권장.
