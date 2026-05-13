# 챕터 05 — Calico CNI

> KOSA 인프라 프로젝트 학습 시리즈
> 분량: 8~10 페이지
> 선수 챕터: 04 Kubernetes 핵심

---

## 학습 후 알 수 있는 것

- **CNI(Container Network Interface)** 가 K8s에서 어떤 자리에 위치하는지, 왜 K8s 본체가 네트워크를 직접 안 만드는지 설명할 수 있어요.
- Pod이 다른 노드의 Pod과 어떻게 통신하는지, **오버레이(VXLAN/IPIP) vs 라우팅(BGP)** 차이를 그릴 수 있어요.
- Calico / Flannel / Cilium의 차이와, 우리가 왜 **Calico VXLAN 모드**를 택했는지 트레이드오프를 댈 수 있어요.
- **NetworkPolicy**로 namespace 간 트래픽을 차단하는 방법을 코드로 작성할 수 있어요.
- Tigera Operator로 Calico를 설치할 때 etcd leader change 때문에 자주 실패하는 이유와, retry 로직이 왜 필요한지 메커니즘 수준에서 이해해요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Calico는 K8s의 CNI 플러그인 중 하나로, Pod 네트워크 IP 할당·노드 간 패킷 라우팅·NetworkPolicy 기반 마이크로세그멘테이션을 동시에 제공하는 오픈소스 네트워크 솔루션입니다.**

### 1.2 등장 배경

K8s는 일부러 네트워크 구현을 외부 플러그인에 맡겼어요. 이유는 단순해요. **회사마다 네트워크 환경이 너무 달라서**. 클라우드(AWS VPC), 베어메탈(BGP/스위치), 가상화(VLAN/오버레이) 각각의 환경에서 최적 구성이 다르거든요. 그래서 K8s는 다음 세 가지 책임을 외부에 위임합니다.

1. **Pod에 IP 부여** — 어느 대역에서 어떻게 줄지
2. **노드 간 Pod 통신** — 다른 Worker의 Pod에게 패킷 전달
3. **트래픽 통제** — 누가 누구와 통신 가능한지 (NetworkPolicy)

이 "위임 규격"이 **CNI(Container Network Interface)** 이고, CNI를 구현한 플러그인 중 가장 널리 쓰이는 게 **Calico, Cilium, Flannel** 등입니다.

### 1.3 핵심 개념 + 용어 풀이

| 용어 | 한 줄 풀이 |
|---|---|
| **CNI** | K8s ↔ 네트워크 플러그인 사이의 표준 인터페이스. JSON 설정 + 바이너리 실행 규격. |
| **Pod CIDR** | Pod에게 줄 IP 대역. 우리는 `10.244.0.0/16`. |
| **Pod IP** | 각 Pod에 부여되는 클러스터 내부 고유 IP. |
| **오버레이 네트워크** | 물리 네트워크 위에 가상의 터널을 깔아 다른 노드의 Pod에 도달. VXLAN/IPIP가 대표적. |
| **VXLAN** | UDP 4789 위에 L2 프레임을 캡슐화. 오버레이 표준. |
| **IPIP** | IP 패킷을 IP로 감쌈. 가볍지만 클라우드와 충돌 잦음. |
| **BGP** | 라우터끼리 경로를 광고하는 프로토콜. Calico의 "오버레이 없는" 모드. |
| **NetworkPolicy** | "Pod A는 Pod B에게만 트래픽 허용" 같은 룰. 방화벽처럼 동작. |
| **Tigera Operator** | Calico를 K8s 위에서 선언적으로 관리해주는 컨트롤러. |
| **felix** | 각 노드에 떠있는 Calico 에이전트(DaemonSet). 정책을 iptables로 변환. |

### 1.4 동작 원리 (내부 메커니즘)

Pod A(노드1) → Pod B(노드2) 통신을 따라가 봅시다. **VXLAN 모드 기준**.

```
[노드1: k8s-w1 (172.16.23.20)]
  Pod A (10.244.10.5) → 패킷 출발 (목적지 10.244.20.7)
       │
       ▼
  Pod A의 veth pair (가상 이더넷 케이블)
       │
       ▼
  노드1의 kernel routing table
  "10.244.20.0/24는 노드2(172.16.23.21)로 가는 길"
       │
       ▼
  VXLAN 캡슐화 (UDP 4789 dst=172.16.23.21)
  [원본 패킷]
   │
   ▼
  노드1의 물리 NIC → 물리망 → 노드2의 물리 NIC
       │
       ▼
[노드2: k8s-w2 (172.16.23.21)]
  VXLAN 디캡슐화
       │
       ▼
  10.244.20.7 IP의 veth로 전달
       │
       ▼
  Pod B 수신
```

