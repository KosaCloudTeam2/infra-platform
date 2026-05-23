# 00. 전체 아키텍처 개요

> ⭐ **한 줄 요약**: 온프레미스(Proxmox+Ceph+K8s) + AWS 하이브리드. 평시 100% 온프레, 트래픽 급증 시 Burst로 EKS에 분산한다. 4명 분담, GitOps 기반, 관측 3대 축 (Metrics+Traces+Logs)을 완성했다.

이 문서는 **4명 팀원 공통 reference**다. 본인 담당 파트로 들어가기 전에 전체 그림을 잡기 위한 것.

---

## 🗺️ 학습 문서 인덱스

전체 문서는 4파트 폴더 + 공통 2개로 구성된다.

```
docs/learning/
├── 00-overview.md                  ← 지금 여기 (4명 공통)
├── 99-cross-cutting.md             ← 파트 경계 넘는 토픽
│
├── architecture/                   ← 아키텍처/설계 담당
├── data-storage/                   ← 데이터/스토리지 담당
├── cicd/                           ← CI/CD 담당
└── security/                       ← 보안 담당
```

각 파트는 `README.md` + 5~8개 deep-dive 문서로 구성된다.

---

## 🎯 프로젝트 한 줄 정의

> "K8s 기반 온프레미스 인프라 위에 ticket-app(FastAPI)을 운영하면서, 트래픽 급증 시 자동으로 AWS EKS로 burst하는 하이브리드 클라우드."

이걸 가능하게 한 핵심 기술 스택을 정리하면 다음과 같다.

| 영역 | 도구 |
|---|---|
| 가상화 | **Proxmox VE** 4 노드 |
| 스토리지 | **Ceph** 6 노드 (BlueStore, RBD + RGW) |
| 컨테이너 오케스트레이션 | **Kubernetes 1.30** (HA CP×3 + Worker×4) |
| 방화벽/라우팅 | **pfSense HA** (CARP) |
| 네트워크 | **Spine-Leaf 10GbE** 패브릭 |
| GitOps | **ArgoCD** (App-of-Apps) |
| CI | **Jenkins** (Kaniko + K8s dynamic agent) |
| 레지스트리 | **Harbor** (Ceph RGW S3 백엔드) |
| 관측성 | **Prometheus + Grafana + AlertManager + Tempo + Loki + OpenTelemetry** |
| 보안 | **자체 CA + 이중 TLS + NetworkPolicy + cert-manager** |
| AWS | **VPC + VPN + NLB + EC2 HAProxy + EKS Karpenter Spot + RDS Read Replica + Route 53** |

---

## 🏗️ 아키텍처 다이어그램 (전체)

전체 흐름을 한 페이지에 그리면 다음과 같다.

```
                       ┌──────────────────────────────────────────┐
                       │              External Users               │
                       └────────────┬─────────────────────────────┘
                                    │ HTTPS
                                    ▼
                       ┌──────────────────────────────────────────┐
                       │   Route 53 (weighted 70:30)              │
                       │     ▼onprem 70%        ▼aws 30%          │
                       └──┬─────────────────────┬─────────────────┘
                          │                     │
                          ▼                     ▼
        ┌─────────────────────────────┐    ┌──────────────────────────┐
        │  온프레미스 (강의장)         │    │  AWS (ap-northeast-2)    │
        │  ────────────────────────   │    │  ────────────────────────│
        │  pfSense HA (DMZ/Internal)  │    │  CloudFront + WAF        │
        │     │                       │    │     │                    │
        │     ▼ Edge VIP 172.16.22.5  │    │     ▼                    │
        │  Edge HAProxy × 2           │    │  NLB                     │
        │     │ (TLS 종료)            │    │     │                    │
        │     ▼ K8s Ingress           │    │     ▼                    │
        │  HAProxy Ingress (172.16.23.50) │    │  EC2 HAProxy × 2     │
        │     │                       │    │     │                    │
        │     ▼                       │    │     ▼                    │
        │  Pods (kosa-tickets, ...)   │    │  EKS + Karpenter Spot    │
        │     │                       │    │  (평시 0, burst시 자동)  │
        │  ┌──┴──┐                    │    │                          │
        │  PXC   Redis  Ceph RBD/RGW  │    │  RDS MySQL (replica)     │
        │  ────────────────────────   │    │     ▲ binlog replication │
        │  3-replica, 10G fabric      │    │     │                    │
        └──┬──────────────────────────┘    └─────┼────────────────────┘
           │                                     │
           │           Site-to-Site VPN          │
           └───────────IPsec, ~6ms latency───────┘

  Burst Trigger:
   Prometheus → AlertManager → Lambda → R53 weight 변경 → 트래픽 AWS로
```

