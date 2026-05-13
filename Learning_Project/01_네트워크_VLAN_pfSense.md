# 01. 네트워크 — VLAN, pfSense, HA

> Layer 1 / 학습 시간 1일 / 등급 🟡 (운영 OK)
> 선수 지식: TCP/IP 기본, 라우팅 개념

---

## 이 단원에서 배우는 것

1. **네트워크 분리** — 왜 한 LAN에 다 두면 안 되는가
2. **VLAN** — 가상 LAN의 원리와 한계
3. **L2 vs L3 스위치** — 우리가 매니지드 L3을 쓰는 이유
4. **pfSense의 정체** — 라우터? 방화벽? 다 맞음
5. **CARP/HA** — 왜 방화벽도 이중화해야 하는가
6. **우리 환경의 VLAN 설계** — 10/20/30/40 각각의 역할

---

## 1) 왜 네트워크 분리가 필요한가

### 모든 장비가 같은 LAN에 있다면?

```
[관리 노트북 4대] [Proxmox 4대] [K8s VM 6대] [DB VM 3대]
        │              │              │              │
        └──────────────┴──────────────┴──────────────┘
                       하나의 LAN (예: 192.168.1.0/24)
```

문제점:
- **보안**: 노트북이 해킹되면 DB까지 직접 접근 가능
- **브로드캐스트 폭발**: ARP, DHCP 패킷이 모든 장비에 전파
- **권한 통제 불가**: "DB는 K8s에서만 접근" 같은 룰 구현 불가
- **성능**: 트래픽이 한 세그먼트에 몰림

### 그래서 분리한다

```
[관리 노트북] ─── VLAN 40 (Management) ─── 172.16.24.0/24
[Proxmox 관리] ─── VLAN 99 (PVE Mgmt)  ─── 192.168.21.0/24
[K8s VM 6대]  ─── VLAN 30 (Internal)   ─── 172.16.23.0/24
[DMZ 노출]    ─── VLAN 20 (DMZ)        ─── 172.16.22.0/24
[Public]      ─── VLAN 10 (Public)     ─── 172.16.21.0/24
```

각 VLAN은 **L2 broadcast domain이 분리**되고, 서로 통신하려면 **L3 라우팅** 거쳐야 함.

---

## 2) VLAN이란?

### 정의

VLAN (Virtual LAN) = **하나의 물리 스위치를 여러 논리 스위치로 나누는 기술**.

```
[물리 스위치 24포트]
   │
   ├─ 포트 1~6  → VLAN 10 (Public)
   ├─ 포트 7~12 → VLAN 20 (DMZ)
   ├─ 포트 13~18 → VLAN 30 (Internal)
   └─ 포트 19~24 → VLAN 40 (Management)
```

각 VLAN은 **L2 수준에서 완전히 분리**된 것처럼 동작. 같은 스위치에 꽂혀 있어도 다른 VLAN끼린 ARP도 안 통함.

### 802.1Q 태그

VLAN을 구현하는 표준. 이더넷 프레임에 **4바이트 태그** 추가:

```
[기존 프레임] [목적지 MAC][출발지 MAC][TYPE][데이터]
[VLAN 프레임] [목적지 MAC][출발지 MAC][802.1Q tag: VLAN ID = 30][TYPE][데이터]
                                       ^^^^^^^^^^^^^^^^^^^^^^^
                                       이 12비트가 VLAN ID (1~4094)
```

### Access 포트 vs Trunk 포트

| 종류 | 동작 | 사용처 |
|---|---|---|
| **Access** | 한 VLAN만, 태그 없이 전달 | 일반 PC, 서버 |
| **Trunk** | 여러 VLAN 동시, 태그 보존 | 스위치↔스위치, 스위치↔하이퍼바이저 |

우리 환경:
- 노트북 → 스위치 = **Access** (VLAN 99 만)
- 스위치 → Proxmox = **Trunk** (VLAN 10/20/30/40 모두 통과)

---

## 3) L2 스위치 vs L3 스위치 vs 라우터

### 정의 차이

| 장비 | 동작 계층 | 무엇을 보고 전달 | 우리 환경 역할 |
|---|---|---|---|
| **L2 스위치 (비매니지드)** | Layer 2 | MAC 주소 | (없음) |
| **L2 매니지드 스위치** | Layer 2 + VLAN | MAC + VLAN ID | 보조 분배 |
| **L3 스위치** | Layer 3 (라우팅 가능) | IP 주소 | Spine-Leaf 패브릭 (10G) |
| **라우터** | Layer 3 + 고급 기능 | IP + 정책 | pfSense (방화벽 포함) |