핵심은 **노드의 커널 라우팅 테이블**에 "어느 노드가 어느 Pod CIDR을 가지고 있다"가 적혀 있다는 거예요. 누가 적어줄까요? 각 노드의 Calico **felix 에이전트**가 클러스터에서 정보를 받아와 자동으로 적어줘요.

NetworkPolicy도 같은 felix가 처리해요. 정책이 만들어지면 felix가 그 노드의 **iptables** (또는 eBPF)에 룰을 박아 넣어요. "10.244.10.5 → 10.244.20.7만 허용, 나머지 거부" 같은 식으로.

### 1.5 주요 기능

| 기능 | 설명 |
|---|---|
| **IPAM** (IP Address Management) | Pod에 IP 자동 할당, 노드별 블록 단위 |
| **노드 간 라우팅** | VXLAN / IPIP / BGP / VPP 4가지 모드 |
| **NetworkPolicy** | K8s 표준 NetworkPolicy + Calico 확장(GlobalNetworkPolicy) |
| **eBPF 데이터플레인** | iptables 대신 eBPF로 처리 (성능↑, 옵션) |
| **Observability** | Flow log, DNS log (Calico Enterprise는 추가) |
| **WireGuard 암호화** | 노드 간 트래픽 자동 암호화 (옵션) |

### 1.6 다른 도구와 비교

| 항목 | **Calico** (우리) | Flannel | Cilium | AWS VPC CNI |
|---|---|---|---|---|
| 모드 | VXLAN / IPIP / BGP | VXLAN | eBPF (혁신) | VPC native (AWS만) |
| NetworkPolicy | ✅ 풍부 | ❌ 없음 | ✅ 매우 풍부 + L7 | 제한적 |
| 성능 | 중상 | 중 | 상 (eBPF) | 상 (native) |
| 학습 곡선 | 중 | 낮음 | 높음 | 낮음 (AWS만) |
| 엔터프라이즈 점유율 | **압도적** | 학습용 | 빠르게 추격 | AWS 전용 |
| 운영 부담 | 중 | 낮음 | 중상 | 낮음 |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **베어메탈 / 온프레미스 K8s**: 클라우드 CNI(VPC CNI 등)를 못 씀 → Calico/Cilium 거의 양자택일
- **NetworkPolicy 필수 환경**: 금융/의료/공공처럼 namespace 간 격리가 컴플라이언스 요구
- **다중 클러스터/멀티 클라우드**: 표준 NetworkPolicy로 통일된 보안 모델
- **마이크로서비스 100+개**: 서비스 간 통신 정책을 코드로 관리

우리는 위 4가지 중 **베어메탈 + NetworkPolicy(PII 분리 정책)** 두 가지가 강했어요.

### 2.2 업계 표준 구성, 대표 사용 기업/사례

- **국내 빅테크**: 카카오, 네이버, 쿠팡 모두 자체 K8s에서 Calico를 본 적 있는 표준 옵션으로 보고 있어요. 최근엔 Cilium으로 이전한 사례도 늘고 있어요.
- **글로벌**: GitHub, Adobe, Discovery, Bloomberg 등이 Calico 운영 사례 공개.
- **클라우드 매니지드**:
  - **EKS**: 기본은 VPC CNI지만, NetworkPolicy 풍부함을 위해 **Calico**를 add-on으로 같이 쓰는 패턴이 많아요.
  - **GKE**: 기본 옵션 중 하나가 Calico.
  - **AKS**: Calico + Cilium 둘 다 지원.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **NetworkPolicy를 코드로 관리** → DevSecOps 친화, Git에서 보안 정책 리뷰
- **iptables 기반 데이터플레인**이 검증된 기술 — 새로운 장애 패턴이 적어요
- **CNCF Graduated** — 가장 성숙한 단계. 장기 유지보수 보장
- **OSS + Tigera 상용판** 듀얼 라인 — 학습/소형은 OSS, 엔터프라이즈는 Tigera로 자연스럽게 이전

### 2.4 시장 위치

