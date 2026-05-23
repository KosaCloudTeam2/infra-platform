# 02. Jenkins Trigger 모드 — SCM Polling vs Webhook vs Self-hosted Runner

> ⭐ **한 줄 요약**: 우리는 **SCM Polling을 선택**했다. Webhook은 외부 노출이 필요해 강의장 NAT 환경에서 불가능했고, GHA self-hosted runner는 ARC 함정으로 후퇴했다. Polling이 1~2분 지연이라는 단점이 있지만 NAT 친화 + 외부 노출 0이라 우리 환경엔 최적이었다.

---

## 🎯 우리가 선택한 모드

Jenkins SCM Polling을 `H/2 * * * *` schedule (2분마다)로 활성화했다. Jenkins가 자체적으로 git ls-remote를 주기적으로 호출해 마지막 commit이 변경됐는지 확인하고, 변경됐으면 빌드를 트리거한다. **외부에서 우리 Jenkins로 inbound 통신이 필요 없다 — 모두 outbound다.**

---

## 🔍 5개 모드 비교

CI trigger 방식은 의외로 다양하다. 우리가 비교한 5개 모드를 정리하면 다음과 같다.

| 모드 | 동작 | 외부 노출 | 지연 | NAT 친화 |
|---|---|---|---|---|
| **1. SCM Polling (선택)** | Jenkins가 git ls-remote 주기적 호출 | ❌ | 1~2분 | ✅ |
| **2. GitHub Webhook → Jenkins** | git push 시 GitHub이 Jenkins URL로 POST | ✅ (Jenkins 노출) | 즉시 | ❌ |
| **3. GitHub Webhook → CF Tunnel** | webhook → cloudflared → Jenkins | ❌ (outbound tunnel) | 즉시 | ✅ |
| **4. GitHub Actions self-hosted runner** | Runner Pod이 GHA service에 outbound poll | ❌ | 즉시 | ✅ |
| **5. Jenkins JNLP inbound agent** | Agent → Jenkins controller 연결 | ❌ | 즉시 | ✅ |

### 각 모드의 본질

**SCM Polling**은 가장 단순하다. Jenkins가 2분마다 git server에 "최신 commit hash 알려줘" 요청을 보내고, 이전과 다르면 빌드 트리거한다. 외부에서 어떤 inbound도 필요 없어 firewall/NAT 친화적이다. 단점은 1~2분 지연이다.

**GitHub Webhook → Jenkins** 직접 패턴은 git push 시 GitHub이 Jenkins URL로 HTTP POST를 보낸다. 즉시 트리거되지만, **Jenkins URL이 외부에 노출돼야** GitHub이 도달할 수 있다. 강의장 NAT 뒤면 이게 불가능하다.

**GitHub Webhook → CF Tunnel** 은 NAT 우회 패턴이다. cloudflared가 outbound로 CF에 tunnel을 만들고, GitHub은 CF의 public URL로 webhook을 보낸다. CF가 tunnel을 통해 우리 Jenkins로 전달한다. 즉시 + NAT 친화적이지만 CF SaaS 의존성이 추가된다.

**GitHub Actions self-hosted runner** 패턴은 Runner Pod이 GHA service에 outbound로 long-polling 한다. job이 queue에 오면 runner가 받아서 실행한다. Jenkins를 안 쓰고 GHA로 가는 모던 패턴인데, ARC (Action Runner Controller)의 함정이 복잡하다.

**Jenkins JNLP inbound agent** 패턴은 Agent VM이 Jenkins controller에 outbound로 연결하는 전통적 방식이다. controller가 외부에 노출되든 말든 무관하지만, agent VM 관리 부담이 있다.

---

## 💡 왜 SCM Polling?

### 1. 외부 노출 0

> 🔥 가장 큰 이유다. **Jenkins는 내부 도메인 (jenkins.kosa.team2)으로만 접근**하고 외부엔 노출 안 된다.

Webhook 패턴이면 Edge HAProxy에 jenkins-webhook 경로를 외부에 노출해야 한다. 그러면 공격 표면이 늘고, GitHub IP allowlist + HMAC 검증 같은 보호 layer를 추가해야 한다. Polling은 이 부담이 0이다.

### 2. NAT 친화

강의장 NAT 뒤라 GitHub이 우리 Jenkins로 inbound 못 한다. **Polling은 Jenkins가 outbound** (git ls-remote)라 NAT 무관하다. 환경 의존성이 없다는 점이 큰 장점이다.

### 3. 즉시 트리거 필요성이 적다

빌드 자체가 5~10분 걸리니, polling 지연 1~2분은 작은 비율이다. 진짜 즉시 트리거가 critical한 시나리오는 (예: ChatOps 봇이 deploy 명령) 별도라 우리 일반 CI flow엔 충분하다.

### 4. 설정 단순

Webhook은 GitHub repo 설정 + Jenkins 외부 노출 + SSL + IP allowlist 등 여러 layer 작업이 필요하다. Polling은 Jenkins job에 cron 한 줄 (`H/2 * * * *`) 추가만 한다.

---

## 💰 비용 비교 (월간)

| 모드 | Jenkins | 외부 추가 컴포넌트 |
|---|---|---|
| Polling | 자체 | 0 |
| Webhook + Edge HAProxy 노출 | 자체 | 0 (이미 있음) |
| Webhook + CF Tunnel | 자체 | $0 (CF 무료) |
| GHA self-hosted runner (ARC) | + ARC controller (~256MB) | 0 |
| JNLP agent | + agent process | 0 |

