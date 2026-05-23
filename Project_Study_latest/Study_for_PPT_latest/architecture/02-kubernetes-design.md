# 02. Kubernetes 설계

> ⭐ **한 줄 요약**: **kubeadm 1.30 HA** (CP×3 stacked etcd + Worker×4)를 골랐다. **Calico IPIP** CNI로 NetworkPolicy 가능, **HAProxy Ingress + MetalLB L2**가 외부 노출 담당. 가장 중요한 결정은 **sys/prod 노드 분리**로, 시스템 워크로드가 비즈니스 트래픽 폭증의 영향을 안 받게 격리했다.

---

## 🎯 우리가 한 선택

K8s 클러스터의 구성은 다음과 같다. CP 3대로 etcd quorum을 만들고, Worker 4대 (production 3 + system 1)로 워크로드를 분산한다. 모든 노드가 kubeadm으로 설치된 표준 K8s 1.30이라 어떤 클러스터로든 이식이 가능하다.

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

### 노드 라벨 분리 — 우리 설계의 핵심

워커 노드는 라벨 `workload-type`으로 두 그룹으로 분리한다. 이게 우리 K8s 설계에서 가장 중요한 결정이다.

```yaml
# 시스템 워크로드용
k8s-sys1: workload-type=system

# 비즈니스 워크로드용
k8s-w1, w2, w3: workload-type=production
```

이렇게 분리하는 이유는 단순하지만 강력하다. **비즈니스 트래픽이 폭증해서 production 노드가 OOM이 나도, 모니터링/CI/CD 같은 system 워크로드는 sys1에서 멀쩡히 살아남는다.** 즉 사고 진단 도구가 사고와 함께 같이 죽지 않게 격리하는 거다.

### 전체 토폴로지

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

## 📍 Placement 정책 — 어떤 워크로드를 어디에, 왜?

다이어그램만 봐선 "w1 = ticket-app 전용, w2 = PXC 전용"으로 오해할 수 있는데, **실제로는 anti-affinity로 강제 분산된다**. 같은 워크로드의 여러 Pod이 같은 노드에 안 가게 막아서, 한 노드가 죽어도 quorum을 유지하는 패턴이다.

### 결정 매트릭스

| 워크로드 | nodeSelector | 분산 방식 | 왜 |
|---|---|---|---|
| **ticket-app** | production (w1~3) | replicas:2 + soft anti-affinity | stateless = 어디든 OK, HA 위해 권장 분산 |
| **PXC** | production (w1~3) | **podAntiAffinity REQUIRED** → 3 Pod이 w1/w2/w3 1개씩 강제 | Galera 쿼럼 = 노드 1대 죽어도 2/3 유지. 같은 노드면 의미 X |
| **PXC ProxySQL** | production | podAntiAffinity (soft) | 2 Pod 분산 권장 |
| **Redis Sentinel** | production | **podAntiAffinity REQUIRED** → 3 Pod 분산 강제 | Quorum 2/3, 노드 분산 필수 |
| **Prometheus** | **system (sys1)** | replica 1 (PVC RWO) | RWO 단일 인스턴스, system 격리 |
| **Grafana** | **system (sys1)** | replica 1 (PVC RWO) | 동일 |
| **AlertManager** | system (sys1) | replicas: 3 spec | sys2 추가 시 진짜 3-node cluster |
| **Harbor** (8 컴포넌트) | **system (sys1)** | core/registry stateless, DB/Redis는 PVC RWO | DB는 단일 노드 고정 |
| **Jenkins** | **system (sys1)** | controller 1개 (PVC RWO) | active-passive 패턴 |
| **ArgoCD** | **system (sys1)** | 4 Pod | replicas 가능하지만 sys1 1대 |
| **Tempo / Loki** | **system (sys1)** | replica 1 (RWO PVC) | S3 backend 전환 시 HA 가능 |
| **CoreDNS** | 모든 노드 (DaemonSet) | DaemonSet | 노드 로컬 DNS |
| **Calico CNI** | 모든 노드 (DaemonSet) | DaemonSet | 모든 노드 필요 |

### 세 가지 placement 메커니즘

#### 1. nodeSelector — 강제 배치

특정 노드 라벨이 있는 곳에만 schedule된다. system 워크로드 전체에 적용해서 sys1에 강제한다.

```yaml
spec:
  template:
    spec:
      nodeSelector:
        workload-type: system   # sys1에만 schedule
```

이게 적용된 워크로드들 (Prometheus/Grafana/Harbor/Jenkins/ArgoCD/Tempo/Loki)은 절대 production 워커에 안 뜬다. 비즈니스 트래픽이 production을 모두 잡아먹어도 영향 없이 살아남는다.