- CNCF Survey 기준 **CNI 채택 1위** 자리를 수년간 유지 (Calico).
- 최근 3년간 **Cilium의 추격이 빠름** — eBPF가 가져온 성능/관측성 차이가 강해서.
- 우리 학습 시점(2026) 기준 신규 도입은 Cilium 비중↑, 기존 운영은 여전히 Calico 우세.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 대안 | NetworkPolicy | 학습/문서 | 우리 환경 적합도 | 최종 판단 |
|---|---|---|---|---|
| **Calico (VXLAN)** | ✅ | ★★★★★ | ★★★★★ (베어메탈, 학습 자료↑) | ✅ |
| Cilium | ✅✅ (L7) | ★★★★ | ★★★ (eBPF 학습 곡선) | △ (다음 라운드) |
| Flannel | ❌ | ★★★★ | ★★ (정책 없음, PII 분리 불가) | ✗ |
| Weave Net | ✅ | ★★ | ★ (개발 중단) | ✗ |

### 3.2 현업 표준과의 정합성

- **kubeadm + Calico**: K8s 공식 문서가 가장 먼저 예시로 드는 조합.
- **Tigera Operator**: 단순 manifest apply가 아닌 **operator pattern**으로 진화한 정공법.
- **VXLAN 모드**: BGP가 없는 환경(=우리)에서 가장 호환성 좋음. IPIP는 일부 클라우드 보안 그룹과 충돌.

### 3.3 선택 근거 (트레이드오프)

| 선택 | 얻는 것 | 잃는 것 |
|---|---|---|
| **Calico** | 풍부한 문서, 안정적 iptables, NetworkPolicy 표준 | Cilium 대비 L7 정책/관측성 부족 |
| **VXLAN 모드** | 스위치 BGP 설정 불필요 → 학습 부담↓ | BGP 모드 대비 ~5% 성능 손실 |
| **Tigera Operator 방식** | Calico 업그레이드/설정이 선언적 | 단순 manifest 대비 한 단계 추가 |

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
   Pod 네트워크 10.244.0.0/16 (Calico VXLAN)
   ─────────────────────────────────────────

   [k8s-cp1]   [k8s-cp2]   [k8s-cp3]   [k8s-w1]   [k8s-w2]   [k8s-w3]
   10.244.0.*  10.244.1.*  10.244.2.*  10.244.3.*  10.244.4.*  10.244.5.*
   (블록 26)   (블록 26)   (블록 26)    (블록 26)   (블록 26)   (블록 26)

        VXLAN 터널 (UDP 4789)
        ◄──────────────────────────────────────────►

   물리 네트워크 VLAN 30 (172.16.23.0/24) — pfSense GW
```

각 노드에 `/26` 블록(64개 IP)이 자동 할당돼요. Pod이 부족해지면 Calico가 추가 블록을 받습니다.

### 4.2 핵심 설정값과 근거

| 항목 | 값 | 근거 |
|---|---|---|
| Calico 버전 | `v3.27.0` | K8s 1.30과 호환되는 LTS 라인 |
| 설치 방식 | **Tigera Operator** | 공식 권장. 업그레이드 안전 |
| 데이터플레인 모드 | **VXLAN** | BGP 미설정 + 호환성↑ |
| Pod CIDR | `10.244.0.0/16` | group_vars/all.yml과 일치 |
| blockSize | `26` (64 IP/노드) | 6노드면 충분, 노드 추가에 여유 |
| natOutgoing | `Enabled` | Pod → 외부망 SNAT (외부 통신 가능) |

### 4.3 다른 컴포넌트와의 연결

```
[Calico] ─→ Pod IP 할당
              │
              ▼
[Service (kube-proxy)] ─→ Pod IP 묶음에 가상 ClusterIP 부여
              │
              ▼
[MetalLB] ─→ Service Type=LoadBalancer에 외부 IP 부여
              │
              ▼
[HAProxy Ingress] ─→ HTTP(S) 라우팅 → Service → Pod
```

Calico는 **가장 아래 레이어**에서 Pod IP를 만들기 때문에, 이게 안 되면 위 모든 컴포넌트가 무용지물이에요. 그래서 K8s 초기화 후 가장 먼저 설치합니다.

---

## 5. 실제 코드 / 설정 파일

### 5.1 Tigera Operator 설치 (`40-k8s-addons.yml`)

경로: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (라인 69~76)

```yaml
- name: Tigera Operator 설치 (Calico 관리 도구)
  kubernetes.core.k8s:
    state: present
    src: https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  register: tigera_apply
  retries: 5
  delay: 15
  until: tigera_apply is succeeded
