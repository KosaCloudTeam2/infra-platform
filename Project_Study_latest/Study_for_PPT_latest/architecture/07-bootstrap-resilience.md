# 07. Bootstrap 의존성 + CI/CD K8s 의존 문제

> ⭐ **한 줄 요약**: 우리는 **Jenkins, ArgoCD, Harbor 같은 운영 도구들을 K8s 위에 올렸다**. 편리하지만 K8s가 죽으면 그 K8s를 살릴 도구도 같이 죽는 **순환 의존성**이 생긴다. 솔직히 인지하고 있는 약점이고 Phase 6에서 CI/CD VM 분리 + DR runbook으로 해소할 계획이다.

---

## 🚨 문제 정의

### 1️⃣ 모든 서비스가 K8s 위에

우리 인프라의 전체 그림을 그려보면, 가상화 layer (Proxmox)와 스토리지 layer (Ceph)는 K8s 밖에 있지만 그 외 거의 모든 운영 도구가 K8s 안에 들어 있다.

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

ticket-app과 DB는 K8s에 있는 게 자연스럽다. 비즈니스 워크로드니까. 그런데 **❓로 표시된 것들 — Jenkins, ArgoCD, Harbor, 모니터링 — 이게 K8s 자체를 살리거나 운영하는 데 필요한 도구들**이다. 이걸 K8s 안에 두면 어떻게 될까?

### 2️⃣ 순환 의존성 (Circular Dependency)

K8s가 죽으면 chain reaction이 발생한다.

```
[K8s 죽음]
   ↓
[Jenkins 죽음] → 코드 배포 불가 → K8s fix 못함
[ArgoCD 죽음] → Sync 불가
[Harbor 죽음] → 이미지 못 pull
[Prometheus 죽음] → 상태 진단 불가
[cert-manager 죽음] → TLS cert 갱신 불가
   ↓
모든 게 같이 죽음 = bootstrap 도구 X
```

**도구가 자기 자신을 못 살린다.** 사람이 Proxmox UI에 직접 접속해서 K8s 노드부터 살려야 한다. Jenkins로 fix를 자동 배포하고 싶어도 Jenkins 자체가 죽어 있다.

### 3️⃣ 실제 위험 시나리오 (위험도 ★★★★)

**가정**: sys1 노드가 죽었다 (디스크 fail). 위에서 본 system 워크로드들이 모두 down.

**결과**:
- Jenkins down → 새 코드 배포 불가
- ArgoCD down → manifest sync 불가
- Harbor down → 새 이미지 pull 불가 (cached image만)
- Prometheus/Grafana down → 진단 도구 X

**복구 절차**:
1. sys1 VM 수동 회복 (Proxmox에서 disk 교체 + restart)
2. Pod 재schedule 대기 (5분)
3. cert-manager 재기동 후 cert 검증
4. Harbor 회복 후 image pull 가능
5. ArgoCD 회복 후 다른 service sync
6. Jenkins 회복 후 새 빌드 가능

→ **모든 도구가 자기 자신을 못 살린다**는 게 본질적 약점이다.

---

## 💡 왜 이렇게 됐나?

이 순환 의존성을 모르고 한 건 아니다. **의식적 trade-off**의 결과다.

**학습 환경 우선순위**가 K8s 학습 가치를 최대화하는 쪽으로 기울었다. 모든 것을 K8s에 올리면 (1) **K8s 학습 가치 ★★★★★**, (2) **운영 단순화** (single management plane, kubectl 하나면 끝), (3) **GitOps 일관성** (ArgoCD가 모든 것 관리), (4) **자원 효율** (VM 분리하면 메모리 ↑).

**실용 vs 안전 trade-off**의 결정이었다.

| 측면 | 실용 (K8s 통합) | 안전 (CI/CD 분리) |
|---|---|---|
| 운영 편의 | ★★★★ | ★★★ |
| GitOps 일관성 | ★★★★ | ★★ |
| Bootstrap 안전 | ★ | ★★★★★ |
| 자원 효율 | ★★★★ | ★★★ |

학습/데모 환경엔 실용이 우선이지만, 진짜 운영급은 안전이 우선이다. 우리는 학습 환경이라 실용을 골랐고, 약점을 인지하고 Phase 6에 분리 계획을 잡았다.

---

## 🔍 다른 회사들은 어떻게 하나?

업계 표준을 보면 어떻게 다루는지 참고할 수 있다.

