# 🏛️ 아키텍처/설계 파트 — README

> 이 폴더의 문서들은 **전체 시스템 구조 + 핵심 설계 결정**을 다룸. 아키텍처 담당이 deep-dive하고, 다른 파트도 cross-reference로 참고.

---

## 📚 문서 목록

| # | 문서 | 핵심 토픽 | 페이지 추정 |
|---|---|---|---|
| 01 | `01-physical-and-network.md` | Proxmox 4 + Ceph 6, Spine-Leaf, pfSense HA, VLAN 4개 | ~8p |
| 02 | `02-kubernetes-design.md` | HA CP×3 + Worker×4, Calico IPIP, sys1+sys2 HA, MetalLB | ~10p |
| 03 | `03-aws-hybrid.md` | VPC + VPN + NLB + EC2 HAProxy 단일 진입점 | ~8p |
| 04 | `04-burst-architecture.md` | Prometheus → AM → Lambda → R53 → EKS Karpenter Spot | ~10p |
| 05 | `05-observability-design.md` | 3대축 (Metrics + Traces + Logs), AlertManager 라우팅, OTel 자동 계측 | ~10p |
| 06 | `06-cost-spof-tradeoffs.md` | 전체 TCO, SPoF 분석, sys2 HA, 확장 로드맵 | ~8p |

**총 ~54p** (markdown 기준)

---

## 🎯 학습 우선순위

### 1주차 — 기초
- 01 (물리/네트워크) + 02 (K8s)
- 다른 파트 README도 빠르게 훑기

### 2주차 — 통합
- 03 (AWS) + 04 (Burst)
- `99-cross-cutting.md` 정독

### 3주차 — 종합
- 05 (관측성) + 06 (비용/SPoF)
- 면접 질문 자가 테스트

---

## 🔑 아키텍처 담당이 마스터해야 할 7가지

> 발표/면접 100% 물어보는 것들:

1. **왜 Proxmox + K8s? (베어메탈 안 쓴 이유)**
   → 01 `## 💡 왜 이걸 선택했나`

2. **왜 Ceph 별도 클러스터?**
   → 01 + 데이터 파트 `data-storage/01-ceph-why.md`

3. **왜 stacked etcd? external etcd 안 쓴 이유**
   → 02

4. **sys1 SPoF + sys2 추가 시 어떻게 HA?**
   → 02 + 06

5. **Burst가 실제로 어떻게 동작하나? 전체 흐름**
   → 04

6. **관측성 3대축 왜 다 따로? 통합 솔루션 (Datadog 등) 안 쓴 이유**
   → 05

7. **이 인프라 월 비용은? 100% AWS 대비 절감?**
   → 06

---

## 🤝 다른 파트와의 연결

| 다른 파트 | 어떻게 연결 |
|---|---|
| 데이터/스토리지 | K8s에 어떤 storage class를 노출할지 (RBD/CephFS), Ceph 노드 네트워크 설계 |
| CI/CD | Jenkins/Harbor/ArgoCD를 어디 배치 (sys1), Resource quota |
| 보안 | DMZ vs Internal VLAN 분리, 이중 TLS topology, NetworkPolicy 강제 영역 |

---

## 🚀 미래 확장 — 아키텍처 담당이 고려해야 할 것

각 deep-dive 문서에 자세히 있지만 한눈에:

- **sys2 추가** (sys1 SPoF 해소) — Phase 6 우선순위
- **Ceph 노드 추가** (현재 6 → 8) 또는 SSD WAL/DB 분리 (성능 ↑)
- **EKS multi-cluster ArgoCD** (현재 onprem만 ArgoCD가 관리)
- **Service mesh (Istio/Linkerd)** — mTLS 자동화 + 트래픽 분석
- **Multi-region AWS** — DR을 위한 cross-region replica

---

## 🧪 자가 테스트 질문

```
□ Proxmox 4대 중 1대 죽으면? (pfSense는?)
□ K8s CP 1대 죽으면? (etcd quorum은?)
□ K8s API VIP 죽으면 어떻게 회복?
□ AWS VPN 양쪽 터널 다 끊기면?
□ Burst trigger가 안 됐을 때 어디부터 진단?
□ sys1 OOM 시 우선 살릴 것?
□ Edge HAProxy split-brain 회복 절차?
□ Ceph mon 1대 죽으면? 3대 다 죽으면?
□ R53 health check가 false positive 내면?
□ 새 서비스 배포 시 sys vs prod 어디 둘지 기준?
```

답이 막히면 해당 문서로 가서 확인.