```

**왜 이 옵션?**

- `tigera-operator.yaml`을 그대로 적용 → CRD + 컨트롤러 한 번에 설치
- `retries: 5, delay: 15`: HA 클러스터 초기엔 etcd leader가 계속 바뀌어서 `etcdserver: leader changed` 일시 에러 자주 발생. 자동 재시도로 흡수

### 5.2 Installation CR (Calico 본체 설정)

이어지는 task:

```yaml
- name: Calico Installation 리소스 적용
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: operator.tigera.io/v1
      kind: Installation
      metadata:
        name: default
      spec:
        calicoNetwork:
          ipPools:
            - blockSize: 26
              cidr: "{{ pod_subnet }}"      # 10.244.0.0/16
              encapsulation: VXLAN          # IPIP보다 호환성 좋음
              natOutgoing: Enabled
              nodeSelector: all()
  register: calico_install
  retries: 5
  delay: 15
  until: calico_install is succeeded
```

**왜 이 옵션?**

- `encapsulation: VXLAN`: 우리는 BGP 미설정 환경이고, pfSense에서 IPIP 프로토콜이 약간 까다로움. VXLAN이 가장 무난.
- `natOutgoing: Enabled`: Pod이 외부(인터넷, GHCR 등)로 나갈 때 노드 IP로 SNAT. 안 켜면 외부에서 회신 못 와요.
- `blockSize: 26`: 1노드당 64개 IP. 우리는 노드당 Pod 30~50개 수준이라 충분.
- `nodeSelector: all()`: 모든 노드에 적용. 일부 노드만 다른 풀 쓸 일 없음.

### 5.3 DaemonSet 대기 로직

```yaml
- name: calico-system 네임스페이스 생성 대기 (Operator가 만듦)
  ansible.builtin.shell: |
    kubectl get namespace calico-system >/dev/null 2>&1
  register: ns_check
  retries: 30
  delay: 10
  until: ns_check.rc == 0
  changed_when: false

- name: calico-node DaemonSet 생성 대기
  ansible.builtin.shell: |
    kubectl -n calico-system get daemonset calico-node -o name >/dev/null 2>&1
  register: ds_check
  retries: 30
  delay: 10
  until: ds_check.rc == 0
  changed_when: false

- name: Calico 노드 Pod 모두 Ready 될 때까지 대기 (최대 5분)
  ansible.builtin.command: >
    kubectl wait --for=condition=Ready pods -n calico-system
    -l k8s-app=calico-node --timeout=300s
  retries: 3
  delay: 30
```

**왜 이 옵션?**

- Operator → Installation CR 반영 → DaemonSet 생성까지 **시간차**가 있어요. `kubectl wait`를 바로 호출하면 "no matching resources" 에러.
- 그래서 **3단계로 점진 대기**: namespace → DaemonSet → Pod Ready 순서.

---

## 6. 실행 + 결과

### 6.1 설치는 40-k8s-addons.yml에 포함되어 자동

```bash
ssh bastion
cd ~/ansible
ansible-playbook playbooks/40-k8s-addons.yml
```

### 6.2 검증

```bash
kubectl get pods -n calico-system
```

우리 환경 기대 출력:

```
NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-xxx                1/1     Running   0          3d
calico-node-aaaaa                          1/1     Running   0          3d
calico-node-bbbbb                          1/1     Running   0          3d
calico-node-ccccc                          1/1     Running   0          3d
calico-node-ddddd                          1/1     Running   0          3d
calico-node-eeeee                          1/1     Running   0          3d
calico-node-fffff                          1/1     Running   0          3d
calico-typha-xxx                           1/1     Running   0          3d
```

`calico-node`가 6개 (DaemonSet이라 노드당 1개) 다 Running이면 OK.

```bash
kubectl get installation default -o jsonpath='{.spec.calicoNetwork.ipPools}'
```

```
[{"blockSize":26,"cidr":"10.244.0.0/16","encapsulation":"VXLAN","natOutgoing":"Enabled"}]
```

### 6.3 Pod-to-Pod 통신 테스트

```bash
kubectl run a --image=busybox --restart=Never -- sh -c "sleep 3600"
kubectl run b --image=busybox --restart=Never -- sh -c "sleep 3600"
kubectl exec a -- ping -c 3 $(kubectl get pod b -o jsonpath='{.status.podIP}')
```

기대: 100% 응답.

### 6.4 NetworkPolicy 예시 (PII 분리)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
  namespace: pii-protected
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: pii-protected
```

이 정책 하나로 **pii-protected** namespace의 모든 Pod는 같은 namespace 안에서만 트래픽 수신. 다른 namespace의 Pod이 직접 접근 불가 → PII 보호.

---

## 7. 함정 + 디버깅

### 함정 1 — Tigera Operator 적용 시 `etcd leader changed` 에러

**증상**: `kubernetes.core.k8s` task가 다음 에러로 실패.

