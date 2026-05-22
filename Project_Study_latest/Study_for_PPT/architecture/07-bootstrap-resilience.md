# 07. Bootstrap 의존성 + CI/CD K8s 의존 문제

> ⭐ **한 줄 요약**: 우리는 **모든 서비스가 K8s 위에** 올라가 있음 (Jenkins/ArgoCD 포함). K8s가 죽으면 → K8s 살리는 도구(Jenkins)도 죽음 → **순환 의존성**. 정직한 약점 + 개선 옵션.

---

## 🚨 문제 정의

### 1️⃣ 모든 서비스가 K8s 위에
```
온프레 인프라:
  Proxmox 4
  Ceph 6
  pfSense HA (VM)
  bastion (VM)
  lb-1, lb-2 (VM)
  edge-haproxy × 2 (VM)
  k8s-cp × 3 (VM)
  k8s-w × 3 (VM)
  k8s-sys1 (VM)
       │
       └── 그 위에 K8s 설치
              │
              └── K8s 안에:
                    ✅ ticket-app (정상)
                    ✅ PXC, Redis (DB layer)
                    ❓ Jenkins (배포 도구)
                    ❓ ArgoCD (GitOps controller)
                    ❓ Harbor (이미지 레지스트리)
                    ❓ Prometheus/Grafana (모니터링)
                    ❓ Tempo/Loki (관측성)
                    ❓ cert-manager (TLS)
```

❓로 표시된 것들 = **K8s 자체를 살리거나 운영하는 데 필요한 도구들**

### 2️⃣ 순환 의존성 (Circular Dependency)
```
[K8s 죽음] → [Jenkins 죽음] → [코드 배포 불가] → [K8s fix 못 함]
              [ArgoCD 죽음] → [Sync 불가]
              [Harbor 죽음] → [이미지 못 pull]
              [Prometheus 죽음] → [상태 진단 불가]
              [cert-manager 죽음] → [TLS cert 갱신 불가]
                    │
                    └── 모든 게 같이 죽음 = bootstrap 도구 X
```

### 3️⃣ 실제 시나리오 (위험도 ★★★★)
**가정**: sys1 노드가 죽었다 (디스크 fail). K8s sys1 NotReady.

**결과**:
- Jenkins down → 코드 배포 X
- ArgoCD down → manifest sync X
- Harbor down → 새 이미지 pull X (cached image만 가능)
- Prometheus/Grafana down → 진단 도구 X

**복구 절차**:
1. sys1 VM 수동 회복 (Proxmox에서 disk 교체 + restart)
2. Pod 재schedule 대기 (5분)
3. cert-manager 재기동 후 cert 검증
4. Harbor 회복 후 image pull 가능
5. ArgoCD 회복 후 다른 service sync
6. Jenkins 회복 후 새 빌드 가능

→ **모든 도구가 자기 자신을 못 살림** (사람 + Proxmox UI에 의존)

---

## 💡 왜 이렇게 됐나?

### 학습 환경 우선순위
1. **K8s 학습 가치 ★★★★★** = 모든 것 K8s에 올림
2. **운영 단순화** = single management plane (kubectl)
3. **GitOps 일관성** = ArgoCD가 모든 것 관리
4. **자원 효율** = VM 분리하면 메모리 ★★★

### 실용 vs 안전 trade-off
- **실용** (K8s 통합) → 운영 편의 ★★★★, GitOps 일관성
- **안전** (CI/CD 분리) → bootstrap 안전, but 운영 부담 ↑

→ **학습/데모는 실용 우선**, 운영급은 안전 우선.

---

## 🔍 다른 회사들은 어떻게 하나?