| 회사 패턴 | CI/CD 배치 | 모니터링 배치 |
|---|---|---|
| **Netflix** | Spinnaker는 별도 EC2 fleet | Atlas/Mantis는 별도 |
| **Google** | Borg는 자기 자신을 관리 (circular OK, 다른 안전망) | 다중 region |
| **소규모 스타트업** | GitHub Actions cloud (외부 SaaS) | Datadog (SaaS) |
| **온프레 enterprise** | Jenkins 별도 VM, ArgoCD K8s | Prometheus K8s, 모니터링 일부 외부 |
| **우리 (학습)** | 다 K8s 위 (단순) | 다 K8s 위 (단순) |

**별도 분리가 정석**이다. Netflix는 Spinnaker (deploy tool)를 EC2 fleet에 따로 두고, Google은 Borg가 자기 자신을 관리하긴 하지만 multi-region + 추가 안전망이 있다. 소규모 스타트업은 SaaS로 위탁 (운영 부담 0). 온프레 enterprise는 일부 critical 도구만 VM 분리하는 hybrid가 일반적이다.

---

## 🚀 해결 옵션 (5가지)

### Option A: ⭐ CI/CD를 별도 VM에 (Bootstrap 보호)

가장 현실적인 옵션이다. **Jenkins controller를 VM으로 옮기고**, Jenkins K8s plugin은 그대로 둬서 빌드 agent는 K8s 안에서 생성된다. ArgoCD는 K8s 안에 두되 **emergency용 ArgoCD CLI를 bastion에 설치**해서 K8s 죽었을 때 git에서 manifest를 직접 apply 가능하게 한다.

```
[추가 VM 1대]
  - cicd-1: Jenkins (master)
  - bastion에 ArgoCD CLI 설치 (UI는 K8s 안 유지)
```

**작업 절차**:
1. Proxmox에 VM 1대 (4vCPU, 8GB RAM) 추가
2. Ansible playbook으로 Jenkins 설치 (Java + Jenkins WAR)
3. 기존 Jenkinsfile 그대로 사용 가능 (K8s plugin은 그대로)
4. ArgoCD CLI를 bastion에 설치 + kubeconfig

이러면 K8s가 죽어도 Jenkins controller는 살아있어서, emergency 시 emergency build를 돌릴 수 있다.

- 💰 **비용**: VM 1대 (호스트 자원만), 0
- ⏱️ **작업**: 1~2일
- 🎯 **추천 시점**: Phase 6 우선

### Option B: 핵심 도구만 VM 분리 (선택적)

모든 도구를 VM으로 옮기진 않고, **진짜 critical만 분리**. Jenkins와 Harbor는 VM, ArgoCD와 모니터링은 K8s 유지. 자원 절감과 안전 사이의 균형.

- 🎯 **추천 시점**: 운영급 진입

### Option C: SaaS로 위탁 (GitHub Actions, Datadog)

운영 부담을 0으로 만드는 옵션. Jenkins → GitHub Actions cloud, 모니터링 → Datadog. **외부 의존 + 비용 발생**이 단점이지만 운영 인건비를 크게 절감.

- 💰 **비용**: GHA $40+/월, Datadog $200+/월
- 🎯 **추천 시점**: 학습 환경 비추, 진짜 운영급에서 검토

### Option D: ⭐ Disaster Recovery Runbook + 정기 훈련

**VM 분리 안 하더라도 체계적 복구 절차를 문서화**하는 접근. 분기별로 K8s를 일부러 죽이고 복구 시간을 측정하는 disaster recovery drill을 진행한다. etcd backup → restore → ArgoCD bootstrap을 자동화 스크립트로 만들어두면 사고 시 단순 실행으로 복구 가능.

- 💰 **비용**: 0
- ⏱️ **작업**: 1주 (문서 + 자동화)
- 🎯 **추천 시점**: 즉시 (Option A와 병행 권장)

### Option E: Multi-cluster (관리 클러스터 + 워크로드 클러스터)

진짜 운영급 패턴이다. **관리 클러스터** (k8s-mgmt, 별도 노드)에 ArgoCD, Jenkins, Harbor를 두고, **워크로드 클러스터**에 비즈니스 워크로드를 둔다. 관리 클러스터가 워크로드 클러스터를 GitOps로 관리. 워크로드 클러스터가 죽어도 관리 클러스터는 살아있어 즉시 복구 가능.

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
| C (SaaS) | 0 | $240+/월 |
| D (Runbook) | 0 | 1주 작업 |
| E (Multi-cluster) | ★★★★ (노드 추가) | 0.2 FTE 추가 |