```
etcdserver: leader changed
```

**원인 (메커니즘)**: 우리 클러스터 부트스트랩 직후엔 다음 일이 동시에 벌어져요.
- kubeadm init이 끝나고 막 3 CP가 합류한 시점 — etcd 멤버 추가
- 메모리 압박 + Ceph RBD 일시 지연이 겹침
- Raft가 leader heartbeat를 놓침 → 새 leader 선출
- 선출 진행 중에 들어온 API 호출은 모두 `leader changed` 응답

이게 1~3초 안에 회복되지만, Ansible의 단발 호출엔 치명적.

**해결**: `retries: 5, delay: 15, until: succeeded` 추가. `40-k8s-addons.yml`의 거의 모든 `kubernetes.core.k8s` task에 동일 패턴을 적용했어요.

```yaml
register: tigera_apply
retries: 5
delay: 15
until: tigera_apply is succeeded
```

**왜 이 함정이 발생하는가**: K8s API server는 모든 쓰기를 **etcd quorum write**으로 처리해요. quorum이 일시적으로 깨지거나 leader가 바뀌면 그 쓰기는 즉시 실패. 따라서 모든 멱등한 쓰기 작업은 retry가 필수예요.

### 함정 2 — calico-node 일부만 NotReady

**증상**:

```bash
kubectl get pods -n calico-system
# calico-node-cp1   Running
# calico-node-cp2   CrashLoopBackOff   ← 이거 하나만
```

**원인 (메커니즘)**: 해당 노드에서 다음 둘 중 하나가 흔해요.
1. **방화벽이 VXLAN UDP 4789 차단** — 노드 간 인캡 패킷 통과 못 함
2. **kernel module 누락** — `vxlan` 모듈이 안 떠있음

**해결**:

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.11 'sudo lsmod | grep vxlan'
```

비어있으면:

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.11 'sudo modprobe vxlan'
```

그리고 `/etc/modules-load.d/k8s.conf`에 `vxlan` 추가해서 영구화.

### 함정 3 — Pod이 IP는 받았는데 외부 통신 불가

**증상**: `ping 8.8.8.8` 실패.

**원인**: `natOutgoing: Enabled`가 없거나 false. SNAT 안 되면 Pod의 10.244.x.x 출발 패킷이 외부 라우터에 가서 "이게 누구야?" 하고 버려져요.

**해결**:

```bash
kubectl edit installation default
# spec.calicoNetwork.ipPools[0].natOutgoing: Enabled
```

### 함정 4 — Calico와 Pod CIDR 불일치

**증상**: Pod이 `ContainerCreating`에서 멈춤. describe하면 `network plugin is not ready`.

**원인**: `kubeadm init --pod-network-cidr=10.244.0.0/16`로 만들었는데 Installation CR의 cidr이 `192.168.0.0/16` 같이 다른 경우. CNI가 어디서 IP를 받아야 할지 모름.

**해결**: 우리는 `group_vars/all.yml`의 `pod_subnet`이 두 곳에서 모두 참조되도록 변수화. 변수화 안 하면 흔히 빠지는 함정이에요.

```yaml
# all.yml
pod_subnet: "10.244.0.0/16"

# 30-k8s-init.yml — kubeadm init
--pod-network-cidr={{ pod_subnet }}

# 40-k8s-addons.yml — Calico Installation
cidr: "{{ pod_subnet }}"
```

---

## 8. 더 깊이 공부할 자료

### 공식 문서
- Calico 공식 문서: https://docs.tigera.io/calico/latest/
- CNI 스펙: https://github.com/containernetworking/cni/blob/main/SPEC.md
- K8s NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/

### 영상 / 강의
- "Calico Deep Dive" — Tigera 공식 KubeCon 발표 시리즈
- "Container Networking from Scratch" — Kelsey Hightower 발표

### 책
- *Container Networking* (O'Reilly) — CNI 전반
- *Kubernetes Networking* (K8s 네트워킹 종합)

### 인증
- **Calico Certified Operator** (Tigera 제공)
- CKA 시험에 NetworkPolicy 문제가 매년 출제

### 우리 프로젝트 관련 파일
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (Calico 설치 부분)
- `/Users/sangjjang/kosa_infra_project/ansible/inventory/group_vars/all.yml` (pod_subnet 정의)
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md` (etcd retry 추가 기록)

---

> 다음 챕터 미리보기 — 외부에서 K8s 서비스에 어떻게 접근할까요? MetalLB로 베어메탈에서 LoadBalancer 만들고 cert-manager로 TLS 자동화합니다.