| 회사 패턴 | CI/CD 배치 | 모니터링 배치 |
|---|---|---|
| **Netflix** | Spinnaker는 별도 EC2 fleet | Atlas/Mantis는 별도 |
| **Google** | Borg는 자기 자신을 관리 (circular OK, 다른 안전망) | 다중 region |
| **소규모 스타트업** | GitHub Actions cloud (외부 SaaS) | Datadog (SaaS) |
| **온프레 enterprise** | Jenkins 별도 VM, ArgoCD K8s | Prometheus K8s, 모니터링 일부 외부 |
| **우리 (학습)** | 다 K8s 위 (단순) | 다 K8s 위 (단순) |

→ **별도 분리가 정석**, 하지만 운영 부담 ↑

---

## 🚀 해결 옵션 (5가지)

### Option A: ⭐ CI/CD를 별도 VM에 (Bootstrap 보호)
```
[추가 VM 2대]
  - cicd-1: Jenkins (master) + 자체 ArgoCD CLI
  - cicd-2: 백업/HA용 (선택)
  - bastion에 ArgoCD 설치 (현재 K8s 안 → 외부로)
```

**작업**:
1. Proxmox에 VM 1대 (4vCPU, 8GB RAM) 추가
2. Ansible playbook으로 Jenkins 설치 (Java + Jenkins WAR)
3. 기존 Jenkinsfile 그대로 사용 가능 (K8s plugin은 그대로)
4. ArgoCD CLI를 bastion에 설치 (UI는 K8s 안에 유지하되 emergency CLI도)

- ✅ **장점**: K8s 죽어도 Jenkins로 배포 가능 (emergency)
- ❌ **단점**: VM 1대 운영, K8s plugin 통한 빌드 격리 유지
- 💰 **비용**: VM 1대 (호스트 자원만), 0
- ⏱️ **작업**: 1~2일
- 🎯 **추천 시점**: Phase 6 우선

### Option B: 핵심 도구만 VM 분리 (선택적)
- Jenkins → VM
- ArgoCD → K8s (그대로, K8s 회복 시 자동)
- Harbor → VM (Docker-compose 또는 podman)
- 나머지 (Prometheus/Tempo/Loki) → K8s 유지

- ✅ **장점**: 진짜 critical만 분리, 자원 절감
- 🎯 **추천 시점**: 운영급 진입

### Option C: SaaS로 위탁 (GitHub Actions, Datadog)
- Jenkins → GitHub Actions cloud
- 모니터링 → Datadog/New Relic
- ArgoCD → 그대로 또는 Flagger SaaS
- ✅ **장점**: 운영 부담 0
- ❌ **단점**: 외부 의존, 비용 ↑, 데이터 주권 X
- 💰 **비용**: GHA $40/월, Datadog $200/월
- 🎯 **추천 시점**: 학습 환경에선 비추, 진짜 운영에선 검토

### Option D: ⭐ Disaster Recovery Runbook + 정기 훈련
- VM 분리 안 하더라도 **체계적 복구 절차** 문서화
- 분기별 disaster recovery drill (실제 K8s 죽이고 복구 시간 측정)
- etcd backup → restore → ArgoCD bootstrap 자동화 스크립트
- ✅ **장점**: 비용 0, 운영 역량 ↑
- ⏱️ **작업**: 1주 (문서 + 자동화)
- 🎯 **추천 시점**: 즉시 (옵션 A와 병행 권장)

### Option E: Multi-cluster (관리 클러스터 + 워크로드 클러스터)
- 관리 클러스터 (k8s-mgmt, 별도 노드): ArgoCD, Jenkins, Harbor
- 워크로드 클러스터: ticket-app, PXC, Redis
- 관리 클러스터가 워크로드 클러스터를 GitOps로 관리
- ✅ **장점**: 워크로드 클러스터 죽어도 관리 클러스터 살아있음 → 즉시 복구
- ❌ **단점**: K8s 클러스터 2개 운영
- 🎯 **추천 시점**: 진짜 운영급 + 여러 워크로드 클러스터

---