### 우리는 왜 L3 매니지드 스위치를 쓰나

CLAUDE.md 보면:
```
JTCOM JT-S508CL-8S L3 8포트 10G 매니지드 스위치 7대
  - Spine 스위치 2대
  - Leaf 스위치 5대
  - Ceph 클러스터링용 Spine-Leaf 패브릭 구성
```

**이유:**
1. **VLAN 지원** — 비매니지드는 VLAN 못 함
2. **L3 라우팅** — Spine-Leaf 패브릭은 OSPF/BGP로 라우팅 (Ceph 트래픽이 라우터를 안 거쳐 빠르게 흐름)
3. **10GbE** — Ceph public/cluster 네트워크에 필수

비매니지드 스위치는 단순 hub 처럼 동작 — 학습용으로도 부족.

---

## 4) pfSense의 정체

### 한 마디로

**pfSense = FreeBSD 기반 오픈소스 방화벽/라우터 어플라이언스**.

이 한 장비가 동시에:
- 🛡 **방화벽** (iptables/pf 룰)
- 🔀 **라우터** (정적/동적 라우팅)
- 🌐 **NAT** (Source/Destination NAT)
- 📡 **DHCP 서버**
- 🔐 **VPN 서버** (IPsec, OpenVPN, WireGuard)
- 📊 **트래픽 모니터링**
- 🌍 **VLAN 게이트웨이**

우리 환경에서 pfSense가 하는 일:

```
[인터넷] ──→ [pfSense WAN]
              │
              ├─ VLAN 10 게이트웨이 (172.16.21.1)
              ├─ VLAN 20 게이트웨이 (172.16.22.1)
              ├─ VLAN 30 게이트웨이 (172.16.23.1) — DHCP 활성
              ├─ VLAN 40 게이트웨이 (172.16.24.1) — DHCP 활성
              │
              └─ 방화벽 룰 (각 VLAN 간 통신 통제)
```

VLAN 간 통신은 **반드시 pfSense를 통과**. 예:
- VLAN 30 (K8s VM) → VLAN 40 (Bastion) ⟶ pfSense가 룰 검사 후 허용/차단

### pfSense vs OPNsense vs IPFire

| 항목 | **pfSense** | OPNsense | IPFire |
|---|---|---|---|
| 베이스 OS | FreeBSD | FreeBSD | Linux |
| UI | 안정적 | 더 현대적 | 단순 |
| 커뮤니티 | 매우 큼 | 큼 | 작음 |
| 상용 지원 | Netgate (유료) | Deciso | 없음 |
| 학습 자료 | 풍부 | 점점 늘어남 | 부족 |
| **선택 이유** | 학습 자료 풍부 + 가장 검증됨 | - | - |

OPNsense가 더 모던하긴 하지만, **자료가 더 많고 KOSA에서도 다루는 게 pfSense**라 선택.

### pfSense vs 클라우드의 보안 그룹

| | pfSense (온프레) | AWS Security Group | Azure NSG |
|---|---|---|---|
| 위치 | 네트워크 경계 | VPC 안 | VNet 안 |
| 룰 적용 | 패킷 통과 시 | 인스턴스 단위 | 서브넷/NIC |
| Stateful | O | O | O |
| L7 검사 | O (Snort/Suricata 가능) | X | Application GW 별도 |

발표 어필: **"온프레의 pfSense = 클라우드의 SG/NSG에 해당. L7까지 검사 가능한 점이 SG보다 강력."**

---

## 5) CARP/HA — 왜 방화벽도 이중화?

### 단일 pfSense의 문제

```
[모든 트래픽] ──→ [pfSense 1대] ──→ [내부]
                       │
                       └─ 다운 시?
                            └─ 전사 인터넷/내부 통신 모두 마비
```

방화벽은 **모든 트래픽의 단일 통과점** — 죽으면 전사 마비. SPOF(Single Point of Failure).

### CARP (Common Address Redundancy Protocol)

CARP = **두 대 이상의 장비가 가상 IP(VIP)를 공유**하는 프로토콜. VRRP의 BSD 버전.