#### 2. podAntiAffinity REQUIRED — 같은 노드에 둘 X (강제)

같은 라벨의 Pod이 같은 노드에 동시에 있을 수 없게 막는다. PXC 3 Pod이 강제로 w1, w2, w3에 1개씩 분산된다.

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

**이게 PXC와 Redis Sentinel의 quorum 보장의 핵심**이다. 만약 같은 노드에 2개 Pod이 떠 있는데 그 노드가 죽으면, 갑자기 quorum 1/3이 돼서 write가 차단된다. REQUIRED 모드는 이걸 사전 방지한다.

#### 3. podAntiAffinity PREFERRED — 가능하면 분산 (권장)

ticket-app 같은 stateless 워크로드는 PREFERRED 모드를 쓴다. 가능하면 분산하지만, 어쩔 수 없으면 같은 노드에 둘 다 뜨는 것도 허용한다.

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

stateless라 어디 뜨든 동일하게 동작하니, 너무 strict하게 막으면 schedule 실패만 늘어난다. PREFERRED가 적절한 균형이다.

### 다이어그램 vs 실제

| 다이어그램 (단순화) | 실제 (anti-affinity 적용) |
|---|---|
| w1: ticket-app | w1: ticket-app-0, PXC-0, Redis-0 (한 Pod씩) |
| w2: PXC | w2: ticket-app-1, PXC-1, Redis-1 |
| w3: Redis | w3: PXC-2, Redis-2 |
| sys1: 모든 시스템 | sys1: 모든 시스템 (nodeSelector 강제) |

`kubectl get pods -A -o wide --sort-by=spec.nodeName` 로 실제 배치를 확인할 수 있다.

---

## 🔍 고려한 대안들

### Q1. kubeadm vs k3s vs RKE2 vs EKS

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **kubeadm (선택)** | 표준 K8s, 업그레이드 명시적, 학습 가치 ↑ | 설치 명령 많음 | ★★★★★ |
| **k3s** | 경량 (단일 바이너리), edge용 | 일부 컴포넌트 다름 (Traefik 기본) | ★★★ (학습엔 아쉬움) |
| **RKE2** | Rancher 표준, hardened | Rancher 종속 | ★★ |
| **EKS** | AWS 관리형 | 온프레 환경엔 부적합 | ★ |

kubeadm은 K8s 표준 부트스트랩 도구다. 모든 컴포넌트가 명시적이라 학습/디버깅에 좋다. k3s는 가볍지만 (단일 바이너리, 메모리 ~500MB) Traefik이 기본 ingress라 우리가 쓰는 HAProxy Ingress와 차이가 있다. 학습 환경엔 표준 패턴이 더 가치 있다.

### Q2. stacked etcd vs external etcd

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **stacked (선택)** | 노드 수 ↓ (CP가 etcd 같이), 단순 | CP 1대 죽으면 etcd도 1대 죽음 | ★★★★ |
| **external etcd** | 격리, etcd 노드 SSD 최적화 가능 | 노드 3대 추가, 운영 복잡 | ★★★ (규모 크면 ★★★★★) |

stacked etcd는 CP 노드와 etcd가 같은 머신에 공존하는 패턴이다. 노드 수가 적어서 단순하지만, CP 1대 죽으면 etcd 1대도 동시에 잃는다. 우리 3 CP면 etcd quorum 2/3이 유지되니 1대 사고는 견딘다. external etcd는 etcd 3~5대를 별도 노드에 두는 패턴이고, etcd 자체를 SSD로 최적화 가능하지만 노드 수가 늘어난다.

### Q3. Calico vs Cilium vs Flannel

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Calico (선택)** | 사실상 표준, NetworkPolicy 강력 | eBPF는 옵션 (기본 iptables) | ★★★★★ |
| **Cilium** | eBPF 기반 (성능 ↑), L7 정책 가능 | 학습 곡선 ↑ | ★★★★ |
| **Flannel** | 가장 단순 | NetworkPolicy 없음 (security 약함) | ★★ |
| **Weave** | 사용 줄어듦 | 2024년 commercial 종료 | ★ |

Calico는 K8s NetworkPolicy 표준 구현이라 zero-trust 정책에 필수다. Flannel은 단순하지만 NetworkPolicy를 지원 안 해서 security 측면에서 부족하다. Cilium은 eBPF 기반이라 더 빠르고 L7 정책 (HTTP method 단위)도 가능하지만 학습 곡선 ↑이고 우리 환경엔 아직 과한 수준이다.

