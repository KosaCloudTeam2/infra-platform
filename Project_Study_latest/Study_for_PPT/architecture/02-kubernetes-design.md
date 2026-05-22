# 02. Kubernetes 설계

> ⭐ **한 줄 요약**: **kubeadm 1.30 HA** (CP×3 stacked etcd + Worker×4), **Calico IPIP** CNI, **HAProxy Ingress + MetalLB L2**, sys/prod 노드 분리. **sys1+sys2 HA로 확장 가정**.

---

## 🎯 우리가 한 선택

### 클러스터 구성
| 컴포넌트 | 선택 | 버전/설정 |
|---|---|---|
| K8s 배포 도구 | **kubeadm** | v1.30.14 |
| etcd 토폴로지 | **stacked** (CP 노드와 같이) | 3-node quorum |
| CP 노드 | **3개** (k8s-cp1/2/3) | 2vCPU/4GB |
| Worker 노드 | **4개** (w1/w2/w3 + sys1) | 2vCPU/6GB (sys1은 16GB) |
| **CNI** | **Calico** + IPIP encapsulation | v3.x |
| **CSI** | **ceph-csi-rbd** (외부 Ceph) | StorageClass: team2-rbd-block |
| **Ingress** | **HAProxy Ingress Controller** (jcmoraisjr) | v0.16.1 |
| **LoadBalancer** | **MetalLB L2 mode** | IP: 172.16.23.50 |
| K8s API HA | **HAProxy + Keepalived** (lb-1/lb-2) | VIP 172.16.23.5:6443 |
| 인증서 자동화 | **cert-manager** + 자체 CA ClusterIssuer | v1.x |

### 노드 라벨 분리
```yaml
# 시스템 워크로드용
k8s-sys1: workload-type=system

# 비즈니스 워크로드용
k8s-w1, w2, w3: workload-type=production
```

---

## 📍 Placement 정책 — 어떤 워크로드를 어디에, 왜?

### 결정 매트릭스

| 워크로드 | 어디에 (nodeSelector) | 분산 방식 | 왜 |
|---|---|---|---|
| **ticket-app** | production (w1~3) | replicas:2 + soft anti-affinity (가능하면 다른 노드) | stateless = 어디든 OK, HA 위해 분산 |
| **PXC (pii-protected)** | production (w1~3) | **podAntiAffinity REQUIRED** (같은 노드 X) → 3 Pod이 w1/w2/w3 1개씩 강제 | Galera 쿼럼 = 노드 1대 죽어도 2/3 유지. 같은 노드면 의미 X |
| **PXC ProxySQL** | production | podAntiAffinity (soft) | 2 Pod 분산 권장 |
| **Redis Sentinel** | production | **podAntiAffinity REQUIRED** → 3 Pod이 w1/w2/w3에 강제 | Quorum 2/3, 노드 분산 필수 |
| **Prometheus** | **system (sys1)** | replica 1 (PVC RWO) | 1 인스턴스만 가능 (RWO), system 격리 |
| **Grafana** | **system (sys1)** | replica 1 (PVC RWO) | 동일 |
| **AlertManager** | system (sys1) | replicas: 3 spec (sys1 1대라 1만 active) | sys2 추가 시 진짜 3-node cluster |
| **Harbor** (8 컴포넌트) | **system (sys1)** | core/registry는 stateless multi, DB/Redis는 PVC RWO | 메타데이터 DB는 단일 노드 고정 필요 |
| **Jenkins** | **system (sys1)** | controller 1개 (PVC RWO) | active-passive 패턴 |
| **ArgoCD** | **system (sys1)** | 4 Pod (controller/server/repo/redis) | replicas 가능하지만 sys1 1대라 의미 X |
| **Tempo / Loki** | **system (sys1)** | replica 1 (RWO PVC) | S3 backend 전환 시 HA 가능 |
| **cert-manager** | system 또는 production (default) | replicas 1 | leader election |
| **CoreDNS** | 모든 노드 (DaemonSet) | DaemonSet | 노드 로컬 DNS |
| **Calico CNI** | 모든 노드 (DaemonSet) | DaemonSet | 모든 노드에 필요 |

### 3가지 placement 메커니즘

#### 1️⃣ `nodeSelector` (강제 — 특정 노드 라벨만)
```yaml
spec:
  template:
    spec:
      nodeSelector:
        workload-type: system   # sys1에만 schedule
```
→ Prometheus/Grafana/Harbor/Jenkins/ArgoCD/Tempo/Loki **모두 적용**.

