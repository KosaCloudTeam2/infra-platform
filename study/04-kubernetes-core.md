# 챕터 04 — Kubernetes 핵심 (kubeadm, etcd, kubelet, containerd)

> KOSA 인프라 프로젝트 학습 시리즈
> 분량: 15~18 페이지
> 선수 챕터: 02 가상화/Proxmox, 03 네트워크/VLAN

---

## 학습 후 알 수 있는 것

- Kubernetes 클러스터가 **Control Plane 5개 컴포넌트 + Worker 3개 컴포넌트**로 어떻게 협력하는지 그림 그리며 설명할 수 있어요.
- **kubeadm**으로 3-CP HA 클러스터를 만드는 흐름과, 우리 환경에서 왜 6노드(3 CP + 3 Worker) 구성을 택했는지 근거를 댈 수 있어요.
- **etcd가 왜 Raft 합의로 동작하고, 왜 홀수(3/5/7)대여야 하는지**, 그리고 leader change가 왜 우리 환경에서 자주 일어났는지 메커니즘 수준에서 이해해요.
- `kubectl connection refused`, `etcd leader changed`, `cp1 OOM` 같은 실제로 우리가 겪은 함정의 원인을 추적하고 해결할 수 있어요.
- 우리 클러스터(`v1.30.14`, `containerd 2.2.1`)의 핵심 설정값 — pod CIDR `10.244.0.0/16`, service CIDR `10.96.0.0/12`, control-plane-endpoint `172.16.23.10` — 이 왜 그렇게 정해졌는지 설명할 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Kubernetes(K8s)는 컨테이너화된 워크로드를 선언적으로 정의하면, 클러스터 전체에 걸쳐 배치·복구·확장·롤아웃을 자동으로 수행하는 오케스트레이션 플랫폼입니다.**

### 1.2 등장 배경

컨테이너(Docker)는 2013~2015년 사이 폭발적으로 퍼졌어요. 그런데 컨테이너를 한두 개 띄우는 건 쉬워도 100개, 1000개를 운영하기 시작하면 다음 질문들이 한꺼번에 쏟아져요.

- "이 컨테이너는 어느 서버에 띄울까?"
- "컨테이너가 죽으면 누가 다시 살리지?"
- "트래픽이 한쪽으로 몰리는데 자동으로 늘려줄 수 있나?"
- "새 버전 배포할 때 무중단으로 가능?"
- "어느 서버의 메모리가 부족하면 다른 서버로 옮길 수 있나?"

이 모든 걸 사람이 수동으로 하던 시대를 끝낸 게 K8s예요. 구글이 내부에서 10년 넘게 운영하던 **Borg**의 경험을 오픈소스로 풀어낸 게 2014년의 K8s 1.0이에요. 이후 CNCF(Cloud Native Computing Foundation)에 기증되며 사실상의 컨테이너 표준이 되었습니다.

### 1.3 핵심 개념 + 용어 풀이

먼저 단어부터 익숙해져야 해요. 영어로 도배되어 있지만, **각 단어가 무엇을 책임지는지** 한 줄로 외우면 다음이 쉬워져요.

| 용어 | 한 줄 풀이 |
|---|---|
| **Pod** | 같이 살고 같이 죽는 컨테이너 1개 이상의 묶음. K8s가 다루는 최소 단위. |
| **Node** | 컨테이너가 실제로 도는 머신(VM 또는 물리). CP 노드 / Worker 노드로 나뉨. |
| **Cluster** | CP + Worker 노드들의 집합. 하나의 K8s. |
| **Namespace** | 한 클러스터 안에서 리소스를 논리적으로 나누는 폴더. `kosa-app`, `monitoring`처럼. |
| **Deployment** | 상태 없는(stateless) Pod를 N개 유지하는 컨트롤러. 롤링 업데이트 지원. |
| **StatefulSet** | 상태 있는(stateful) Pod에 안정적 이름·디스크를 줌. DB, 메시지 큐. |
| **DaemonSet** | 모든 노드에 Pod 1개씩 자동 배치. CNI, 로그 수집기 등. |
| **Service** | Pod 묶음에 안정된 가상 IP/DNS 부여. Pod이 죽고 살아도 IP 유지. |
| **Ingress** | 외부 HTTP(S) 트래픽을 Service로 라우팅. L7 게이트웨이. |
| **ConfigMap / Secret** | 설정값(평문) / 자격증명(base64) 저장소. Pod에 env나 파일로 마운트. |
| **PersistentVolume(PV) / Claim(PVC)** | 스토리지 추상화. PVC가 요청하면 StorageClass가 PV를 동적으로 만듦. |
| **Control Plane(CP)** | 클러스터의 두뇌. api-server, etcd, scheduler, controller-manager가 핵심. |
| **Worker** | 사용자 워크로드를 실행하는 노드. kubelet + containerd. |