### Q4. HAProxy Ingress vs Nginx vs Traefik

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **HAProxy Ingress (jcmoraisjr) 선택** | HAProxy 성능, TLS 종료 견고 | annotation 표준과 약간 다름 | ★★★★ |
| **Nginx Ingress** | 가장 보편적, 문서 풍부 | C 기반이라 rule 변경 시 reload | ★★★★ |
| **Traefik** | 자동 발견, 대시보드 좋음 | 설정 학습 곡선 | ★★★ |

우리 팀은 Edge HAProxy를 이미 운영하고 있어, K8s Ingress도 HAProxy 계열로 통일하는 게 **운영 일관성** 측면에서 유리했다. annotation이 `kubernetes.io/ingress.class`만 인식하는 등 다른 ingress와 약간 다른 점이 있는데, 한 번 익히면 별 문제 없다.

### Q5. MetalLB L2 vs BGP vs ExternalIP

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **L2 모드 (선택)** | 외부 라우터 무관, 설정 단순 | 단일 노드 ARP 응답 | ★★★★ |
| **BGP 모드** | 진짜 분산, ECMP | 외부 BGP 라우터 필요 (우리 환경에 없음) | ★ (불가) |
| **ExternalIP** | 가장 단순 | 노드 IP 고정, HA X | ★★ |

MetalLB L2 모드는 외부 라우터 없이도 LoadBalancer Service를 구현해준다. 단점은 단일 노드가 ARP 응답을 담당하니 그 노드 처리량이 한계다. BGP 모드가 진짜 분산이지만 외부 BGP 라우터가 필요한데 우리 환경엔 없다.

---

## 💡 왜 이걸 선택했나

다섯 가지 이유로 정리한다.

### 1. kubeadm = 표준 + 학습 가치

K8s 운영을 진짜 이해하려면 kubeadm으로 손수 설치해봐야 한다. 모든 컴포넌트가 `/etc/kubernetes/manifests/`에 명시적으로 드러나서, 트러블슈팅 시 어디를 봐야 할지 명확하다 (etcd, apiserver, kubelet 등). 업그레이드 절차도 명시적이라 1.30 → 1.31 같은 작업의 실제 운영 역량을 키울 수 있다.

### 2. stacked etcd = 비용/단순함 균형

학습 환경에서 etcd 3대를 따로 두는 건 노드 자원 낭비다. 3 CP에 etcd가 같이 떠 있으면 충분히 동작하고 (quorum 유지), 운영도 단순하다. 진짜 운영 진입 + 노드 50+ 규모면 external etcd로 분리하는 게 합리적이다.

### 3. Calico IPIP = 안전한 default + NetworkPolicy 강력

IPIP encapsulation은 외부 BGP 없이 동작하고 NAT 친화적이다 (우리 환경 적합). NetworkPolicy 표준 구현이라 zero-trust 정책이 가능하다. Pod-Pod 실측 5.34 Gbps로 우리 워크로드 규모에 충분하다.

### 4. sys/prod 노드 분리 = 운영 격리 (가장 중요)

> 🔥 **핵심**: 비즈니스 트래픽 폭증으로 production 노드가 OOM 나도 sys1의 모니터링은 살아남는다.

이게 단순한 라벨 한 줄 같지만, 실제로는 매우 강력한 격리다. system 워크로드 (Prometheus, Harbor, Jenkins, ArgoCD)는 sys1에 nodeSelector로 강제하고, production 워크로드 (ticket-app, PXC, Redis)는 w1~w3에 둔다. 비즈니스 폭증 사고가 발생해도 모니터링/CI/CD는 살아남아 진단 도구로 동작한다.

또 다른 효과는 **PVC RWO 충돌 회피**다. Prometheus, Grafana, Jenkins, Harbor 같은 stateful 워크로드는 PVC RWO 단일 노드 mount다. 다른 노드로 reschedule되면 Multi-Attach 에러가 발생한다. sys1에 강제 고정하면 reschedule 자체가 안 일어나니 이 문제가 해소된다.

### 5. HAProxy Ingress + MetalLB L2 = 우리 환경 최적

Edge HAProxy와 같은 도구라 운영 일관성이 좋다. MetalLB L2는 외부 BGP 라우터가 없는 우리 환경에서 유일한 선택지였다 (BGP 모드는 불가).

---

## 💰 비용 분석

### Worker 노드 자원 사용 (현재)