```
[pfSense-1] MASTER ──┐
                     ├─ VIP 192.168.21.10 (CARP)
[pfSense-2] BACKUP ──┘

평상시: 모든 트래픽이 pfSense-1으로
pfSense-1 다운 시: BACKUP이 자동으로 MASTER 승격 → VIP가 pfSense-2로 이동
            (~3초 안에 페일오버)
```

내부 장비 입장에선 게이트웨이가 `192.168.21.10` 으로 같음. 누가 MASTER인지 신경 안 씀.

### CARP를 위한 3가지 구성요소

1. **CARP VIP** — 가상 IP (Active 노드가 응답)
2. **pfsync** — 두 pfSense 간 상태 동기화 (연결 상태, NAT 테이블 등)
3. **XMLRPC Sync** — 설정 동기화 (룰, DHCP, VPN 설정)

세 가지 다 있어야 진정한 HA.

### 우리 환경

```
[Proxmox 4대 중 2대 위에 pfSense VM 2대]
  - pfsense-1 (VMID 101) on kosa1 = MASTER
  - pfsense-2 (VMID 104) on kosa2 = BACKUP
  - CARP VIP = 192.168.21.10

pfsync 인터페이스: 별도 VLAN 또는 직결 (pfSense간 빠른 동기화)
```

학습 포인트:
- **물리 pfSense 어플라이언스 2대가 정석** — 우리는 VM으로 함 (하드웨어 4대 제약)
- 발표 시엔 "**전용 어플라이언스로 분리 배치**"한 것처럼 그림 그리기 (실제용/발표용 다이어그램 분리)

### 페일오버 시나리오 데모

데모 시:
```bash
# Active (pfsense-1) 셧다운
ssh root@kosa1 'qm shutdown 101'

# 3초 후 BACKUP이 MASTER로 승격
# 내부 호스트는 끊김 거의 없이 계속 통신
ping 8.8.8.8   # 잠시 멈췄다가 재개
```

발표 어필: **"방화벽 자체도 SPOF가 안 되도록 CARP+pfsync로 Active-Passive 페일오버. 3초 내 자동 복구."**

---

## 6) 우리 환경의 VLAN 설계

### 전체 그림

```
┌──────────────────────────────────────────────────────────────┐
│ Internet                                                      │
└────────────────────────┬─────────────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │  TP-Link 라우터       │  192.168.21.1
              │  (간단한 NAT 처리)    │
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │  관리형 L2 스위치     │
              │  (port2,5 가용)      │
              └──────────┬──────────┘
                         │
        ┌────────┬───────┼───────┬──────┐
        │        │       │       │      │
   [노트북 4대]                       [Proxmox 4대]
   192.168.21.x                  192.168.21.2~5
                                        │
                                        ├─ pfSense VM × 2 (CARP HA)
                                        │   CARP VIP 192.168.21.10
                                        │
                                        ├─ VLAN 10 게이트웨이 172.16.21.1
                                        ├─ VLAN 20 게이트웨이 172.16.22.1
                                        ├─ VLAN 30 게이트웨이 172.16.23.1 (DHCP)
                                        └─ VLAN 40 게이트웨이 172.16.24.1 (DHCP)
```

### VLAN별 역할

| VLAN | 대역 | 이름 | 용도 | DHCP |
|---|---|---|---|---|
| 10 | 172.16.21.0/24 | **Public** | 외부에 공개하는 서비스 (현재 미사용, 향후 확장) | - |
| 20 | 172.16.22.0/24 | **DMZ** | MetalLB IP 풀 (172.16.22.50~100), HAProxy Ingress | - |
| 30 | 172.16.23.0/24 | **Internal** | K8s 노드 (cp1~3, w1~3), 일반 서비스 | DHCP 100~200 |
| 40 | 172.16.24.0/24 | **Management** | Bastion, Ansible runner | DHCP 100~200 |

### 왜 4개로 나눴나

| VLAN | 왜 분리? |
|---|---|
| **VLAN 10 (Public)** | 외부 노출 서비스만 — 침입 시 내부 영향 최소화 |
| **VLAN 20 (DMZ)** | LoadBalancer IP 풀 — 내부 IP 노출 방지 |
| **VLAN 30 (Internal)** | K8s 노드 통신 — 외부 접근 차단 |
| **VLAN 40 (Management)** | Bastion + 운영 도구 — 일반 사용자 못 들어오게 |