### 1.4 동작 원리 (내부 메커니즘)

K8s의 핵심 아이디어는 단 하나, **선언적(Declarative) + 컨트롤 룹(Control loop)** 이에요.

```
사용자: "ticket-app Pod 2개를 원해" (YAML로 선언)
       │
       ▼
[API Server] ───→ [etcd] (원하는 상태 저장)
       │
       ▼
[Controller Manager]
   현재 상태(Pod 0개) vs 원하는 상태(Pod 2개) 비교
   부족분 발견 → Pod 객체 생성 요청
       │
       ▼
[Scheduler]
   Pod을 어느 Node에 둘지 결정 (자원, anti-affinity 등 고려)
       │
       ▼
[Worker Node의 kubelet]
   "내 노드에 Pod 가져가야 한대" → containerd에 컨테이너 실행 명령
       │
       ▼
[containerd] → 컨테이너 RUN!
```

이 룹이 1초도 안 쉬고 돌아가요. Pod이 죽으면 → 현재 상태 1개로 떨어짐 → controller가 차이를 발견 → 다시 만듦. 이 패턴을 **reconciliation loop**라고 부릅니다.

### 1.5 주요 기능

| 기능 | 무엇을 자동화하나 |
|---|---|
| **Self-healing** | Pod 죽으면 재생성, Node 죽으면 다른 Node로 이전 |
| **Scaling (HPA/VPA)** | CPU/메모리 사용량 기준 Pod 개수/크기 자동 조절 |
| **Rolling update / Rollback** | 점진적 새 버전 배포 + 문제 시 한 줄로 롤백 |
| **Service discovery** | Pod에 DNS 부여, IP 바뀌어도 이름으로 접근 |
| **Load balancing** | Service의 트래픽을 Pod 여러 개에 분산 |
| **Secret/Config 관리** | 환경설정/자격증명을 코드 밖으로 분리 |
| **Storage orchestration** | PVC 요청만으로 Ceph/EBS/NFS 자동 프로비저닝 |
| **Batch execution** | Job/CronJob으로 일회성/정기 작업 |

### 1.6 다른 도구와 비교

| 도구 | 포지션 | 장점 | 단점 | 우리 평가 |
|---|---|---|---|---|
| **Kubernetes** | 사실상 표준 | 생태계 압도적, 모든 클라우드 지원, 학습 자산 가치↑ | 학습 곡선 가파름 | ✅ 채택 |
| Docker Swarm | 단순 | docker-compose와 거의 동일 | 생태계 사그라듦, 클라우드 미지원 | 학습 가치↓ |
| Nomad (HashiCorp) | 가볍고 다목적 | 컨테이너+VM+raw exec 통합 | 시장 점유율 작음, 인력 풀 좁음 | 대안 미고려 |
| OpenShift | K8s 상용판 | RBAC 강력, GUI 풍부, 엔터프라이즈 지원 | 라이선스 비용↑, 자유도↓ | 학습 부담↑ |
| k3s | 경량 K8s | 단일 바이너리, 엣지에 적합 | 멀티 CP HA 학습엔 부족 | 학습 가치↓ |
| ECS / Fargate | AWS 전용 | 운영 부담↓ | 락인, 온프레 불가 | 하이브리드 부적합 |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