#### 2️⃣ `podAntiAffinity` REQUIRED (강제 — 같은 노드에 둘 X)
```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: pxc
            topologyKey: kubernetes.io/hostname
```
→ PXC 3 Pod이 강제로 w1, w2, w3에 1개씩 (Galera Operator 자동 설정).
→ Redis Sentinel 동일.
→ **노드 1대 죽어도 quorum 유지** 보장.

#### 3️⃣ `podAntiAffinity` PREFERRED (권장 — 가능하면 분산)
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: ticket-app
        topologyKey: kubernetes.io/hostname
```
→ ticket-app replicas 2가 가능하면 다른 워커에 (스케줄러가 결정).

### 다이어그램 vs 실제

| 다이어그램 (단순화) | 실제 (anti-affinity 적용) |
|---|---|
| w1: ticket-app | w1: ticket-app-0, PXC-0, Redis-0 (한 Pod씩) |
| w2: PXC | w2: ticket-app-1, PXC-1, Redis-1 |
| w3: Redis | w3: PXC-2, Redis-2 |
| sys1: 모든 시스템 | sys1: 모든 시스템 (nodeSelector 강제) |

→ "1 워커 = 1 워크로드" **아님**. 각 워커가 여러 워크로드의 1개 Pod씩 받음.

### 실제 확인 명령
```bash
# 어느 노드에 어떤 Pod이 떴는지 확인
kubectl get pods -A -o wide --sort-by=spec.nodeName

# 출력 예 (실제):
# k8s-w1   ticket-app-...-aaa     1/1   Running
# k8s-w1   kosa-pxc-pxc-0         1/1   Running    ← PXC-0
# k8s-w1   kosa-redis-node-0      3/3   Running    ← Redis-0
# k8s-w2   ticket-app-...-bbb     1/1   Running
# k8s-w2   kosa-pxc-pxc-1         1/1   Running
# k8s-w2   kosa-redis-node-1      3/3   Running
# k8s-w3   kosa-pxc-pxc-2         1/1   Running
# k8s-w3   kosa-redis-node-2      3/3   Running
# k8s-sys1 alertmanager-...       2/2   Running
# k8s-sys1 kube-prom-grafana-...  3/3   Running
# k8s-sys1 harbor-core-...        1/1   Running
# ... (모든 시스템 sys1)
```

### 왜 이렇게 설계했나 — 핵심 원칙

| 원칙 | 적용 |
|---|---|
| **HA 워크로드는 강제 분산** (podAntiAffinity REQUIRED) | PXC 3, Redis 3 → quorum 보장 |
| **단일 인스턴스 stateful은 nodeSelector** | Prometheus/Grafana/Jenkins 등 sys1 고정 (PVC RWO + 운영 격리) |
| **stateless는 soft 분산** | ticket-app 같은 replicas는 권장만 (강제 X — 한 노드 죽어도 다른 노드에 다 떠도 OK) |
| **DaemonSet은 모든 노드** | CNI/CoreDNS/Promtail 등 노드 로컬 필요 |
| **system vs production 강제 격리** | 비즈니스 폭증이 모니터링 죽이지 못함 |

---

### 다이어그램
```
                            [bastion 172.16.24.10 — kubectl]
                                    │
                                    ▼
                            K8s API VIP 172.16.23.5:6443
                                    │ (HAProxy + Keepalived)
                          ┌─────────┼─────────┐
                          ▼         ▼         ▼
                    [cp1:6443] [cp2:6443] [cp3:6443]
                       (etcd)   (etcd)    (etcd)  ← stacked
                                    │
                          ┌─────────┼─────────┬───────────┐
                          ▼         ▼         ▼           ▼
                    [w1] prod  [w2] prod  [w3] prod  [sys1] system
                       │         │         │           │
                       │         │         │           ├─ Prometheus  ┐
                    ticket-app  PXC-0     PXC-1        ├─ Grafana     │ 모두
                    (replicas:2 PXC-2     Redis-0      ├─ Harbor       sys1에
                     scheduler  Redis-1   Redis-2      ├─ Jenkins      강제
                     자유 배치)                         ├─ ArgoCD      │ (nodeSelector)
                                                       └─ Tempo/Loki  ┘
                          ↑
                    [MetalLB 172.16.23.50]
                          ↑
                   [HAProxy Ingress]