비용 측면에선 Option A가 가장 부담 적다. Proxmox 자원만 쓰고 운영 부담도 0.05 FTE 정도. Option C (SaaS)는 운영 부담 0인 대신 월 $240+이 누적적.

---

## ⚠️ 발표 시 솔직 어필 포인트

> "**모든 서비스가 K8s 위에 있는 것은 학습 환경 단순화 선택이고, 진짜 운영급으로 가려면 CI/CD VM 분리 + DR runbook이 필수**. 우리는 이 한계를 인지하고 Phase 6 우선 작업으로 명시했다."

이렇게 말하면 면접관이 평가하는 건 다음과 같다:
- **약점 인지 ★★★★★** (성숙도)
- **개선 계획 명확 ★★★★** (실무 감각)
- **트레이드오프 의식적 ★★★★★** (엔지니어링 사고)

→ **약점 숨기지 말고 솔직히 + 개선 계획으로 어필**하는 게 면접에서 가장 강력한 패턴이다.

---

## 🔗 다른 파트와의 연결

이 문제는 다른 파트에도 영향을 준다. `06-cost-spof-tradeoffs.md`의 SPoF 표에 #13 (모든 게 K8s 위), #14 (자동 프로비저닝 없음)으로 추가돼 있다. `08-onprem-autoscaling.md`는 노드 자동 확장 문제를 다루는데, CI/CD 분리 후엔 그 자동화도 더 안전해진다. CI/CD 파트의 Jenkins 배치 결정과 직결되고, 보안 파트의 backup/DR 정책 (`security/08-backup-dr-policy.md`)과도 연결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 모든 게 K8s 위에 있으면 K8s가 죽으면 어떻게 되나요?**

A. **솔직한 약점입니다**. 세 가지 대응이 있는데요. **첫째**, K8s 자체 복구는 etcd backup → restore (Phase 6 계획). **둘째**, Jenkins/ArgoCD는 별도 VM 분리 권장 (Option A). **셋째**, Disaster runbook 작성 + 분기 훈련. **현재 학습 환경엔 단순화 선택**이고, 운영 진입 시 분리를 우선 작업으로 잡았습니다.

**Q2. ArgoCD가 자기 자신도 관리하나요?**

A. **네 — `argocd-operator` Application이 자기를 manage**합니다. K8s가 죽으면 ArgoCD도 죽고요. 회복은 (1) bastion에 ArgoCD CLI 설치해서 emergency 시 사용, 또는 (2) helm install argocd 다시 실행. Multi-cluster 패턴 (Option E)이면 관리 클러스터가 살아있어 즉시 복구 가능합니다.

**Q3. K8s 죽었을 때 복구 RTO 목표는?**

A. **우리 목표 4시간**입니다 (etcd backup → restore → ArgoCD bootstrap → 모든 service 회복). 실제 측정은 분기별 훈련으로 검증. 진짜 운영급은 1시간 이내 + Multi-cluster 패턴이 표준입니다.

**Q4. Jenkins 분리하면 어떻게 K8s에 빌드 push하나요?**

A. **Jenkins VM에서 kubectl 사용** → K8s plugin으로 agent Pod 생성. 즉 Jenkins controller만 VM에 있고 빌드 agent는 여전히 K8s 안에서 동적 생성됩니다. K8s API VIP 죽으면 빌드 큐잉되지만 Jenkins controller는 살아있어 K8s 회복 후 즉시 빌드 가능합니다.

**Q5. 학습 환경에서 굳이 분리 안 한 게 트레이드오프 의식인가요?**

A. **네**. (1) sys1 단일 노드 운영 자원 빡빡, (2) VM 추가 = 자원 ↑, (3) 운영 부담 ↑. **데모/발표엔 단순함 우선 + 약점 인지** 패턴을 의식적으로 골랐습니다. 운영 진입 시 분리하는 게 표준이고, 우리는 Phase 6에서 그 작업을 우선순위 ★★★★로 잡았습니다.

**Q6. CI/CD VM 분리하면 GitOps 일관성이 깨지지 않나요?**

A. **ArgoCD는 그대로 K8s 안 유지**합니다. Jenkins만 VM으로 옮깁니다. Jenkins는 image build + git에 tag update만 담당하고, **ArgoCD가 git → cluster sync하는 부분은 그대로** 동작합니다. Bootstrap 보호 + GitOps 유지 동시에 가능합니다.