K8s는 다음 중 두 개 이상에 해당하면 진지하게 도입을 고려해요.

- **마이크로서비스 10개 이상** — 서비스 간 디스커버리, 배포 자동화가 손으로 안 됨
- **트래픽 변동 5배 이상** — 오토스케일링 필수 (티켓팅, 라이브 커머스가 전형)
- **무중단 배포 SLA** — 롤링 업데이트/카나리 빌트인
- **멀티 환경(개발/스테이징/운영)** — 동일 매니페스트로 환경만 갈아끼움
- **하이브리드/멀티 클라우드** — 같은 K8s API로 온프레/AWS/GCP 모두 운영

우리 KOSA 프로젝트는 **온프레미스 + AWS 하이브리드 + 티켓팅 트래픽 변동**이라는 세 가지 조건을 다 만족해서 K8s가 자연스러운 선택이었어요.

### 2.2 업계 표준 구성, 대표 사용 기업/사례

업계에서 본 표준 K8s 운영 구성:

- **CP 3대 + Worker 다수**: HA를 위한 최소 구성. 우리도 3 CP.
- **etcd 외장 또는 stacked** — Stacked(CP에 etcd 같이)가 기본, 200+ 노드 클러스터는 외장 etcd
- **CNI는 Calico / Cilium** — NetworkPolicy 지원 필수
- **CSI는 클라우드별** — AWS EBS CSI, GCE PD CSI, 온프레는 Ceph CSI / Longhorn
- **인증/인가**: OIDC(Keycloak, Okta) + RBAC + (조직 따라) OPA Gatekeeper

대표 사용 기업:

- **AWS / GCP / Azure**: 자사 매니지드 K8s (EKS / GKE / AKS) 제공
- **국내**: 카카오, 네이버, 쿠팡, 토스, 우아한형제들 등 거의 모든 IT 빅테크
- **글로벌**: Spotify, Airbnb, Pinterest, Box, GitHub 등이 공개 발표한 K8s 운영 사례 보유

### 2.3 왜 효율이 좋은가 (현업 관점)

- **인프라 활용률↑**: bin-packing scheduler가 노드 자원을 빈틈없이 채움. 평균 활용률이 가상화만 쓰던 시절(20~30%)에서 50~70%로 올라가요.
- **운영 인력↓**: self-healing으로 새벽 호출이 줄고, 동일 패턴(YAML)으로 모든 워크로드 관리 → 1인당 운영 가능 워크로드 수 증가.
- **개발 → 운영 인터페이스 단일화**: 개발자가 "이 매니페스트로 띄워주세요" 만 하면 운영팀이 환경별로 맞춰주는 핸드오프 사라짐.
- **클라우드 비교 협상력**: 동일 매니페스트가 AWS/GCP/온프레에 다 도는 덕에 단일 벤더 락인이 풀려요.

### 2.4 시장 위치

- **CNCF Survey 2023**: 프로덕션 K8s 도입률 **84%** (조사 응답 기업 기준).
- **컨테이너 오케스트레이션 시장 점유율**: K8s가 사실상 90%+ 단일 표준. Swarm·Nomad는 한 자릿수.
- **트렌드**: 단순한 컨테이너 실행을 넘어 **플랫폼(IDP, Internal Developer Platform)**, **AI/ML 워크로드(Kubeflow, Ray)**, **Edge K8s(k3s, MicroK8s)** 등으로 확장 중.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 대안 | 학습 가치 | 멀티 클러스터 | 온프레+클라우드 통일 | 4인 팀 운영 부담 | 최종 판단 |
|---|---|---|---|---|---|
| **Kubernetes (kubeadm)** | ★★★★★ | 가능 | 가능 (EKS와 동일 API) | 중 | ✅ |
| Docker Swarm | ★★ | 제한적 | AWS에서 사그라듦 | 낮음 | ✗ (취업 가치↓) |
| Nomad | ★★★ | 가능 | 가능 | 낮음 | ✗ (인력 풀↓) |
| k3s | ★★★ | 가능 | 가능 | 낮음 | ✗ (HA 학습 부족) |
| OpenShift | ★★★★ | 가능 | 가능 | 높음 (학습) | ✗ (취업 후 학습이 적절) |

