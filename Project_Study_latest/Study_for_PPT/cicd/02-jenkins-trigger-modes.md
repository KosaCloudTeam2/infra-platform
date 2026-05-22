# 02. Jenkins Trigger 모드 — SCM Polling vs Webhook vs Self-hosted Runner

> ⭐ **한 줄 요약**: **SCM Polling 선택** (외부 노출 0, NAT 친화). Webhook은 외부 노출 필요, Runner는 ARC 학습 비용. 우리 환경엔 Polling이 합리적.

---

## 🎯 우리가 선택한 모드

**Jenkins SCM Polling** (`H/2 * * * *` — 2분마다 git fetch + 비교)

---

## 🔍 5개 모드 비교

| 모드 | 동작 | 외부 노출 | 지연 | 부하 | NAT 친화 |
|---|---|---|---|---|---|
| **1. SCM Polling (선택)** | Jenkins가 git ls-remote 주기적 호출 | ❌ | 1~2분 | git API 호출 (rate limit 주의) | ✅ |
| **2. GitHub Webhook → Jenkins** | git push 시 GitHub이 Jenkins URL로 POST | ✅ (Jenkins 노출) | 즉시 | 0 | ❌ (외부 노출 필요) |
| **3. GitHub Webhook → CF Tunnel** | webhook → cloudflared tunnel → Jenkins | ❌ (outbound tunnel) | 즉시 | cloudflared 1 process | ✅ |
| **4. GitHub Actions self-hosted runner** | Runner Pod이 GHA service에 outbound poll | ❌ | 즉시 | ARC controller | ✅ |
| **5. Jenkins JNLP inbound agent** | Agent → Jenkins controller 연결 | ❌ (agent outbound) | 즉시 | agent 1 process | ✅ |

---

## 💡 왜 SCM Polling?

### 1. 🔒 **외부 노출 0**
- Webhook은 Jenkins를 외부에 노출 = 공격 표면 ↑
- Polling은 Jenkins가 outbound → 0 노출

### 2. 🌐 **NAT 친화** (강의장 환경)
- 강의장 NAT 뒤 → GitHub이 우리 Jenkins로 inbound 불가
- Polling은 무관

### 3. 🎯 **즉시 트리거 필요성 ↓**
- 우리 demo는 1~2분 지연 OK
- 진짜 운영도 deploy는 즉시 트리거 + 빌드 끝나는 데 5~10분 → polling 지연은 무시 가능

### 4. ⚙️ **설정 단순**
- Webhook = GitHub repo 설정 + Jenkins 노출 + SSL + IP allowlist
- Polling = Jenkins job에 cron 한 줄

---

## 💰 비용 비교 (월간)

| 모드 | Jenkins | 외부 추가 컴포넌트 |
|---|---|---|
| Polling | 자체 | 0 |
| Webhook + Edge HAProxy 노출 | 자체 | 0 (이미 있음) |
| Webhook + CF Tunnel | 자체 | $0 (CF 무료) |
| GHA self-hosted runner (ARC) | + ARC controller (~256MB) | 0 |
| JNLP agent | + agent process | 0 |

→ 비용은 모두 비슷. **운영 부담 + 보안 trade-off가 핵심**.

---

## ⚖️ Trade-off

### Polling 선택의 잃은 것
| 잃은 것 | 의미 |
|---|---|
| 즉시 트리거 (1~2분 지연) | 데모/학습엔 무시 가능 |
| git API 호출 부하 | private repo는 rate limit 5000/h → 영향 X |
| 사용자 push에 대한 즉시 feedback | 빌드 끝나는 데 5~10분이라 1~2분 지연은 작음 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Jenkins 죽음** | 모든 모드 영향 | Pod 재시작 |
| **GitHub API rate limit** | Polling 실패 (rate limit hit) | polling 주기 늘림 (`H/5` = 5분) |
| **Git server 죽음** | 빌드 트리거 X (git fetch 실패) | git 회복 (GitHub down은 매우 드뭄) |

---

## 🚀 확장 가능성

### Option A: ⭐ Polling + Webhook 병행 (off-prem 환경 이동 후)
- ✅ **장점**: Webhook으로 즉시, Polling은 failover
- ❌ **단점**: Webhook 외부 노출 필요
- 🎯 **추천 시점**: off-prem 환경

### Option B: CF Tunnel로 Webhook (NAT 우회)
- ✅ **장점**: NAT 환경에서도 즉시 트리거
- ❌ **단점**: CF 의존 (외부 SaaS)
- 🎯 **추천 시점**: NAT 환경 + 즉시 트리거 원할 때

### Option C: GHA self-hosted runner로 마이그레이션
- ✅ **장점**: 모던, GitHub 통합
- ❌ **단점**: ARC fsGroup 함정, Jenkins 폐기
- 🎯 **추천 시점**: 큰 변경

### Option D: Polling 주기 조정 (현재 2분 → 1분 or 5분)
- 1분 = git API rate limit 주의
- 5분 = 더 여유롭지만 지연 ↑
- 🎯 **추천 시점**: 빌드 빈도에 맞춰 튜닝

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| off-prem 환경 진입 | A or B |
| 진짜 즉시 트리거 필요 | A (Polling fallback) |
| 빌드 빈도 ↓ | D (5분으로 늘림) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 자기 (`01-jenkins-vs-github-actions.md`) | trigger 선택은 도구 선택의 일부 |
| 🏛️ 아키텍처 | Edge HAProxy 외부 노출 정책 |
| 🔒 보안 | Webhook 시 IP allowlist, HMAC 인증 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Polling 1~2분 지연 별로 안 좋은 거 아닌가?**
A. 데모/학습 OK. 실제 빌드 5~10분이라 polling 지연은 작은 비율. 진짜 즉시 필요시 → Option B (CF Tunnel webhook).

**Q2. git API rate limit 위험?**
A. GitHub private repo authenticated = 5000 req/h. Polling 2분마다 = 720 req/h. 한 polling이 여러 API 호출이지만 안전 마진 ★★★★.

**Q3. Webhook이 더 좋은 이유?**
A. (1) 즉시, (2) git API 호출 0, (3) push에 즉각 PR check 표시. 단점은 Jenkins 외부 노출 + 보안 위험.

**Q4. ARC Runner 시도해봤다고?**
A. 네 — Controller 설치 OK, Runner Pod 시작 OK. 하지만 워크플로 실행 시 PVC fsGroup 1001 권한 거부. 학습 시간 ↑ 결과 ↓라 Jenkins로 후퇴. 트러블슈팅 경험 가치 있음.

**Q5. JNLP inbound agent 모드는 왜 안 썼나?**
A. JNLP는 별도 agent (보통 VM) 관리 부담. 우리는 K8s dynamic agent (Kaniko + git Pod template) 으로 더 자동화. JNLP는 K8s 없는 환경에선 좋음.