| 노드 | RAM 할당 | 실사용 | 여유 |
|---|---|---|---|
| sys1 (16GB) | 16GB | ~6GB (Prom/Graf/Harbor/Jenkins/Tempo/Loki) | 60% |
| w1 (6GB) | 6GB | ~2.4GB | 60% |
| w2 (6GB) | 6GB | ~2.9GB | 50% |
| w3 (6GB) | 6GB | ~2.2GB | 65% |

sys1은 시스템 워크로드 6GB 정도 쓰고 있어서 추가 여유가 ~60%다. Tempo + Loki를 추가하면서 약간 더 늘었지만 여전히 안정적이다.

### sys2 추가 시 비용

| 항목 | 비용 |
|---|---|
| Proxmox VM 1개 (16GB RAM, 4 vCPU) | 호스트 자원만 사용 |
| K8s 라이센스 | 무료 (kubeadm) |
| 운영 부담 | minimal (anti-affinity 설정만) |

sys2 추가는 비용 측면에서 거의 무료다. Proxmox 호스트의 RAM이 빡빡한 게 유일한 부담인데, kosa1 또는 kosa3에 추가하면 가능하다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 표준 K8s (이식성) | 설치 자동화 직접 구현 |
| 노드 분리 격리 | sys1 SPoF (sys2 추가 필요) |
| Calico NetworkPolicy 가능 | iptables 모드 (eBPF 안 씀) |
| HAProxy 일관성 | Annotation 표준과 약간 다름 |
| MetalLB L2 단순 | 단일 노드 ARP 응답 (cascade 가능) |

가장 큰 trade-off는 **sys1 SPoF**다. system 워크로드를 sys1에 집중시켰으니 sys1 죽으면 모니터링/CI/CD 전부 down된다. 이 약점을 해소하려고 sys2 추가가 Phase 6 우선 작업으로 계획돼 있다.

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **K8s API VIP (172.16.23.5)** | kubectl 멈춤, 5분 후 노드 eviction | Keepalived 자동 (수 초) |
| **CP 1대 죽음** | etcd quorum 유지, API VIP 자동 우회 | 자동 |
| **CP 2대 죽음** | etcd quorum loss → write 차단 | 긴급 — 죽은 CP 1대 살려야 |
| **sys1 다운** | 모니터링/CI/CD/Harbor 전부 down | sys2 필수 (Phase 6) |
| **MetalLB speaker 죽음** | LB IP ARP 응답 멈춤 | DaemonSet 재시작 |
| **calico-node 죽음** | 그 노드 Pod 네트워크 단절 | DaemonSet 자동 회복 |
| **CSI ceph-rbdplugin 죽음** | 그 노드 PVC mount 실패 | nodeplugin 재시작 |

K8s API VIP가 죽으면 kubectl이 멈추고 5분 후 노드들이 NotReady로 marked되어 Pod eviction이 시작된다. Keepalived가 보통 수 초 내 자동 failover하니 정상적으로는 영향 없다.

CP 1대 죽음은 etcd 2/3 quorum 유지로 영향이 적지만, CP 2대 죽으면 etcd quorum loss로 write가 차단된다. 이건 긴급 사고라 죽은 CP 1대라도 즉시 살려야 한다.

---

## 🚀 확장 가능성

### Option A: ⭐ sys2 추가 (sys1 SPoF 해소) — Phase 6 우선

sys1 SPoF가 우리 가장 큰 약점이라, Phase 6에서 sys2 추가가 최우선 작업이다. Proxmox VM 1개 (16GB RAM, 4 vCPU) 추가하고 K8s join해서 `workload-type=system` 라벨을 붙이면 된다. 그 다음 helm values를 업데이트해서 Prometheus replicas 2 + anti-affinity로 sys1/sys2 분산 배치를 적용한다.

작업은 4~6시간 정도. sys2 추가 후 HA가 가능한 워크로드들 (Prometheus, AlertManager, ArgoCD repo-server 등)은 replicas를 늘리고, Jenkins 같은 active-passive만 가능한 건 그대로 단일.

- 💰 **비용**: 0 (Proxmox 자원만)
- 🎯 **추천 시점**: 운영 진입 직전 + 데모 자주 + sys1 OOM 잦음

### Option B: external etcd 분리

노드 수 50+ 또는 etcd 메트릭이 병목으로 측정되면 etcd 3대를 별도 노드로 분리한다. etcd 노드는 SSD로 최적화하고 (fsync 빠름), CP는 컴퓨트만 담당한다. 운영 복잡도가 ↑이지만 진짜 large-scale 환경에선 필수다.

### Option C: Worker 노드 추가 (production)