### 3.2 현업 표준과의 정합성

- **kubeadm**: 공식 도구. EKS/GKE 내부도 동일 컴포넌트.
- **stacked etcd**: 6노드 클러스터에선 표준.
- **CNI Calico, MetalLB, cert-manager**: CNCF Graduated/Incubating 프로젝트로 엔터프라이즈에서 가장 흔한 조합.
- **containerd 런타임**: Docker shim이 K8s 1.24부터 제거되면서 사실상 표준 런타임.

### 3.3 선택 근거 (트레이드오프)

선택한 길과 그 대가:

| 선택 | 얻는 것 | 잃는 것 / 감수한 것 |
|---|---|---|
| **kubeadm 수동 설치** | K8s 내부 동작을 깊이 이해, 면접·발표 자산 | kubespray 대비 손이 더 가고 디버깅 비용↑ |
| **stacked etcd (CP에 같이)** | 노드 수 절약, 구성 단순 | etcd가 CP 자원 경쟁의 대상이 됨 → leader change 빈발 |
| **3 CP + 3 Worker** | quorum 안전, anti-affinity 가능 | Worker 자원 한정 (32GB×3) — 메모리 빡빡 |
| **v1.30.14 (LTS-ish)** | EKS와 버전 정합성, 신기능 활용 | v1.30은 1년 후 EOL → 정기 업그레이드 필요 |

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
                   [노트북 / Mgmt]
                   192.168.21.x
                         │
                         │ SSH
                         ▼
                   [Bastion (172.16.24.10)]
                   kubectl / helm / ansible
                         │
                         │ K8s API (443/6443)
                         ▼
            ┌────────── VLAN 30 (172.16.23.0/24) ──────────┐
            │                                              │
   ┌────────┼────────┐  ┌────────┼────────┐  ┌────────┼────────┐
   │   k8s-cp1       │  │   k8s-cp2       │  │   k8s-cp3       │
   │   172.16.23.10  │  │   172.16.23.11  │  │   172.16.23.12  │
   │   on kosa4      │  │   on kosa2      │  │   on kosa3      │
   │  ┌─────────────┐│  │  ┌─────────────┐│  │  ┌─────────────┐│
   │  │api-server   ││  │  │api-server   ││  │  │api-server   ││
   │  │etcd         ││  │  │etcd         ││  │  │etcd         ││
   │  │controller-m ││  │  │controller-m ││  │  │controller-m ││
   │  │scheduler    ││  │  │scheduler    ││  │  │scheduler    ││
   │  │kubelet      ││  │  │kubelet      ││  │  │kubelet      ││
   │  │containerd   ││  │  │containerd   ││  │  │containerd   ││
   │  └─────────────┘│  │  └─────────────┘│  │  └─────────────┘│
   └─────────────────┘  └─────────────────┘  └─────────────────┘

   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
   │   k8s-w1        │  │   k8s-w2        │  │   k8s-w3        │
   │   172.16.23.20  │  │   172.16.23.21  │  │   172.16.23.22  │
   │   on kosa3      │  │   on kosa4      │  │   on kosa2      │
   │  ┌─────────────┐│  │  ┌─────────────┐│  │  ┌─────────────┐│
   │  │kubelet      ││  │  │kubelet      ││  │  │kubelet      ││
   │  │containerd   ││  │  │containerd   ││  │  │containerd   ││
   │  │kube-proxy   ││  │  │kube-proxy   ││  │  │kube-proxy   ││
   │  │Calico pods  ││  │  │Calico pods  ││  │  │Calico pods  ││
   │  │app pods ... ││  │  │app pods ... ││  │  │app pods ... ││
   │  └─────────────┘│  │  └─────────────┘│  │  └─────────────┘│
   └─────────────────┘  └─────────────────┘  └─────────────────┘