핵심은 양쪽 사이트가 모두 동작 가능하면서, **Route 53이 트래픽을 분배**한다는 점이다. 평시엔 온프레 70 / AWS 30 비율로 가지만, burst 시점에 AWS 비율을 100%로 끌어올린다.

---

## 👥 4명 팀원 분담 + 책임

학습 환경 4명 팀의 분담을 정리한다. 각자 deep-dive 영역이 있지만 cross-cutting 토픽은 모두 알아야 한다.

| 담당 | 파트 | 핵심 책임 | 폴더 |
|---|---|---|---|
| **A** | 🏛️ 아키텍처/설계 | 전체 구조, 네트워크, K8s, AWS 하이브리드, Burst | `architecture/` |
| **B** | 💾 데이터/스토리지 | Ceph (RBD/CephFS/RGW), PXC, Redis, RDS replication, 10G 네트워크 결정 | `data-storage/` |
| **C** | 🔧 CI/CD | Jenkins, Harbor, ArgoCD, 파이프라인 | `cicd/` |
| **D** | 🔒 보안 | pfSense, TLS, NetworkPolicy, WAF, 정책, 백업/DR | `security/` |

> 🔥 **각자 본인 파트 deep-dive + 다른 파트 README는 필독**. 면접/발표에서 cross-cutting 질문이 무조건 들어옵니다.

---

## 🌟 핵심 어필 포인트 5가지

발표/면접에서 강조할 5가지를 정리한다.

### 1. 진짜 동작하는 하이브리드 클라우드

VPN 위에 데이터 (PXC → RDS) + 워크로드 (Burst) 양방향 흐름이 동작한다. 단순히 "VPN으로 두 사이트 연결"하는 수준이 아니라 **자동화된 burst 트리거**가 동작한다.

### 2. 9-layer cascade 사고 분석 + 예방

2026-05-21 incident: cp1 etcd hiccup → 6분 timeout cascade. 5개 layer를 추적했고, fix 4개 (etcd auto-compact, HAProxy fall 5, GARP, ARP timeout)를 적용했다. **인프라를 깊이 있게 이해한 증거**다.

### 3. GitOps 완성 (App-of-Apps + 자동 sync)

root-app 1개로 모든 service가 부트스트랩된다. 모든 변경은 git commit → ArgoCD가 reconcile. selfHeal로 drift가 자동 회복된다.

### 4. 관측 3대 축 완성 (Metrics + Traces + Logs)

Prometheus + Tempo + Loki를 자체 호스팅했다. OpenTelemetry auto-instrumentation으로 **코드 0줄 변경**으로 trace 수집. AlertManager가 SMTP email + AWS Lambda webhook을 동시 라우팅.

### 5. 이중 TLS (Defense in Depth)

외부 (Edge HAProxy)와 내부 (HAProxy Ingress) 모두 TLS 종료. 자체 CA (10년) + cert-manager로 service별 cert 90일 자동 회전. **내부 트래픽도 wire에서 평문이 아니다**.

---

## 📅 프로젝트 단계 요약

각 Phase가 어떤 작업을 했는지 정리한다.