```

> ⚠️ **주의**: 위 다이어그램은 단순화된 표현. 실제 Pod 배치는 K8s 스케줄러 + anti-affinity가 결정 (아래 "Placement 정책" 섹션 참고).

---

## 🔍 고려한 대안들

### Q1. kubeadm vs k3s vs RKE2 vs EKS

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **kubeadm (선택)** | 표준 K8s, 업그레이드 명시적, 학습 가치 ↑ | 설치 명령 많음, 자동화 필요 | ★★★★★ |
| **k3s** | 경량 (단일 바이너리), edge용 | 일부 컴포넌트 다름 (Traefik 기본 등), production K8s와 약간 다름 | ★★★ (학습엔 아쉬움) |
| **RKE2** | Rancher 표준, hardened | Rancher 종속, k8s 표준 우회 | ★★ |
| **EKS** | AWS 관리형, 운영 부담 ↓ | 비용 ↑ (vCPU 시간당), 온프레 환경엔 부적합 | ★ (온프레엔 X) |

### Q2. stacked etcd vs external etcd

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **stacked (선택)** | 노드 수 ↓ (CP가 etcd 같이), 단순 | CP 1대 죽으면 etcd도 1대 죽음, IO 부하 같이 받음 | ★★★★ |
| **external etcd** | 격리, etcd 노드 SSD 최적화 가능, etcd 5대 클러스터 가능 | 노드 추가 (etcd 3대 별도), 운영 복잡 | ★★★ (규모 크면 ★★★★★) |

### Q3. Calico vs Cilium vs Flannel

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Calico (선택)** | 검증된 사실상 표준, NetworkPolicy 강력, IPIP/VXLAN/BGP 선택 가능 | eBPF는 옵션 (기본은 iptables) | ★★★★★ |
| **Cilium** | eBPF 기반 (성능 ↑), L7 정책 가능 | 학습 곡선 ↑, 일부 운영 함정 | ★★★★ |
| **Flannel** | 가장 단순 | NetworkPolicy 없음 (security 약함) | ★★ |
| **Weave** | 사용 줄어듦, 2024년 commercial 종료 | 미래 불투명 | ★ |

### Q4. HAProxy Ingress vs Nginx vs Traefik vs Istio Gateway

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **HAProxy Ingress (jcmoraisjr) 선택** | HAProxy 성능, TLS 종료 견고, 우리 팀이 HAProxy 익숙 | annotation이 기존 표준과 약간 다름 (`kubernetes.io/ingress.class`만 인식) | ★★★★ |
| **Nginx Ingress** | 가장 보편적, 문서 풍부 | C 기반 ngx로 ingress rule 변경 시 reload | ★★★★ |
| **Traefik** | 자동 발견, 대시보드 좋음 | 설정 학습 곡선 | ★★★ |
| **Istio Gateway** | Service Mesh 일부, mTLS | 무거움, mesh 안 쓸 거면 과함 | ★★ |

### Q5. MetalLB L2 vs BGP vs ExternalIP

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **L2 모드 (선택)** | 외부 라우터 무관, 설정 단순 | 단일 노드가 ARP 응답 → 그 노드 처리량 한계, failover ARP refresh 필요 | ★★★★ |
| **BGP 모드** | 진짜 분산 (모든 노드가 응답), ECMP | 외부 BGP 라우터 필요 (우리 환경엔 없음) | ★ (불가) |
| **ExternalIP (Service spec)** | 가장 단순 | 노드 IP 고정, HA X | ★★ |

---

## 💡 왜 이걸 선택했나 (5가지)

### 1. 🔧 **kubeadm = 표준 + 학습 가치**
> 🔥 **핵심**: K8s 운영을 진짜 이해하려면 kubeadm으로 손수 깔아봐야.

- 모든 클러스터의 동작 원리 노출 (`/etc/kubernetes/manifests/`)
- 트러블슈팅 시 어디 봐야 할지 명확 (etcd, apiserver, kubelet)
- 업그레이드 절차 명시 → 실제 운영 역량

### 2. 💰 **stacked etcd = 비용/단순함 균형**
- 노드 4대 절약 (external etcd 3 + 별도)
- 학습 환경엔 충분 (3 노드 quorum)
- IO 부담은 우리 워크로드 규모엔 무시 가능 (2026-05-21 cascade는 별도 원인)

### 3. 🌐 **Calico IPIP = 안전한 default + NetworkPolicy 강력**
- IPIP encapsulation = 외부 BGP 없이도 동작 (우리 환경 적합)
- NetworkPolicy 표준 구현 (zero-trust 가능)
- 실측 5.34 Gbps Pod-Pod (충분)

### 4. 📊 **sys/prod 노드 분리 = 운영 격리**
> 🔥 **핵심**: 비즈니스 트래픽 폭증으로 운영 노드 OOM 나도 모니터링/CI/CD는 살아남는다.

- system 워크로드 (Prometheus/Grafana/Harbor/Jenkins/ArgoCD)는 sys1
- production 워크로드 (ticket-app/PXC/Redis)는 w1~w3
- nodeSelector `workload-type` 라벨로 강제
- **PVC RWO 충돌 회피**: stateful (Prometheus, Jenkins) 단일 노드 고정 → Multi-Attach 에러 회피

### 5. ⚡ **HAProxy Ingress + MetalLB L2 = 우리 환경 최적**
- HAProxy = 외부 Edge HAProxy와 동일 도구 → 일관성
- MetalLB L2 = 외부 BGP 라우터 없으니 유일한 선택지

---

## 💰 비용 분석

### Worker 노드 자원 사용 (현재)
| 노드 | RAM 할당 | 실사용 | 여유 |
|---|---|---|---|
| sys1 (16GB) | 16GB | ~6GB (Prom/Graf/Harbor/Jenkins/Tempo/Loki) | 60% |
| w1 (6GB) | 6GB | ~2.4GB | 60% |
| w2 (6GB) | 6GB | ~2.9GB | 50% |
| w3 (6GB) | 6GB | ~2.2GB | 65% |

### sys2 추가 시 비용 (Phase 6)
- Proxmox VM 1개 추가: 16GB RAM, 4 vCPU, 50GB disk
- 호스트 자원 차감 (kosa1 또는 kosa3에 추가)
- 추가 라이선스 비용: ₩0 (kubeadm 무료)
- 운영 부담: minimal (anti-affinity 설정만)

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 표준 K8s (이식성) | 설치 자동화 직접 구현 (Ansible 35-*.yml) |
| 노드 분리 격리 | sys1 SPoF (sys2 추가 필요) |
| Calico NetworkPolicy 가능 | iptables 모드 (eBPF 안 씀) |
| HAProxy 일관성 | Annotation 표준과 약간 다름 |
| MetalLB L2 단순 | 단일 노드 ARP 응답 (cascade 가능) |

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **K8s API VIP (172.16.23.5)** | kubectl 멈춤, kubelet → API timeout, eviction 시작 (5분 후) | Keepalived가 자동 (수 초), 안 되면 lb-1/lb-2 keepalived 수동 restart |
| **CP 1대 죽음** | etcd 2/3 quorum 유지, API VIP가 그 CP 빼고 routing | 자동 (HAProxy backend check) |
| **CP 2대 죽음** | etcd quorum loss → write 차단 (read만) | 긴급 — 죽은 CP 1대 살려야 |
| **sys1 다운** | 모니터링/CI/CD/Harbor 전부 down | 진짜 운영엔 sys2 추가 필수. 회복: VM 재시작 or migration |
| **MetalLB speaker 죽음** | LB IP ARP 응답 멈춤 | `kubectl rollout restart ds metallb-speaker` |
| **calico-node 죽음** | 그 노드의 Pod 네트워크 단절 | DaemonSet 자동 회복 |
| **CSI ceph-rbdplugin 죽음** | 그 노드의 PVC mount 실패 | nodeplugin DaemonSet 재시작 |

---

## 🚀 확장 가능성

### Option A: ⭐ sys2 추가 (sys1 SPoF 해소) — **Phase 6 우선순위**
- ✅ **장점**: HA 보장, rolling 점검 가능, 메모리 풀 32GB
- ❌ **단점**: 일부 워크로드는 anti-affinity로 분산 가능, 일부 (Jenkins)는 active-passive
- 💰 **비용**: Proxmox VM 1개 (호스트 자원만, 라이선스 ₩0)
- ⏱️ **작업**: 4~6시간 (VM 생성 + K8s join + 라벨 + helm values 업데이트 + anti-affinity)
- 🎯 **추천 시점**: 운영 진입 직전 / 데모 자주 / sys1 OOM 잦음

**sys2 추가 후 HA 매핑 (가정)**:
| 워크로드 | sys1 | sys2 |
|---|---|---|
| Prometheus | replica-0 | replica-1 (Thanos sidecar dedup) |
| AlertManager | -0 | -1, -2 |
| Grafana | replica-1 | replica-2 |
| Harbor core/db/registry | active | replica |
| Harbor jobservice/trivy | active | replica |
| Jenkins | active | (active-passive only) |
| ArgoCD application-controller | leader | follower |
| ArgoCD repo-server/server | replica | replica |
| Loki | read+write+backend 분리 | 분리 |
| Tempo | active | (RWO PVC 한계, S3 백엔드 권장) |

### Option B: external etcd 분리
- ✅ **장점**: etcd IO 격리, etcd 노드 SSD 최적화
- ❌ **단점**: 노드 3대 추가, 운영 복잡
- 💰 **비용**: VM 3대 + 운영 부담
- 🎯 **추천 시점**: 노드 수 50+ 또는 etcd 메트릭이 병목

### Option C: Worker 노드 추가 (production)
- ✅ **장점**: 더 많은 비즈니스 워크로드, HPA 효율 ↑
- 💰 **비용**: Proxmox VM 1개당 0
- 🎯 **추천 시점**: production HPA가 자주 max replicas 도달

### Option D: Calico → Cilium 전환 (eBPF)
- ✅ **장점**: 더 빠름 (kube-proxy 대체), L7 NetworkPolicy
- ❌ **단점**: 마이그레이션 위험, 학습 곡선
- 🎯 **추천 시점**: 성능 병목 측정 + 팀 학습 의지

### Option E: HAProxy Ingress → Nginx 전환
- ✅ **장점**: 더 보편적 (인터넷 자료 ↑)
- ❌ **단점**: 마이그레이션 작업 + annotation 차이
- 🎯 **추천 시점**: 새 팀원이 Nginx만 알 때 (낮은 우선순위)

### Option F: ServiceMesh 도입 (Istio/Linkerd)
- ✅ **장점**: mTLS 자동, traffic management, observability
- ❌ **단점**: 무거움 (sidecar per Pod), 학습 곡선 ★★★★★
- 🎯 **추천 시점**: 마이크로서비스 10+ 또는 mTLS 강제 필요

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| sys1 OOM 잦음 | A (sys2) |
| etcd metrics fsync 느림 | B (external etcd) |
| HPA max 도달 | C (worker 추가) |
| network 성능 측정 | D 검토 |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 데이터 | ceph-csi-rbd가 K8s ↔ Ceph 다리. StorageClass 정의. |
| 🔧 CI/CD | Jenkins/Harbor/ArgoCD를 sys1에 배치. nodeSelector 강제. |
| 🔒 보안 | NetworkPolicy 사용은 Calico 의존. RBAC + cert-manager. |
| 🏛️ 자기 자신 (아키텍처) | `01-physical` (네트워크 위에 K8s 동작) + `03-aws-hybrid` (EKS와 다른 점) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. CP 3대인데 1대 죽으면 어떻게 되나?**
A. etcd quorum 2/3 유지 → write 가능. HAProxy 헬스체크가 죽은 CP를 자동 제외 → kubectl 정상. 5분 후 노드 NotReady → 자동 회복 또는 수동.

**Q2. sys1 SPoF인 거 알면서 왜 sys2 안 만들었나?**
A. (1) 학습 환경에서 4명이 운영 부담 ↑, (2) Proxmox 자원 빡빡 (총 RAM 128GB 중 75% 사용 중), (3) **데모/포트폴리오 목적엔 sys1만으로 충분**. 진짜 운영 단계 진입 시 Phase 6 우선순위. 발표 문서에선 sys1+sys2 가정으로 HA 설계 보여줌.

**Q3. PVC RWO인데 Pod이 다른 노드로 reschedule되면?**
A. Multi-Attach 에러로 Pending → 운영 노트북 알람. 회복 방법은 stale VolumeAttachment 강제 삭제. **그래서 sys1 고정 (nodeSelector)** = 이 문제 회피.

**Q4. Calico를 IPIP로 설정한 이유? VXLAN 안 한 이유?**
A. IPIP는 더 가볍고 (헤더 작음) NAT 친화. VXLAN은 multi-tenant 환경에서 강점이지만 우리는 단일 클러스터 단일 tenant. 외부 BGP 없으니 BGP 모드도 불가.

**Q5. kube-proxy iptables vs IPVS 골랐을 거 같은데?**
A. 기본 iptables 그대로. 서비스 수 1000+ 되면 IPVS가 유리 (lookup O(1) vs O(N))인데 우리 규모엔 차이 없음.

**Q6. cert-manager가 자체 CA로 발급한 cert 90일 회전 안전한가?**
A. 회전 자동 (cert-manager가 만료 30일 전 자동 갱신). 진짜 위험은 자체 CA 만료 (10년) — 그땐 모든 cert 재발급 + 노드 trust store 교체 필요. 9년 뒤 일정 catalog.