```

요점:

- **VLAN 30(172.16.23.0/24)** 안에 K8s 노드 6대. 라우팅은 pfSense.
- 6대 모두 **VM**. Proxmox kosa1~4에 분산 배치.
- **CP 3대**는 의도적으로 **다른 Proxmox 호스트**에 분산 → 하이퍼바이저 1대 죽어도 quorum 유지.
- **Bastion은 VLAN 40(Mgmt)** 에 별도로 두어 K8s 멤버 아님. 도구만 보관.

### 4.2 핵심 설정값과 근거

| 항목 | 값 | 근거 |
|---|---|---|
| K8s 버전 | `1.30.14` | EKS 1.30과 동시 운영, 1.30은 ipv6 dual-stack 등 안정화 |
| Pod CIDR | `10.244.0.0/16` | RFC1918 + Calico 기본값. /16 = 65k IP, 충분 |
| Service CIDR | `10.96.0.0/12` | K8s 기본값. Pod/Service 충돌 회피 |
| control-plane-endpoint | `172.16.23.10:6443` | 1차로 cp1 IP 직접 사용. 추후 keepalived VIP로 |
| 컨테이너 런타임 | `containerd 2.2.1` | Docker shim 제거된 1.24+에선 사실상 표준 |
| Cgroup driver | `systemd` | kubelet/containerd 둘 다 systemd로 통일 (driver 불일치는 흔한 함정) |
| API 포트 | `6443` | K8s 기본 |
| etcd 배치 | stacked (CP에 같이) | 노드 수 절약 |

`group_vars/all.yml`에 위 값이 한 곳에 모여 있어요 (`/Users/sangjjang/kosa_infra_project/ansible/inventory/group_vars/all.yml`).

### 4.3 다른 컴포넌트와의 연결

```
[Ceph 클러스터]  ──(CSI driver)──→ [K8s PVC] ─→ Pod의 /data
[pfSense]        ──(VLAN GW)─────→ [K8s 노드 외부 통신]
[MetalLB]        ──(L2)──────────→ [Service Type=LoadBalancer]
[Calico]         ──(VXLAN)───────→ [Pod 네트워크 10.244.0.0/16]
[ArgoCD]         ──(K8s API)─────→ [Deployment/Service 자동 sync]
[GHCR]           ──(image pull)──→ [Pod 컨테이너 이미지]
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 `group_vars/all.yml` — 클러스터 전역 변수

경로: `/Users/sangjjang/kosa_infra_project/ansible/inventory/group_vars/all.yml`

```yaml
# K8s 버전 (kubeadm/kubelet/kubectl 모두 동일하게)
kubernetes_version: "1.30"

# Pod / Service 네트워크 CIDR
pod_subnet:     "10.244.0.0/16"   # Calico/Cilium 기본값과 호환
service_subnet: "10.96.0.0/12"    # K8s 기본값

# 클러스터 API 엔드포인트
kubernetes_api_endpoint: "172.16.23.10"   # k8s-cp1 IP (임시)
kubernetes_api_port: 6443

# CNI 선택
cni_plugin: calico
calico_version: "v3.27.0"
```

**왜 이 옵션?**

- `kubernetes_version: "1.30"`: MAJOR.MINOR만 핀. 패치는 apt가 자동. 너무 좁게 핀하면 보안 패치 적용이 어려워요.
- `pod_subnet`: 10.244는 K8s 커뮤니티에서 가장 흔한 기본값. 사내망(172.16/12)과 안 겹치는 게 핵심.
- `service_subnet`: /12라 1M IP. 일반 환경에선 더 크게 잡을 이유가 거의 없어요.

### 5.2 `30-k8s-init.yml` — kubeadm으로 클러스터 만드는 코어 부분

경로: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/30-k8s-init.yml`

핵심 task 한 덩어리:

```yaml
- name: kubeadm init 실행
  ansible.builtin.shell: |
    kubeadm init \
      --control-plane-endpoint "{{ kubernetes_api_endpoint }}:{{ kubernetes_api_port }}" \
      --upload-certs \
      --pod-network-cidr={{ pod_subnet }} \
      --service-cidr={{ service_subnet }} \
      --kubernetes-version=v{{ kubernetes_version }}.0 \
      --node-name={{ inventory_hostname }}
  when: not kubeconfig_check.stat.exists