| 단계 | 작업 | 상태 |
|---|---|---|
| **Phase 0** | 물리 구축 (Proxmox 4 + Ceph 6 + 스위치 패브릭) | ✅ |
| **Phase 1** | pfSense HA + VLAN + K8s HA 구축 | ✅ |
| **Phase 2** | Harbor + Jenkins + ArgoCD + Prometheus | ✅ |
| **Phase 3** | AWS VPC + VPN + RDS Read Replica | ✅ |
| **Phase 4** | EKS + Karpenter Burst + Lambda trigger | ✅ |
| **Phase 5** | CloudFront + WAF + 관측성 3대축 (Tempo+Loki) + 이메일 알림 | ✅ |
| **Phase 6** | sys2 HA + Backup 자동화 + Sealed Secrets | ⏳ 계획 |

Phase 0~5가 완료된 상태고, Phase 6이 운영급 진입을 위한 다음 단계다.

---

## ⚖️ 트레이드오프 — 의식적으로 선택한 것들

우리가 일부러 포기한 것들을 정리하면 다음과 같다. 모두 학습/데모 우선순위와의 trade-off다.

| 선택 | 대안 | 우리가 고른 이유 | 잃은 것 |
|---|---|---|---|
| Proxmox + K8s | 베어메탈 K8s | VM 격리 + cloud-init + 학습 가치 | 가상화 오버헤드 |
| Ceph 별도 클러스터 | K8s 안에 Rook | 스토리지 장애 격리 + 독립 확장 | 노드 6대 추가 비용 |
| 자체 CA | Let's Encrypt | 내부 도메인(*.kosa.team2) LE 안 됨 | 외부 신뢰성 X |
| Jenkins Polling | GHA self-hosted runner | NAT 친화 + 즉시 동작 (ARC 함정 회피) | 1~2분 지연 |
| Ceph RGW (S3) | AWS S3 | 자체 호스팅 무료 + 데이터 주권 | RGW 단일 daemon SPoF |
| EKS Karpenter Spot | EC2 Auto Scaling Group | Spot 90% 비용 절감 | interruption 가능 |
| MetalLB L2 | BGP | 외부 BGP 라우터 없음 | 단일 노드 ARP 응답 |

---

## ⚠️ 솔직히 인정하는 약점 (발표 어필 포인트)

면접관/발표자가 가장 좋아하는 게 **자기 약점 인지 + 개선 계획**이다. 우리 약점 8개를 솔직히 정리한다.

| # | 약점 | 영향 | 개선 계획 |
|---|---|---|---|
| 1 | **모든 서비스 K8s에 (CI/CD 포함)** | K8s 죽으면 → K8s 살릴 도구도 죽음 (순환 의존) | Phase 6: Jenkins 별도 VM 분리 → `architecture/07-bootstrap-resilience.md` |
| 2 | **워커 자원 부족시 자동화 X** | AWS Karpenter는 있는데 온프레 수동 | Phase 7: Terraform + Ansible 자동 프로비저닝 → `architecture/08-onprem-autoscaling.md` |
| 3 | **sys1 단일 노드** | 모니터링/CI/CD 전부 down | Phase 6: sys2 추가 |
| 4 | **Ceph RGW 단일 daemon** | Harbor push/pull 실패 | Phase 6: RGW 2개 |
| 5 | **NetworkPolicy ticket-app만** | 다른 ns 무방비 | Phase 6: 모든 ns 확장 |
| 6 | **Secret 평문 base64** | Git commit 불가 | Phase 6: Sealed Secrets |
| 7 | **백업 자동화 없음** | DR 어려움 | Phase 6: etcd/PXC/Harbor backup CronJob |
| 8 | **webhook 무인증** | false burst trigger 위험 | Phase 6: API Key |

→ 8개 모두 문서화됐다 (각각 해당 파트 문서에 detail). **솔직히 + 개선 계획 = 면접 강점**이라는 패턴이 가장 중요하다.

---

## 🚨 알려진 SPoF + 위험 점수