비용 차이는 거의 없다. **운영 부담 + 보안 trade-off**가 진짜 결정 요소다.

---

## ⚖️ Trade-off

### Polling 선택의 잃은 것

| 잃은 것 | 의미 |
|---|---|
| 즉시 트리거 (1~2분 지연) | 데모/학습엔 무시 가능 |
| git API 호출 부하 | private repo는 rate limit 5000/h → 영향 X |
| 사용자 push에 대한 즉시 feedback | 빌드 끝나는 데 5~10분이라 1~2분 지연은 작음 |

### 사실 모든 잃은 게 작다

이 trade-off들이 작은 이유는 우리 use case가 **batch-like** (한 번에 큰 빌드)이기 때문이다. 만약 매초 commit이 발생하는 진짜 hot한 개발 환경이면 polling 지연이 누적 부담이 클 수 있는데, 우리는 그렇지 않다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Jenkins 죽음** | 모든 모드 영향 | Pod 재시작 |
| **GitHub API rate limit** | Polling 실패 (rate limit hit) | polling 주기 늘림 (`H/5` = 5분) |
| **Git server 죽음** | 빌드 트리거 X (git fetch 실패) | git 회복 (GitHub down은 매우 드뭄) |

Jenkins 자체 죽음이 가장 중요한 SPoF인데, 이건 모든 trigger 모드 공통이다. polling-specific 위험은 git API rate limit인데, private repo authenticated 기준 5000/h라 polling 2분마다 (~720/h)는 안전 margin이 크다.

---

## 🚀 확장 가능성

### Option A: ⭐ Polling + Webhook 병행 (off-prem 환경 이동 후)

NAT가 풀린 환경 (off-prem 이전 후)에 가면 Webhook을 추가할 수 있다. **Webhook으로 즉시 트리거하고, Polling은 fallback** 역할로 둔다. Webhook이 어떤 이유로 (GitHub 일시 장애 등) 실패해도 Polling이 catch-up한다.

- 🎯 **추천 시점**: off-prem 환경 진입 후

### Option B: CF Tunnel로 Webhook (NAT 우회)

NAT 환경에서도 즉시 트리거 원하면 CF Tunnel로 가능하다. cloudflared가 bastion에서 outbound tunnel을 만들고, GitHub은 CF의 public URL로 webhook 보낸다. **단점은 CF SaaS 의존성** 추가.

- 🎯 **추천 시점**: NAT 환경 + 즉시 트리거 critical

### Option C: GHA self-hosted runner로 마이그레이션

Jenkins 자체를 GHA로 바꾸는 큰 변경. 우리가 시도했다가 ARC fsGroup 함정으로 후퇴한 옵션이다. 학습 가치는 있지만 ROI가 안 맞아 보류 상태.

### Option D: Polling 주기 조정 (현재 2분)

빌드 빈도에 맞춰 주기를 튜닝할 수 있다. **1분 = git API rate limit 주의**, **5분 = 더 여유롭지만 지연 ↑**. 현재 2분은 안전한 default.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| off-prem 환경 진입 | A or B |
| 진짜 즉시 트리거 필요 | A (Polling fallback) |
| 빌드 빈도 ↓ | D (5분으로 늘림) |

---

## 🔗 다른 파트와의 연결

이 trigger 결정은 `01-jenkins-vs-github-actions.md`의 더 큰 도구 선택과 직결된다. 보안 측면에선 Webhook 도입 시 IP allowlist + HMAC 인증이 필요한데, 이건 `security/06-burst-trigger-security.md` 패턴과 유사하다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Polling 1~2분 지연이 별로 안 좋은 거 아닌가요?**

A. **데모/학습 환경엔 충분**합니다. 빌드 자체가 5~10분 걸리니 polling 지연이 작은 비율입니다. 진짜 즉시 필요하면 Option B (CF Tunnel webhook)로 즉시화 가능합니다. 우리 use case가 batch-like (큰 commit 가끔)이라 polling이 잘 맞습니다.

**Q2. git API rate limit이 위험하지 않나요?**

A. **GitHub private repo authenticated = 5000 req/h**입니다. Polling 2분마다 = 720 req/h 정도라 안전 margin이 ★★★★ 큽니다. 한 polling이 여러 API 호출이지만 rate limit에 걸릴 가능성은 매우 낮습니다.

**Q3. Webhook이 더 좋은 이유는요?**

A. **즉시성** (지연 0), **git API 호출 0** (rate limit 무관), **PR에 즉각 build status 표시** (GitHub UI 통합). 단점은 Jenkins 외부 노출 + 보안 위험입니다. trade-off라 환경에 따라 다릅니다.

**Q4. ARC Runner 시도했다고 하셨는데 어디서 실패?**

A. Controller 설치 OK, Runner Pod 시작 OK, **워크플로 실행 시 PVC fsGroup 1001 권한 거부**. 학습 시간 ↑ vs 결과 ↓라 Jenkins로 후퇴했습니다. 트러블슈팅 경험 자체는 가치 있었습니다.

**Q5. JNLP inbound agent 모드는 왜 안 썼나요?**

A. **JNLP는 별도 agent VM 관리 부담**이 있습니다. 우리는 K8s dynamic agent (K8s plugin이 Kaniko + git Pod를 동적 생성)로 더 자동화했습니다. JNLP는 K8s가 없는 전통 환경에서 좋은 패턴입니다.