```

**왜 이 옵션?**

- `--control-plane-endpoint`: HA에 필수. **나중에 cp2/cp3가 join할 때 이 주소로 인증서가 발급**돼요. 단일 IP를 적으면 그 노드 다운 시 신규 join이 막힘. 본래는 keepalived VIP를 쓰지만 우리는 1차로 cp1 IP로 시작.
- `--upload-certs`: 다른 CP가 join할 때 자동으로 CA 키를 받게 해줘요. 안 쓰면 사람이 손으로 복사해야 함.
- `--pod-network-cidr`: Calico가 이 범위 안에서 IP 할당.
- `--node-name`: ansible inventory의 hostname 사용. 호스트명이 IP로 잡히는 흔한 함정 회피.
- `when: not kubeconfig_check.stat.exists`: **멱등성**. `/etc/kubernetes/admin.conf` 이미 있으면 skip → 재실행해도 안전.

이어지는 워커 join 부분:

```yaml
- name: Worker join 실행
  ansible.builtin.shell: |
    {{ hostvars[groups['k8s_control_plane'][0]].worker_join }} \
      --node-name={{ inventory_hostname }}
  when: not kubelet_check.stat.exists
```

- 첫 CP에서 `kubeadm token create --print-join-command`로 받은 join 명령을 `set_fact`로 다른 호스트에서도 접근 가능하게 만든 뒤 그대로 실행.

### 5.3 `inventory/hosts.yml` — 누가 CP고 누가 Worker인지

경로: `/Users/sangjjang/kosa_infra_project/ansible/inventory/hosts.yml`

```yaml
all:
  children:
    k8s_control_plane:
      hosts:
        k8s-cp1: { ansible_host: 172.16.23.10 }
        k8s-cp2: { ansible_host: 172.16.23.11 }
        k8s-cp3: { ansible_host: 172.16.23.12 }
    k8s_workers:
      hosts:
        k8s-w1: { ansible_host: 172.16.23.20 }
        k8s-w2: { ansible_host: 172.16.23.21 }
        k8s-w3: { ansible_host: 172.16.23.22 }
    k8s_cluster:
      children:
        k8s_control_plane:
        k8s_workers:
```

이 그룹화 덕분에 playbook에서 `hosts: k8s_control_plane[0]`(첫 CP만), `hosts: k8s_workers`(워커만) 같이 깔끔하게 분기됩니다.

---

## 6. 실행 + 결과

### 6.1 단계별 실행 명령

전체 부트스트랩은 5단계로 끊어서 실행해요.

```bash
ssh bastion
cd ~/ansible
```

```bash
ansible-playbook playbooks/00-bootstrap.yml
```

```bash
ansible-playbook playbooks/10-k8s-prepare.yml
```

```bash
ansible-playbook playbooks/20-k8s-install.yml
```

```bash
ansible-playbook playbooks/30-k8s-init.yml
```

```bash
ansible-playbook playbooks/40-k8s-addons.yml
```

### 6.2 검증 명령과 우리 실제 출력

```bash
kubectl get nodes -o wide
```

우리 실제 출력 (정상 상태):

```
NAME      STATUS   ROLES           AGE     VERSION    INTERNAL-IP     OS-IMAGE
k8s-cp1   Ready    control-plane   3d12h   v1.30.14   172.16.23.10    Ubuntu 24.04.1 LTS
k8s-cp2   Ready    control-plane   3d12h   v1.30.14   172.16.23.11    Ubuntu 24.04.1 LTS
k8s-cp3   Ready    control-plane   3d12h   v1.30.14   172.16.23.12    Ubuntu 24.04.1 LTS
k8s-w1    Ready    <none>          3d12h   v1.30.14   172.16.23.20    Ubuntu 24.04.1 LTS
k8s-w2    Ready    <none>          3d12h   v1.30.14   172.16.23.21    Ubuntu 24.04.1 LTS
k8s-w3    Ready    <none>          3d12h   v1.30.14   172.16.23.22    Ubuntu 24.04.1 LTS
```

전체 시스템 Pod 확인:

```bash
kubectl get pods -A | grep -vE "Running|Completed"
```

기대 출력: **빈 줄** (모두 Running이면 grep -v로 다 걸러져요).

### 6.3 etcd 멤버십 확인 (HA 핵심)

```bash
kubectl exec etcd-k8s-cp1 -n kube-system -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