방화벽 룰 단순 예시:
```
VLAN 40 → VLAN 30: 허용 (Bastion에서 K8s SSH OK)
VLAN 30 → VLAN 40: 차단 (K8s 노드에서 Bastion으로 못 옴, 침투 차단)
VLAN 10 → VLAN 30: 차단
VLAN 20 → VLAN 30: 제한적 (특정 포트만)
```

---

## 7) Spine-Leaf 패브릭 (Ceph 전용)

### 일반 Hub-and-Spoke 와의 차이

```
[Hub-and-Spoke]                  [Spine-Leaf]
       ┌────┐                  ┌────┐    ┌────┐
       │Hub │                  │Sp1 │    │Sp2 │
       └─┬──┘                  └─┬──┘    └─┬──┘
    ┌────┼────┐                  │ ╲  ╱   │
    │    │    │                  │  ╲╱    │
   [s1] [s2] [s3]              ┌─┴──┬─┴─┐ │
                               │L1  │L2 │ │
                               └────┴───┘ │
                                          ▼
                                    각 서버는 Leaf에 연결
                                    Leaf끼리 통신은 Spine 경유
                                    경로 다양 (L1→Sp1→L2 또는 L1→Sp2→L2)
```

### 왜 Ceph는 Spine-Leaf인가

- **대역폭** — Hub가 병목. Spine 여러 대로 분산
- **장애 격리** — Spine 1대 다운돼도 Spine 2가 처리
- **East-West 트래픽** — Ceph는 OSD 끼리 복제 트래픽이 대부분 → 노드 간 통신 최적화 필요

우리 구성: Spine 2대 + Leaf 5대 + Ceph 노드 6대 (각 노드가 Leaf에 연결).

### 학습 포인트

발표 시: **"데이터센터급 Spine-Leaf 아키텍처를 학습 환경에 구현. 향후 노드 추가 시 수평 확장 가능."**

---

## 8) 실습

### 명령 1 — VLAN 트래픽 확인

```bash
# Proxmox 호스트에서
ssh root@kosa1
ip -br link show | grep vlan

# 특정 VLAN의 트래픽 캡처
tcpdump -i vmbr0.30 -nn host 172.16.23.10
```

### 명령 2 — pfSense CARP 상태

pfSense Web UI:
- Status → CARP (failover)
- MASTER/BACKUP 상태 확인

### 명령 3 — VLAN 간 통신 테스트

```bash
# Bastion (VLAN 40)에서 K8s 노드 (VLAN 30) 핑
ssh bastion
ping 172.16.23.10
# pfSense 룰 허용이라 응답

# 반대 방향 (차단된 룰일 경우)
ssh k8s-cp1
ping 172.16.24.10
# pfSense가 차단 → no response
```

---

## 9) 발표 어필 멘트

> *"우리 환경은 4개 VLAN (Public, DMZ, Internal, Management)으로 보안 경계를 구분하고, pfSense HA로 방화벽 자체의 가용성도 확보했습니다. CARP+pfsync로 Active-Passive 페일오버가 3초 안에 완료되며, 모든 VLAN 간 트래픽은 pfSense 룰을 통과합니다. Ceph 스토리지망은 별도 10GbE Spine-Leaf 패브릭으로 East-West 트래픽 병목을 제거했습니다."*

---

## 10) 추가 학습 자료

- pfSense 공식 docs: https://docs.netgate.com/pfsense/
- Spine-Leaf 패브릭 설명: Cisco DC 설계 가이드
- VLAN 802.1Q 표준: IEEE 802.1Q-2018

---

## 11) 우리 프로젝트 적용 — 더 깊이

- 구체적인 VLAN별 IP/DHCP 풀: [`../project/03_네트워크_설계.md`](../project/03_네트워크_설계.md)
- pfSense HA 구축 절차: `pfSense_HA_Setup_Guide.md` (프로젝트 루트)
- 트래픽 흐름 다이어그램: `Architecture_Design.md` (프로젝트 루트)

---

## 다음 단원

학습 완료 후 → [`02_가상화_Proxmox.md`](02_가상화_Proxmox.md)

체크리스트:
- [ ] VLAN의 원리 설명 가능
- [ ] L2/L3 스위치 차이 설명 가능
- [ ] pfSense가 하는 7가지 역할 나열 가능
- [ ] CARP/pfsync 차이 설명 가능
- [ ] 우리 4개 VLAN의 용도 외움
- [ ] Spine-Leaf 패브릭 동작 그릴 수 있음