## 📊 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 학습/데모 환경 | D (Runbook만) |
| Phase 6 운영 진입 | A (Jenkins VM 분리) + D |
| 진짜 운영 + critical | B (선택적 분리) |
| 비용 무관 + 운영 편의 | C (SaaS) |
| 여러 클러스터 운영 | E (Multi-cluster) |

---

## 💰 비용 비교

| 옵션 | CapEx | OpEx |
|---|---|---|
| 현재 (모두 K8s) | 0 | 0 |
| A (Jenkins VM 분리) | 0 (Proxmox 자원) | 0.05 FTE 추가 |
| B (3개 분리) | 0 | 0.1 FTE 추가 |
| C (SaaS) | 0 | $240/월 |
| D (Runbook) | 0 | 1주 작업 |
| E (Multi-cluster) | ★★★★ (노드 추가) | 0.2 FTE 추가 |

---

## ⚠️ 발표 시 솔직 어필 포인트

> "**모든 서비스가 K8s 위에 있는 것은 학습 환경 단순화 선택이고, 진짜 운영급으로 가려면 CI/CD VM 분리 + DR runbook이 필수**. 우리는 이 한계를 인지하고 Phase 6 우선 작업으로 명시했다."

이렇게 말하면 면접관은:
- "약점 인지 ★★★★★" (성숙도)
- "개선 계획 명확 ★★★★" (실무 감각)
- "트레이드오프 의식적 ★★★★★" (엔지니어링 사고)

→ **약점 숨기지 말고 솔직히 + 개선 계획으로 어필**.

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 자기 (`06-cost-spof-tradeoffs.md`) | SPoF 표에 #13 (모든 게 K8s 위), #14 (CI/CD K8s 의존) 추가 |
| 🏛️ 자기 (`08-onprem-autoscaling.md`) | 노드 자동 확장 (CI/CD 분리하면 그쪽으로) |
| 🔧 CI/CD | Jenkins 배치 결정 |
| 🔒 보안 (`08-backup-dr-policy.md`) | DR 시나리오와 직결 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 모든 게 K8s 위에 있으면 K8s 죽으면 어떻게?**
A. 솔직한 약점. (1) K8s 자체 복구는 etcd backup → restore (Phase 6), (2) Jenkins/ArgoCD는 별도 VM 분리 권장 (Option A), (3) Disaster runbook 작성 + 분기 훈련. **현재 학습 환경엔 단순화 선택, 운영 진입 시 분리.**

**Q2. ArgoCD가 자기 자신도 관리하나?**
A. 네 — `argocd-operator` Application이 자기를 manage. K8s 죽으면 ArgoCD도 죽음. 회복: bastion에 ArgoCD CLI 설치 → emergency 시 사용. 또는 helm install argocd 다시.

**Q3. K8s 죽었을 때 복구 RTO 목표?**
A. 우리 목표 4시간 (etcd backup → restore → ArgoCD bootstrap → 모든 service 회복). 실제 측정은 분기별 훈련으로. 진짜 운영급은 1시간 이내 + Multi-cluster.

**Q4. Jenkins 분리하면 어떻게 K8s에 빌드 push?**
A. Jenkins VM에서 kubectl 사용 → K8s plugin으로 agent Pod 생성. K8s API VIP 죽으면 Jenkins도 영향 (빌드 큐잉). 그래도 Jenkins controller는 살아있음 → K8s 회복 후 즉시 동작.

**Q5. 학습 환경에서 굳이 분리 안 한 게 트레이드오프 의식?**
A. 네. (1) sys1 단일 노드 운영, (2) VM 추가 = 자원 ↑, (3) 운영 부담 ↑. **데모/발표엔 단순함 우선 + 약점 인지**. 운영 진입 시 분리.

**Q6. CI/CD VM 분리하면 GitOps 일관성 깨지나?**
A. ArgoCD는 그대로 K8s 안. Jenkins만 VM. Jenkins는 image build + git update만. ArgoCD가 git → cluster sync는 그대로. **bootstrap 보호 + GitOps 유지 동시 가능**.