기대:

```
abc... started k8s-cp1  https://172.16.23.10:2380  https://172.16.23.10:2379  false
def... started k8s-cp2  https://172.16.23.11:2380  https://172.16.23.11:2379  false
ghi... started k8s-cp3  https://172.16.23.12:2380  https://172.16.23.12:2379  false
```

3개가 모두 `started`면 **quorum = 2/3** 유지. 1대 죽어도 클러스터 살아있어요.

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 함정 1 — `etcdserver: leader changed` 일시 에러

**증상**: Ansible playbook 실행 중 `kubernetes.core.k8s` task가 다음 에러로 종종 실패.

```
etcdserver: leader changed
```

**원인 (메커니즘)**: etcd는 **Raft 합의 알고리즘**으로 동작해요. 3대 중 1대가 leader가 되고 나머지가 follower. 우리 환경에선 다음 조합으로 leader change가 자주 발생했어요.

- CP 노드 4GB만 할당했더니 메모리 압박 → kubelet/etcd가 일시적으로 응답 지연
- Ceph RBD IO가 일시 지연되면서 etcd의 WAL 쓰기가 막힘
- heartbeat timeout(100ms 기본) 초과 → follower가 "leader가 죽었나?" 판단해 새 선거 시작
- 잠시 후 옛 leader가 돌아옴 → 또 선거 → leader change 반복

이게 1~3초 안에 회복되지만, 그 사이 들어온 API 호출은 실패하죠.

**해결**: `40-k8s-addons.yml`의 모든 K8s 리소스 적용 task에 retry 추가.

```yaml
- name: Tigera Operator 설치
  kubernetes.core.k8s:
    state: present
    src: https://.../tigera-operator.yaml
  register: tigera_apply
  retries: 5
  delay: 15
  until: tigera_apply is succeeded
```

5번 × 15초 = 최악의 경우 75초 동안 자동 재시도. 거의 모든 leader change를 흡수합니다.

### 함정 2 — `kubectl: The connection to the server ... was refused`

**증상**:

```
$ kubectl get nodes
The connection to the server 172.16.23.10:6443 was refused - did you specify the right host or port?
```

**원인**: `~/.kube/config`의 server URL이 cp1(172.16.23.10) 단일 IP. cp1이 다운(또는 etcd leader 이동 중)이면 즉시 실패해요.

**해결**: 임시로 살아있는 다른 CP로 우회.

```bash
kubectl config set-cluster kubernetes --server=https://172.16.23.11:6443
```

장기 해결: **keepalived VIP**를 만들어 `control-plane-endpoint`를 VIP로 바꾸는 게 정공법. 우리는 시간 관계상 다음 이터레이션으로 미뤘어요.

### 함정 3 — cp1이 자주 OOM/리부팅

**증상**: kosa1에 올라간 cp1 VM이 하루 1~2회 자체 리부팅. dmesg에 OOM kill 흔적.

**원인 (메커니즘)**: kosa1에는 cp1뿐 아니라 pfSense-1 VM도 있었어요. Proxmox kosa1의 32GB 메모리 중:
- pfSense-1: ~4GB
- 다른 백그라운드 VM
- cp1: 4GB
- 호스트 Proxmox 자체: ~2GB

→ 합산이 75%를 넘으면서 메모리 압박. cp1 안에서 kubelet + etcd + api-server + controller + scheduler가 동시에 메모리를 끌어쓰면 OOM 발생.

**해결**: cp1을 메모리 여유 있는 kosa4로 마이그레이션.

```bash
ssh kosa1 'qm migrate 210 kosa4 --online'
```