운영 진입 전에 해소해야 할 SPoF를 위험도 순으로 정리한다.

| SPoF | 영향 | 위험 점수 | 해결 계획 |
|---|---|---|---|
| **sys1 단일 노드** | 모니터링/Harbor/Jenkins/ArgoCD 전부 down | ★★★★ | sys2 추가 (Phase 6) |
| **Ceph RGW 단일 daemon** | Harbor push/pull 불가 | ★★★ | RGW 2 이상 |
| **NAT Gateway AZ별 1개** | AZ 죽으면 outbound 끊김 | ★★ | 이미 2 AZ |
| **pfSense MASTER VM 호스트** | HA로 자동 failover (수초) | ★ | 정상 |
| **K8s API VIP** | Keepalived 자동 (수초) | ★ | 정상 |

→ 자세한 분석: `architecture/06-cost-spof-tradeoffs.md`

---

## 📚 다음 읽을 문서 (역할별)

각 담당이 우선 읽어야 할 문서를 정리한다.

### 아키텍처 담당 (A)
1. `architecture/README.md` → 학습 가이드
2. `architecture/01-physical-and-network.md` → 물리/네트워크 깊이
3. `architecture/02-kubernetes-design.md` → K8s 설계
4. `architecture/03-aws-hybrid.md` → AWS 통합
5. `architecture/04-burst-architecture.md` → Burst 전체 흐름
6. `architecture/05-observability-design.md` → 3대축 설계
7. `architecture/06-cost-spof-tradeoffs.md` → 종합 분석
8. ⭐ `architecture/07-bootstrap-resilience.md` → K8s 의존성 + CI/CD 분리
9. ⭐ `architecture/08-onprem-autoscaling.md` → 온프레 워커 자동 프로비저닝

### 데이터/스토리지 담당 (B)
`data-storage/README.md` + 01~06

### CI/CD 담당 (C)
`cicd/README.md` + 01~06

### 보안 담당 (D)
`security/README.md` + 01~08

### 모두 (cross-cutting)
`99-cross-cutting.md` — 파트 경계 토픽

---

## ❓ 자주 받는 전반적 질문

**Q. 왜 100% AWS 가지 않고 하이브리드인가요?**

A. 네 가지 이유입니다. **이미 보유한 온프레 자원 활용 (sunk cost)**, **클라우드 비용 절감** (평시 워크로드는 온프레, burst만 AWS), **데이터 주권** (PXC가 primary, RDS는 replica), **학습 가치** (양쪽 다 다룸). 100% AWS면 학습 가치 한 측면만 보는 셈입니다.

**Q. 비용은 얼마나 들어가나요?**

A. 온프레 (전기/감가) 약 ₩30만/월, AWS Phase 1-2 약 $130/월 (VPN+NAT+EC2+NLB). Phase 4 burst는 발생 시에만 추가 비용. 100% AWS 대비 약 60% 절감 추정입니다. 자세한 건 `architecture/06`.

**Q. 4명이 어떻게 분담했나요?**

A. 위의 4파트 분담 패턴입니다. 각자 자기 영역 deep-dive + 통합은 cross-cutting 문서로 공유. K8s 표준 분리 패턴 (App/Infra/Sec)을 따른 결과입니다.

**Q. 가장 어려웠던 부분이 뭐예요?**

A. 세 가지입니다. **9-layer cascade incident** (cp1 etcd hiccup → 6분 outage 추적), **ArgoCD/Operator reconcile 충돌** (helm values가 안 먹는 미묘한 문제), **OTel auto-instrumentation NetworkPolicy 함정** (egress 룰 빠뜨려서 trace 안 감). 모두 docs/onprem/incident-* 또는 CLAUDE.md에 문서화됐습니다.

---

## 🔗 외부 참고 문서

- `Session_Handoff.md` — 작업 history 큰 그림
- `docs/onprem/` — 운영 narrative + 트러블슈팅 chronicle
- `CLAUDE.md` — 운영 reference + AI 컨텍스트