비즈니스 워크로드가 늘어서 HPA가 자주 max replicas에 도달하면 Worker를 늘린다. Proxmox VM 1개당 0 비용이라 부담은 적다.

### Option D: Calico → Cilium 전환 (eBPF)

성능 병목이 측정되고 팀이 eBPF 학습 의지가 있으면 Cilium으로 전환한다. kube-proxy까지 대체할 수 있고 L7 NetworkPolicy도 가능하다. 마이그레이션 위험이 있어 신중해야 한다.

### Option E: HAProxy Ingress → Nginx 전환

Nginx가 더 보편적이라 새 팀원이 익숙할 수 있다. 마이그레이션 작업 + annotation 차이 정리가 필요한데, 학습 환경엔 우선순위 낮다.

### Option F: ServiceMesh 도입 (Istio/Linkerd)

마이크로서비스 10+로 성장하거나 mTLS 강제가 필요하면 Service Mesh를 도입한다. sidecar 패턴이 무겁고 학습 곡선이 크지만, mTLS 자동화 + traffic management + observability가 강력하다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| sys1 OOM 잦음 | A (sys2) ⭐ 즉시 |
| etcd metrics fsync 느림 | B (external etcd) |
| HPA max 도달 | C (worker 추가) |
| 네트워크 성능 병목 | D 검토 |

---

## 🔗 다른 파트와의 연결

이 K8s 설계는 다른 파트의 기반이다. 데이터 파트는 ceph-csi-rbd로 K8s와 Ceph를 연결하고 StorageClass를 정의한다 (`data-storage/03-storage-types.md`). CI/CD 파트는 Jenkins/Harbor/ArgoCD를 sys1에 배치하는 nodeSelector 패턴을 따른다. 보안 파트는 NetworkPolicy를 Calico 위에서 구현하고 cert-manager로 TLS를 자동화한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. CP 3대인데 1대 죽으면 어떻게 되나요?**

A. **etcd quorum 2/3 유지**해서 write 가능합니다. HAProxy 헬스체크가 죽은 CP를 자동 제외하니 kubectl도 정상 동작합니다. 5분 후 노드 자체가 NotReady marked되면서 자동 회복 절차에 들어갑니다. 자동 회복 또는 수동 reboot 후 정상으로 돌아옵니다.

**Q2. sys1 SPoF인 거 알면서 왜 sys2 안 만들었나요?**

A. 세 가지 이유입니다. **첫째, 학습 환경에서 4명이 운영 부담 ↑**하는 건 우선순위가 낮았고, **둘째, Proxmox 자원이 빡빡** (총 RAM 128GB 중 75% 사용 중)했고, **셋째, 데모/포트폴리오 목적엔 sys1만으로 충분**했습니다. 약점을 인지하고 Phase 6 우선 작업으로 명시했습니다. 발표 문서에선 sys1+sys2 가정으로 HA 설계를 보여줍니다.

**Q3. PVC RWO인데 Pod이 다른 노드로 reschedule되면?**

A. **Multi-Attach 에러로 Pending 상태**가 됩니다. 회복하려면 stale VolumeAttachment를 강제 삭제해야 하는데, 운영 시 골칫거리입니다. **그래서 sys1 고정 (nodeSelector)이 이 문제를 회피**합니다. stateful 워크로드는 단일 노드에 묶어두면 reschedule 자체가 안 일어나니까요.

**Q4. Calico를 IPIP로 설정한 이유? VXLAN 안 한 이유?**

A. **IPIP는 헤더가 더 가볍고 NAT 친화적**입니다. VXLAN은 multi-tenant 환경에서 강점이지만 우리는 단일 클러스터 단일 tenant라 그 장점이 의미 없습니다. 외부 BGP 라우터가 없어서 BGP 모드도 불가능합니다. IPIP가 우리 환경에 최적입니다.

**Q5. kube-proxy iptables vs IPVS는 어떻게 골랐나요?**

A. **기본 iptables 그대로**입니다. 서비스 수 1000+ 되면 IPVS가 유리 (lookup O(1) vs O(N))하지만 우리 규모엔 차이가 없습니다. 단순함 + 호환성 우선이라 기본 모드 유지입니다.

**Q6. cert-manager가 자체 CA로 발급한 cert 90일 회전이 안전한가요?**

A. 회전이 **자동**입니다 (cert-manager가 만료 30일 전 자동 갱신). 진짜 위험은 **자체 CA 자체가 만료 (10년)**되는 시점인데, 그때는 모든 cert 재발급 + 모든 노드 trust store 교체가 필요합니다. 9년 catalog를 미리 잡아두는 게 운영 정석입니다.