마이그레이션 후 inventory.md의 cp1 위치를 `kosa4`로 갱신. 이후 OOM 사라짐.

### 함정 4 — `WATCH_NAMESPACE` 때문에 Operator가 CR을 못 봄

**증상**: PerconaXtraDBCluster CR을 만들었는데도 Pod이 안 만들어짐. Events 비어있고, Operator 로그에 `RBAC: ... forbidden` 에러.

**원인 (메커니즘)**: K8s의 **namespace-scoped Role vs ClusterRole** 차이를 모르면 빠지는 함정.

- Operator는 환경변수 `WATCH_NAMESPACE`로 어느 ns를 감시할지 정함
- 처음엔 `pxc-operator` (자기 ns) 만 지정. 우리 PXC CR은 `pii-protected`에 있음 → 안 보임
- `WATCH_NAMESPACE=""` 로 모든 ns 보게 했더니 RBAC forbidden. **namespace-scoped Role만 있는데 cluster-wide 감시를 시도**해서.

**해결**: 두 단계.

```bash
kubectl edit deployment -n pxc-operator percona-xtradb-cluster-operator
# WATCH_NAMESPACE를 valueFrom → value: "pxc-operator,pii-protected" 로

# Role을 pii-protected ns에도 복제
kubectl get role -n pxc-operator -o yaml | \
  sed "s/namespace: pxc-operator/namespace: pii-protected/g" | \
  kubectl apply -f -

kubectl create rolebinding pxc-operator-binding -n pii-protected \
  --serviceaccount=pxc-operator:percona-xtradb-cluster-operator \
  --role=percona-xtradb-cluster-operator
```

핵심 깨달음: **RBAC scope와 WATCH_NAMESPACE는 매칭되어야 한다**. cluster-wide 보려면 ClusterRole, 특정 ns만 보려면 그 ns에 Role 복제.

### 함정 5 — kubelet이 갑자기 NotReady

**증상**: `kubectl get nodes`에 한 노드만 `NotReady`. describe 보면 `kubelet stopped posting node status`.

**원인**: 흔한 경로 둘.
1. **시간 동기화 어긋남**: chrony 죽음 → 인증서 시간 불일치
2. **cgroup driver 불일치**: containerd가 cgroupfs, kubelet은 systemd 같은 미스매치

**해결 절차**:

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.22 'sudo systemctl status kubelet'
```

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.22 'sudo journalctl -u kubelet --tail=50'
```

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.22 'sudo systemctl restart kubelet'
```

대개 재시작으로 회복. 안 되면 위 두 가지 원인 (시간/cgroup) 확인.

---

## 8. 더 깊이 공부할 자료

### 공식 문서
- Kubernetes 공식: https://kubernetes.io/docs/concepts/
- kubeadm 가이드: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- etcd: https://etcd.io/docs/

### 책 / 시리즈
- *Kubernetes in Action* (Marko Lukša) — 입문~중급의 결정판
- *Kubernetes Up & Running* — Brendan Burns(K8s 공동창시자) 저서
- *Programming Kubernetes* — Operator/CRD 개발 깊이

### 강의
- KubeCon 발표 영상 (CNCF YouTube)
- "Kubernetes the Hard Way" (Kelsey Hightower) — kubeadm 없이 손으로 만들어보기

### 인증
- **CKA(Certified Kubernetes Administrator)**: 인프라/운영 트랙
- **CKAD(Certified Kubernetes Application Developer)**: 개발자 트랙
- **CKS(Certified Kubernetes Security Specialist)**: CKA 후 보안 심화

### 우리 프로젝트 관련 파일
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/30-k8s-init.yml` — kubeadm init 자동화
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` — CNI/MetalLB/Metrics 설치
- `/Users/sangjjang/kosa_infra_project/inventory.md` — 6노드 배치/디버깅 함정 표
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md` — 이번 운영에서 만난 함정 기록

---

> 다음 챕터 미리보기 — Pod끼리 어떻게 통신하는지, 왜 Calico를 골랐는지 들어갑니다.
