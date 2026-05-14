# 챕터 03 — pfSense HA + 네트워크 설계 (VLAN, dual-NIC)

> KOSA 인프라 프로젝트 학습용 문서 시리즈<br> 작성일: 2026-05-13<br> 선수 챕터:
> `01-project-overview.md`, `02-proxmox-cloudinit.md`<br> 후속 챕터: (예정) `04-k8s-bootstrap.md`

---

## 이 챕터 학습 후 알 수 있는 것

- **pfSense**가 정확히 무엇이고, 라우터/방화벽/DHCP/VPN 중 어떤 역할을 한꺼번에 하는지
- **CARP/pfsync/XMLRPC Sync** 세 개념의 차이와 함께 동작하는 방식
- **VLAN 10/20/30/40** 각각의 역할과 우리가 그렇게 나눈 이유
- **Dual-NIC 설계** (K8s 노드의 eth0 VLAN30 + eth1 Ceph 10G)가 왜 필요한지
- **Spine-Leaf 패브릭**이 무엇이고 Ceph 클러스터에서 왜 쓰는지
- **MTU 9000 (Jumbo Frame)** 이 왜 Ceph에 필요한지, 그리고 함정
- 실전에서 만난 함정 5가지: MetalLB IP 풀, VLAN 서브인터페이스 잔재, ICMP 라우팅, multicast
  snooping, XMLRPC Skew 복제

---

## 1. 기술 개요 (자세히)

### 1.1 정의 (한 문장)

#### pfSense

**pfSense**는 FreeBSD 기반의 **오픈소스 통합 게이트웨이 소프트웨어**예요. 한 박스에서 **라우터 +
방화벽 + VPN 서버 + DHCP/DNS + IDS/IPS + Captive Portal**를 다 처리해요. 쉽게 말하면 "동네 공유기
풀-버전".

#### VLAN

**VLAN (Virtual LAN, 802.1Q)** 은 **하나의 물리 스위치를 여러 논리 스위치로 나누는 기술**. 이더넷
프레임에 4바이트 태그(VLAN ID 12비트)를 박아서 분리해요.

#### CARP

**CARP (Common Address Redundancy Protocol)** 은 **여러 대 방화벽/라우터가 하나의 가상 IP(VIP)를
공유**하다가, MASTER 다운 시 BACKUP이 자동으로 그 VIP를 인계받는 프로토콜. BSD 진영의 VRRP 호환
구현체.

### 1.2 등장 배경 (어떤 문제 해결하려고?)

#### pfSense의 배경

2004년 m0n0wall 프로젝트의 포크로 시작. 당시 시장은:

- **Cisco IOS**: 강력하지만 라이센스 비싸고 GUI 부족
- **Linux iptables**: 강력하지만 운영 GUI 0
- **소호 공유기**: 쉬운데 기능 제한적

→ **"FreeBSD의 강력한 네트워크 스택 + 쉬운 웹 UI + 오픈소스"** 조합이 필요했어요. pfSense가 그
자리를 차지.

#### VLAN의 배경

옛날엔 부서별로 **물리적으로 다른 스위치**를 두고 분리했어요. 비용도 비싸고 배선도 복잡. 1998년 IEEE
802.1Q 표준이 나오면서 **"하나의 스위치에서 논리적 분리"** 가 가능해졌고, 이게 사실상 모든
엔터프라이즈 네트워크의 기본이 됐어요.

#### CARP의 배경

방화벽이 단일 장애점(SPOF)이면 위험해요. 1990년대 후반 Cisco가 **HSRP**(독점)를, 이후 IETF가
**VRRP**(표준)를 만들었고, OpenBSD/FreeBSD 진영이 라이센스 회피 위해 **CARP**를 별도로 만들었어요.
동작 원리는 거의 같아요.

### 1.3 핵심 개념 + 용어 풀이

| 용어                          | 풀이                                                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- |
| **L2 / L3**                   | OSI 모델 2층(MAC, 같은 LAN) / 3층(IP, 라우팅). VLAN은 L2 분리, 라우팅은 L3.                             |
| **VLAN ID**                   | 1~4094 범위 정수. 0과 4095는 예약. 우리는 10/20/30/40/99 사용.                                          |
| **Access 포트 vs Trunk 포트** | Access = 한 VLAN만 통과 (태그 없음, 일반 PC), Trunk = 여러 VLAN 통과 (태그 보존, 스위치↔하이퍼바이저)   |
| **PVID (Port VLAN ID)**       | Access 포트에서 untagged 패킷에 자동으로 부여되는 VLAN ID                                               |
| **VLAN-aware bridge**         | Linux 브리지가 802.1Q 태그를 인식하고 처리하는 모드. Proxmox에서 `bridge-vlan-aware yes`로 활성.        |
| **CIDR**                      | "172.16.23.0/24"처럼 IP + 서브넷 마스크 길이로 표기. /24는 256개 IP.                                    |
| **CARP MASTER/BACKUP**        | 하나의 VIP를 두고 MASTER가 응답하다가 다운 시 BACKUP이 인계                                             |
| **CARP Skew**                 | 우선순위 값 (0 = 가장 높음, 255 = 가장 낮음). 같은 VHID 그룹 안에서 낮은 쪽이 MASTER.                   |
| **VHID**                      | Virtual Host ID. 같은 가상 IP를 공유하는 CARP 그룹 식별자. 1~255.                                       |
| **pfsync**                    | 두 pfSense 사이에서 **상태 테이블(state table)** 을 실시간 동기화. TCP 세션이 페일오버 후에도 유지되게. |
| **XMLRPC Sync**               | 두 pfSense의 **설정값**을 동기화 (방화벽 룰, NAT 등). 단, Virtual IP는 동기화 제외 권장.                |
| **MTU**                       | Maximum Transmission Unit. 한 번에 보내는 IP 패킷 최대 크기. 일반 1500, Jumbo 9000.                     |
| **Jumbo Frame**               | MTU 9000 이상 이더넷 프레임. 패킷 수 ÷ 6 → CPU 부담 감소, 처리량 ↑.                                     |
| **Spine-Leaf 패브릭**         | 두 계층 (Spine 위 / Leaf 아래) 네트워크 토폴로지. 모든 Leaf가 모든 Spine에 연결. 데이터센터 표준.       |
| **MetalLB**                   | 온프레미스 K8s에서 LoadBalancer 타입 Service에 외부 IP 부여. L2 모드 (ARP) / BGP 모드.                  |

### 1.4 동작 원리 (내부 메커니즘)

#### pfSense의 동작

```
[WAN 인터페이스]  ──→ [방화벽 룰 (pf)] ──→ [라우팅 테이블] ──→ [LAN 인터페이스]
                        ↓
                  [NAT/Port forward]
                        ↓
                  [상태 테이블 (state)]
                        ↓
                  [VPN, IDS, DHCP 등 부가 기능]
```

- **pf** (packet filter): OpenBSD에서 가져온 패킷 필터. iptables 대비 표현력 ↑, 성능 ↑.
- **state table**: TCP 세션마다 1개 엔트리. 연결마다 5-tuple (src/dst IP, port, proto) 기록.
- **Per-VLAN 인터페이스**: 같은 물리 NIC에 VLAN 태그별로 가상 인터페이스 (`igb0_vlan10`,
  `igb0_vlan20`...) 생성.

#### CARP의 동작

```
[pfSense-1 (MASTER)]  ─── 224.0.0.18 multicast (1초 간격) ──→  [pfSense-2 (BACKUP)]
   VIP 172.16.23.1                                                  대기 상태
   ARP 응답 = MASTER MAC                                             3초간 multicast 끊기면 인계

[클라이언트] ARP 요청 "who has 172.16.23.1?"
     ↓
[pfSense-1] "그건 내 MAC: 00:00:5e:00:01:1e (VHID 30의 가상 MAC)"
     ↓
[클라이언트] 그 MAC으로 패킷 전송 → pfSense-1이 처리

[pfSense-1 다운]
     ↓ (3초 후)
[pfSense-2] 자신을 MASTER로 승격, 같은 가상 MAC을 자기 NIC에 추가
     ↓
[스위치] MAC 위치 학습 갱신 (Gratuitous ARP)
     ↓
[클라이언트] 같은 IP로 보내지만 이젠 pfSense-2가 처리
```

**페일오버 시간**: 3초 (CARP 기본 timeout). pfsync로 state까지 동기화되어 있으면 **TCP 세션 유지**.

#### VLAN 802.1Q 태그

```
[일반 프레임]
| Dst MAC (6B) | Src MAC (6B) | Type/Len (2B) | Data | FCS (4B) |

[VLAN 프레임 — 4바이트 태그 삽입]
| Dst MAC (6B) | Src MAC (6B) | 0x8100 (2B) | TCI (2B) | Type/Len | Data | FCS |
                                              │
                                              ├─ Priority (3 bits)
                                              ├─ DEI (1 bit)
                                              └─ VLAN ID (12 bits, 0-4095)
```

스위치는 이 12비트 VLAN ID를 보고 같은 VLAN끼리만 패킷 전달.

#### Dual-NIC 설계

```
[K8s 노드 (k8s-cp1)]
    ├── eth0 (NIC 1) ── VLAN 30 (172.16.23.10/24, gateway 172.16.23.1)
    │     │
    │     └─ K8s control plane, etcd, kubelet, Pod traffic
    │
    └── eth1 (NIC 2) ── Ceph 10G (10.10.10.110/24, gateway 없음)
          │
          └─ Ceph RBD IO 전용, jumbo frame
```

**왜 분리?** Pod 통신(보통 1Gbps) + Ceph IO(많을 땐 5~10 Gbps)를 같은 NIC에 두면 서로 영향. 분리하면
Ceph IO 폭주해도 K8s API 응답 안정.

### 1.5 주요 기능

#### pfSense

1. **상태 기반 방화벽 (Stateful)** — 연결 상태 추적, 응답 패킷 자동 허용
2. **NAT/Port Forwarding** — 외부 IP를 내부로
3. **VPN 서버** — IPsec, OpenVPN, WireGuard
4. **VLAN 인터페이스** — Tagged/Untagged 처리
5. **DHCP/DNS Resolver** — 로컬 IP 자동 할당
6. **CARP/pfsync HA** — 이중화
7. **IDS/IPS** (Snort/Suricata 패키지)
8. **Captive Portal** (게스트 와이파이용)
9. **gateway 그룹 + 정책 라우팅** — 멀티 WAN 라우팅 분기

#### VLAN/네트워크 설계

1. **보안 분리** — VLAN 간 라우팅을 pfSense가 통제
2. **브로드캐스트 도메인 축소** — ARP/DHCP 폭주 영향 격리
3. **QoS** — VLAN별 우선순위
4. **운영 권한 분리** — DB 관리자는 VLAN 30만 보임

### 1.6 다른 도구와 비교 (기술적 차이)

#### 게이트웨이/방화벽

| 도구                                  | 라이센스    | 특징                                               |
| ------------------------------------- | ----------- | -------------------------------------------------- |
| **pfSense (CE/Plus)**                 | Apache 2    | FreeBSD 기반, 풍부한 패키지, 현업 표준             |
| **OPNsense**                          | BSD         | pfSense 포크 (2015년), UI 다름, 보안 업데이트 빠름 |
| **Cisco IOS**                         | 상용        | 강력, 비싸고 폐쇄, 대기업 표준                     |
| **MikroTik RouterOS**                 | 상용 (저렴) | 가성비 좋음, CLI 깊음, 학습 곡선 가파름            |
| **Linux iptables/nftables + scripts** | GPL         | 완전 자유, GUI 0, 운영 부담 ↑                      |

#### CARP / VRRP / HSRP

| 프로토콜 | 출처          | 특징                                 |
| -------- | ------------- | ------------------------------------ |
| **CARP** | OpenBSD       | 라이센스 무료, pfSense/OPNsense 표준 |
| **VRRP** | IETF RFC 5798 | 표준, Cisco/Juniper/Linux Keepalived |
| **HSRP** | Cisco 독점    | 가장 오래됨, Cisco 전용              |

세 프로토콜 모두 **"가상 IP + 가상 MAC + 우선순위 + multicast heartbeat"** 동일한 패턴이에요. 사실상
호환 가능 (단, 같은 프로토콜끼리만 동작).

#### 데이터센터 네트워크

| 토폴로지                             | 특징                                                          |
| ------------------------------------ | ------------------------------------------------------------- |
| **3-tier (Core/Aggregation/Access)** | 옛 표준, North-South 트래픽 위주                              |
| **Spine-Leaf**                       | 모던 표준, East-West (서버간) 트래픽 최적화. Ceph/K8s에 적합. |
| **Hyperscale (Fat-Tree, CLOS)**      | Google/Facebook 규모                                          |

우리 Ceph 클러스터는 **Spine 2 / Leaf 5의 미니 Spine-Leaf** 구조예요.

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 이게 필요한가

#### pfSense가 잘 맞는 상황

- **중소기업/스타트업 본사 네트워크** — 한 박스로 모든 것 처리
- **소규모 데이터센터 게이트웨이** — 라이센스 부담 없이 풀 기능
- **VPN 서버** — IPsec/OpenVPN을 본사에 두고 원격 지사 연결
- **VMware/Proxmox와 같이** — 게이트웨이 가상화

#### VLAN 분리가 필수인 상황

- **PCI DSS 컴플라이언스** — 결제 데이터망은 일반망과 물리적/논리적 분리 필수
- **HIPAA, 개인정보보호법** — PII 망 격리
- **OT/IT 분리** — 공장 제어망과 사무망 격리

#### CARP HA가 필수인 상황

- **게이트웨이가 죽으면 전사 인터넷 마비**되는 환경
- **VPN 서버를 통해 본사 ↔ 지사 통신**하는데 끊기면 안 됨
- **SLA 99.9% 이상 요구**되는 서비스

### 2.2 업계에서 보통 어떻게 쓰나

#### pfSense 표준 사용 패턴

```
[ISP 라우터]
       │
       ▼
[pfSense HA × 2 (CARP)]   ← 메인 게이트웨이
       │
       ├── VLAN 10 (Server farm)
       ├── VLAN 20 (DMZ)
       ├── VLAN 30 (Internal)
       └── VLAN 99 (Management)
```

**대표 사용 사례**:

- **북미 중소기업**: 점유 1위 (Spiceworks 2023)
- **유럽 학교/대학**: 비용 효율
- **한국**: 카페/식당 와이파이부터 중견기업까지
- **MSP (Managed Service Provider)**: 고객사 게이트웨이로 대량 배포

#### VLAN 설계 표준

엔터프라이즈 표준 분류:

| VLAN 용도         | 일반적인 ID 범위    |
| ----------------- | ------------------- |
| Management        | 1, 99, 999          |
| Server (Internal) | 100~199             |
| DMZ               | 200~299             |
| User VLAN         | 10~50               |
| VoIP              | 4 (Cisco 권장), 100 |
| Guest Wi-Fi       | 80, 200             |
| Storage / iSCSI   | 500~600             |

> 우리 환경은 **10/20/30/40/99**로 단순화. 학습 환경에 적정.

### 2.3 왜 효율이 좋은가 (현업 관점)

#### 운영 관점

```
[VLAN 미분리 시]:
  - 새 서비스 만들 때마다 방화벽 룰 복잡 (port 단위로 구분)
  - PII 노출 사고 = 회사 전체 영향
  - 트러블슈팅 시 어디서 트래픽 새는지 찾기 어려움

[VLAN 분리 + pfSense]:
  - 룰을 VLAN 단위로 (예: VLAN 30 → VLAN 40 차단)
  - 사고 시 VLAN 단위 격리 가능
  - Wireshark도 VLAN 별로 떠서 분석 쉬움
```

#### 비용 관점

- pfSense 박스 2대 + L3 매니지드 스위치 ≈ 100~200만원
- 동급 Cisco/Palo Alto 솔루션 ≈ 1000만원 이상

#### 성능 관점

- pfSense는 FreeBSD의 `pf`를 사용 → Linux nftables와 비슷한 수준의 성능
- CARP 페일오버 3초 이내 (운영 기준 충분)
- VLAN 자체는 거의 무료 (CPU 부담 ~0%)

#### 학습 곡선

- pfSense Web UI: 첫 1~2일이면 익숙
- VLAN 개념: 한 번 이해하면 평생 자산
- CARP/HA: 일주일 정도 실험 필요

### 2.4 시장 위치

- **오픈소스 방화벽 점유**: pfSense ~45%, OPNsense ~30%, 기타 (Spiceworks 2024)
- **글로벌 SMB 방화벽**: pfSense는 Top 3 (FortiGate, SonicWall과 함께)
- **트렌드**: 2020년 이후 pfSense Plus (유료 SaaS화) 노선과 OPNsense (완전 무료) 분기. 학습 환경엔
  pfSense CE도 무료.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

#### 방화벽

| 대안                        | 장점                                    | 단점                           | 우리 결정                        |
| --------------------------- | --------------------------------------- | ------------------------------ | -------------------------------- |
| **pfSense**                 | 무료, 풍부한 GUI, VPN/IDS 통합, HA 표준 | UI 일부 옛 디자인              | ✅ 선택                          |
| OPNsense                    | 더 신선한 UI, 보안 빠름                 | 패키지 생태계 pfSense보다 작음 | 거의 동급, pfSense 이력서 가치 ↑ |
| Linux iptables + Keepalived | 완전 자유                               | GUI 0, 운영 부담               | ❌ 학습 환경 부적합              |
| Cisco ASA                   | 강력, 표준                              | 라이센스 비쌈, 학습 자원 부족  | ❌ 예산                          |

#### VLAN 분리

| 대안                          | 장점                       | 단점                     | 우리 결정         |
| ----------------------------- | -------------------------- | ------------------------ | ----------------- |
| **VLAN 분리 (10/20/30/40)**   | 표준, 보안 분리, 운영 단순 | 약간의 학습 곡선         | ✅ 선택           |
| 단일 LAN                      | 가장 단순                  | 보안/관리 권한 분리 불가 | ❌ 현업 표준 아님 |
| L3 segmentation (별도 라우터) | 강한 분리                  | 비용 ↑, 학습 가치 분산   | 과한 설계         |

#### HA

| 대안                    | 장점                           | 단점                     | 우리 결정                  |
| ----------------------- | ------------------------------ | ------------------------ | -------------------------- |
| **CARP (pfSense 표준)** | pfSense 네이티브, 3초 페일오버 | VRRP/HSRP와 비호환       | ✅ 선택                    |
| 단일 pfSense            | 단순                           | SPOF                     | ❌ 학습 가치 ↓             |
| Active-Active           | 처리량 ↑                       | 설정 복잡, 비대칭 라우팅 | 단순화 위해 Active-Passive |

### 3.2 현업 표준과의 정합성

우리 구성은 **중견기업 표준** 그대로예요:

| 우리 컴포넌트               | 현업 대응물                          |
| --------------------------- | ------------------------------------ |
| pfSense HA                  | Palo Alto HA, Fortinet HA, F5        |
| L3 매니지드 스위치          | Cisco Catalyst, Aruba                |
| VLAN 10/20/30/40            | 거의 모든 엔터프라이즈가 비슷한 패턴 |
| Spine-Leaf 패브릭           | 데이터센터 모던 표준                 |
| Jumbo Frame on Storage VLAN | iSCSI/Ceph 등 스토리지망 표준        |

### 3.3 선택 근거 (트레이드오프)

**받아들인 단점**:

1. **pfSense가 Proxmox VM에 얹어짐** — 하드웨어 4대 한계. 발표용 다이어그램은 별도 어플라이언스로
   그리되 멘트로 설명.
2. **Active-Passive (Active-Active 아님)** — pfsense는 둘 다 동시 active 운영 가능하나 비대칭 라우팅
   함정. 단순화 선택.
3. **MTU 9000은 Ceph 망에만** — 외부망까지 적용 시 어디서든 1500 패킷 만나면 fragmentation. 분리
   운영.
4. **XMLRPC Sync 부분 사용** — Virtual IP는 동기화 안 함 (Skew까지 복사되어 split-brain 위험). 수동
   관리 부담 있음.

**그래도 선택한 이유**:

- 현업 표준 그대로 학습 가치 큼
- HA 구성을 직접 만들어 보는 것이 핵심 학습 포인트
- 발표 시연 시 "방화벽 한 대 죽여도 서비스 계속"이 강력한 메시지

---

## 4. 우리 환경 구성

### 4.1 토폴로지

#### 전체 네트워크 계층도

```
                       [Omada Router]  192.168.21.1
                                │
                       [관리형 스위치]  ← VLAN 1/10/20/30/40/99
                ┌───────┬───────┴───────┬───────┐
                │       │               │       │
            (Trunk) (Trunk)         (Trunk) (Trunk)
                │       │               │       │
            ┌───▼───┐ ┌─▼─────┐     ┌───▼───┐ ┌─▼─────┐
            │ kosa1 │ │ kosa2 │     │ kosa3 │ │ kosa4 │   ← Proxmox 4대
            │┌─────┐│ │┌─────┐│     │       │ │       │
            ││pf-1 ││ ││pf-2 ││     │       │ │       │
            ││MAST.││◄┤│BACK.││     │       │ │       │
            │└─────┘│ │└─────┘│     │       │ │       │
            └───────┘ └───────┘     └───────┘ └───────┘
                  ▲       ▲ pfsync (VLAN 99)
                  └───────┘
                     │
                  CARP VIP
                  - WAN  : 192.168.21.10
                  - VL10 : 172.16.21.1
                  - VL20 : 172.16.22.1
                  - VL30 : 172.16.23.1   ← K8s 노드 gateway
                  - VL40 : 172.16.24.1   ← Bastion gateway

[K8s 노드는 K8s VLAN 30 (eth0) + Ceph 10G (eth1)]
                                        │
                              ┌─────────┴──────────┐
                              │                    │
                          [Spine SW1]        [Spine SW2]
                              │ │                │ │
                       ┌──────┘ └────────┬───────┘ └──────┐
                       │                 │                │
                  [Leaf SW1] [Leaf SW2] ...  [Leaf SW5]
                       │           │                │
                  [Ceph N1]   [Ceph N2]   ...  [Ceph N6]
                  10.10.10.x   10.10.10.x       10.10.10.x
                              (MTU 9000)
```

#### VIP 매핑

| 인터페이스          | 네트워크        | 게이트웨이 VIP | VHID |
| ------------------- | --------------- | -------------- | ---- |
| WAN                 | 192.168.21.0/24 | 192.168.21.10  | 1    |
| VLAN10 (Public)     | 172.16.21.0/24  | 172.16.21.1    | 10   |
| VLAN20 (DMZ)        | 172.16.22.0/24  | 172.16.22.1    | 20   |
| VLAN30 (Internal)   | 172.16.23.0/24  | 172.16.23.1    | 30   |
| VLAN40 (Management) | 172.16.24.0/24  | 172.16.24.1    | 40   |

#### pfSense 노드별 IP

| 항목                   | kosa1 (MASTER)        | kosa2 (BACKUP) |
| ---------------------- | --------------------- | -------------- |
| Proxmox 관리           | 192.168.21.2          | 192.168.21.3   |
| pfSense WAN            | 192.168.21.2          | 192.168.21.3   |
| pfSense LAN (VLAN10)   | 172.16.21.2           | 172.16.21.3    |
| pfSense VLAN20         | 172.16.22.2           | 172.16.22.3    |
| pfSense VLAN30         | 172.16.23.2           | 172.16.23.3    |
| pfSense VLAN40         | 172.16.24.2           | 172.16.24.3    |
| pfSense SYNC (VLAN 99) | 10.10.99.1            | 10.10.99.2     |
| CARP Skew              | **0** (우선순위 높음) | **100** (낮음) |

#### K8s 노드 Dual-NIC

| VM      | eth0 (VLAN 30)                  | eth1 (Ceph 10G)        |
| ------- | ------------------------------- | ---------------------- |
| k8s-cp1 | 172.16.23.10/24, gw 172.16.23.1 | 10.10.10.110/24, no gw |
| k8s-cp2 | 172.16.23.11/24, gw 172.16.23.1 | 10.10.10.111/24, no gw |
| k8s-cp3 | 172.16.23.12/24, gw 172.16.23.1 | 10.10.10.112/24, no gw |
| k8s-w1  | 172.16.23.20/24, gw 172.16.23.1 | 10.10.10.120/24, no gw |
| k8s-w2  | 172.16.23.21/24, gw 172.16.23.1 | 10.10.10.121/24, no gw |
| k8s-w3  | 172.16.23.22/24, gw 172.16.23.1 | 10.10.10.122/24, no gw |
| bastion | 172.16.24.10/24, gw 172.16.24.1 | (없음)                 |

> Bastion은 K8s 트래픽 없으므로 single-NIC. K8s 노드만 dual-NIC.

### 4.2 핵심 설정값과 근거 (왜 이 값?)

#### VLAN 설계

| VLAN ID     | 이름           | CIDR           | 게이트웨이  | 왜?                                                 |
| ----------- | -------------- | -------------- | ----------- | --------------------------------------------------- |
| 1 (default) | (untagged)     | -              | -           | 스위치 기본값. 사용하지 않지만 trunk 통과는 허용.   |
| 10          | Public DMZ     | 172.16.21.0/24 | 172.16.21.1 | 외부 노출 후보. 현재 미사용 (확장 여지).            |
| 20          | DMZ / 외부     | 172.16.22.0/24 | 172.16.22.1 | MetalLB 후보 대역이었으나 ARP 함정으로 30으로 통일. |
| 30          | Internal (K8s) | 172.16.23.0/24 | 172.16.23.1 | K8s 노드 6대 + MetalLB pool (172.16.23.100~150)     |
| 40          | Management     | 172.16.24.0/24 | 172.16.24.1 | Bastion, 관리 인터페이스                            |
| 99          | SYNC           | 10.10.99.0/24  | -           | pfsync HA 동기화 전용                               |

#### Ceph 10G

| 항목       | 값            | 근거                                                                   |
| ---------- | ------------- | ---------------------------------------------------------------------- |
| CIDR       | 10.10.10.0/24 | RFC1918 사설 대역, 외부와 격리                                         |
| MTU        | 9000 (Jumbo)  | Ceph IO에서 패킷당 데이터 ↑, CPU 부담 ↓ (6배 효율)                     |
| 게이트웨이 | 없음          | 같은 L2 안에서 직접 통신, 라우팅 불필요                                |
| 토폴로지   | Spine-Leaf    | East-West (Ceph 노드 ↔ K8s 노드 + Ceph 노드 ↔ Ceph 노드) 트래픽 최적화 |

#### CARP 설정

| 항목             | 값         | 근거                                      |
| ---------------- | ---------- | ----------------------------------------- |
| Skew (MASTER)    | 0          | 최고 우선순위, 살아있을 땐 항상 MASTER    |
| Skew (BACKUP)    | 100        | 충분히 낮은 우선순위, MASTER 다운 시 인계 |
| Advertise base   | 1          | 1초 간격 multicast (기본값)               |
| 페일오버 timeout | 3초        | 3 × advertise base = 3초 미수신 시 인계   |
| Multicast addr   | 224.0.0.18 | CARP 표준                                 |
| pfsync MTU       | 1500       | 단일 망 안이라 jumbo 불필요               |

#### 방화벽 룰 (요약)

| Source         | Destination   | Action               | 근거                         |
| -------------- | ------------- | -------------------- | ---------------------------- |
| VLAN 40 (Mgmt) | 모든 VLAN     | Pass                 | 관리망은 어디든 접근         |
| VLAN 30 (K8s)  | VLAN 30 내부  | Pass                 | K8s 내부 통신                |
| VLAN 30        | VLAN 20 (DMZ) | Pass                 | DMZ 서버 호출                |
| VLAN 30        | VLAN 40       | Pass (특정 포트)     | bastion에 응답               |
| VLAN 30        | Internet      | Pass                 | apt update 등                |
| VLAN 20        | VLAN 30       | Block                | DMZ → Internal 차단 (방향성) |
| Any            | Any           | Block (Default deny) | 명시적 허용 외 차단          |

### 4.3 다른 컴포넌트와의 연결

```
[K8s 노드 cloud-init 설정]
   ip_config 1: 172.16.23.10/24 + gateway 172.16.23.1   ← VLAN 30, pfSense CARP VIP가 gateway
   ip_config 2: 10.10.10.110/24 (no gateway)            ← Ceph 10G, 같은 L2

[Terraform variables.tf:138]
   variable "internal_gateway" {
     default = "172.16.23.1"   # pfSense CARP VIP
   }

[K8s + MetalLB]
   IPAddressPool: 172.16.23.100-172.16.23.150   ← K8s 노드와 같은 VLAN 30 → ARP 응답 OK

[Ceph CSI]
   monitor IPs: 10.10.10.12 외 (10G 망)
   K8s 노드의 eth1으로 직접 통신 → Pod 데이터망과 분리, IO 폭주 시에도 K8s API 안전
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 Proxmox 호스트 네트워크 (kosa1)

파일: `[kosa1]:/etc/network/interfaces`

```bash
auto lo
iface lo inet loopback

#################################
# 1. 관리망 + 업링크 (vmbr0, VLAN-aware)
#################################
iface eno1 inet manual                  # 물리 NIC, IP 없음

auto vmbr0
iface vmbr0 inet static
    address 192.168.21.2/24
    gateway 192.168.21.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes               # ★ VLAN-aware 활성 (핵심)
    bridge-vids 1-4094                  # ★ 모든 VLAN 허용 (trunk)
    up bridge vlan add vid 2-4094 dev vmbr0 self

#################################
# 2. 10GbE Ceph 직결망 (vmbr1)
#################################
iface enp1s0f0 inet manual
    mtu 9000                            # ★ 물리 NIC MTU 9000

auto vmbr1
iface vmbr1 inet static
    address 10.10.10.31/24              # kosa1=.31, kosa2=.32 등 (Proxmox host)
    bridge-ports enp1s0f0
    bridge-stp off
    bridge-fd 0
    mtu 9000                            # ★ 브리지도 MTU 9000
```

**줄별 설명**:

- `bridge-vlan-aware yes`: 브리지가 802.1Q 태그를 처리하도록. 이게 없으면 VLAN 동작 안 함.
- `bridge-vids 1-4094`: 모든 VLAN을 trunk로 허용. 보안 강화하려면 사용 VLAN만 명시.
- `mtu 9000`: Ceph 트래픽 jumbo frame. 양쪽 (물리 NIC + 브리지) 모두 일치해야 함.
- `gateway`가 vmbr0에만 있고 vmbr1엔 없음: vmbr1은 같은 L2 안에서 통신, 라우팅 불필요.

#### ⚠️ 절대 만들면 안 되는 것

```bash
# 이런 거 만들면 VHID 10 split-brain 재발
auto eno1.10
iface eno1.10 inet manual
    vlan-raw-device eno1
```

**왜?** Linux 커널은 `eno1.10` 같은 VLAN 서브인터페이스가 있으면 VLAN 10 프레임을 그쪽으로 demux.
이게 별도 브리지에 연결되면 pfSense VM의 LAN 트렁크와 분리됨. VLAN-aware 브리지를 쓰면 **이런
서브인터페이스를 호스트 레벨에서 절대 만들지 말 것**.

### 5.2 pfSense VM NIC 설정

```bash
# kosa1 (VMID 101, MASTER)
[kosa1]# qm set 101 -net0 virtio=BC:24:11:0C:87:26,bridge=vmbr0,firewall=0
[kosa1]# qm set 101 -net1 virtio=BC:24:11:EC:59:68,bridge=vmbr0,firewall=0
[kosa1]# qm set 101 -net2 virtio=BC:24:11:09:4C:30,bridge=vmbr0,tag=99
```

**줄별 설명**:

- `net0` (WAN): vmbr0 trunk에 연결, **태그 없음** = WAN(VLAN 1, untagged) 통과
- `net1` (LAN trunk): vmbr0 trunk에 연결, **태그 없음** = 모든 VLAN 통과 (pfSense 내부에서 VLAN
  분기)
- `net2` (SYNC): `tag=99` = Proxmox에서 VLAN 99 access 포트처럼 동작 → pfSense에 들어갈 땐 untagged
- `firewall=0` 필수: Proxmox 측 방화벽 비활성화. 이게 1이면 fwbr/fwln 추가 브리지 생성 → CARP 가상
  MAC이 여러 브리지에 학습되며 **MAC flapping → split-brain**.

### 5.3 Terraform K8s 노드 (dual-NIC)

파일: `/Users/sangjjang/kosa_infra_project/terraform/modules/vm/main.tf`

`main.tf:80-102` 재인용:

```hcl
# Primary NIC (VLAN 30 or 40)
network_device {
  bridge   = var.bridge      # "vmbr0"
  vlan_id  = var.vlan_tag    # 30 (K8s) or 40 (Bastion)
  model    = "virtio"
  firewall = false           # ★ Proxmox fw 끔
}

# Secondary NIC (Ceph 10G) - dynamic
dynamic "network_device" {
  for_each = var.ceph_bridge != "" ? [1] : []
  content {
    bridge   = var.ceph_bridge   # "vmbr1"
    model    = "virtio"
    firewall = false
    mtu      = var.ceph_mtu      # ★ 9000 (jumbo)
  }
}
```

`main.tf:116-133` (Cloud-init IP):

```hcl
# 1st = primary NIC (VLAN 30, gateway 172.16.23.1)
ip_config {
  ipv4 {
    address = var.ip_address    # "172.16.23.10/24"
    gateway = var.gateway       # "172.16.23.1" (pfSense CARP VIP)
  }
}

# 2nd = Ceph NIC (gateway 없음 - 같은 L2 직접 통신)
dynamic "ip_config" {
  for_each = var.ceph_ip != "" ? [1] : []
  content {
    ipv4 {
      address = var.ceph_ip     # "10.10.10.110/24"
    }
  }
}
```

### 5.4 Terraform 변수 정의

파일: `/Users/sangjjang/kosa_infra_project/terraform/onprem/variables.tf`

`variables.tf:93-152` 발췌:

```hcl
variable "bridge_lan" {
  description = "VM이 붙을 LAN 브리지 (VLAN-aware vmbr0)"
  default     = "vmbr0"
}

variable "bridge_ceph" {
  description = "Ceph 10G 패브릭 브리지 (Proxmox vmbr1)"
  default     = "vmbr1"
}

variable "internal_vlan_tag" {
  description = "K8s 노드용 VLAN (Internal = VLAN 30)"
  default     = 30
}

variable "mgmt_vlan_tag" {
  description = "관리망 VLAN (Bastion = VLAN 40)"
  default     = 40
}

variable "internal_gateway" {
  description = "Internal VLAN 게이트웨이 VIP (pfSense CARP)"
  default     = "172.16.23.1"      # ★ pfSense CARP VIP
}

variable "mgmt_gateway" {
  description = "관리망 VLAN 게이트웨이 VIP"
  default     = "172.16.24.1"      # ★ pfSense CARP VIP
}
```

**왜 게이트웨이가 pfSense CARP VIP?**

- pfSense-1 또는 pfSense-2 중 어느 것이 MASTER인지 K8s 노드는 모름
- 가상 IP 172.16.23.1로 보내면 ARP로 현재 MASTER의 가상 MAC을 받아 통신
- 페일오버 시 VIP는 그대로, MASTER만 바뀜 → K8s 노드는 변경 인지 불필요

### 5.5 관리형 스위치 VLAN 설정

```
| Port | 연결 대상 | 모드 | VLAN |
|---|---|---|---|
| 1 | kosa1 Proxmox | Trunk | Tagged 10,20,30,40,99 / Untagged 1 |
| 2 | kosa2 Proxmox | Trunk | 동일 |
| 3 | kosa3 Proxmox | Trunk | Tagged 10,20,30,40 |
| 4 | kosa4 Proxmox | Trunk | Tagged 10,20,30,40 |
| 5 | 관리 노트북 | Access | VLAN 40 (PVID 40, Untagged) |
| Uplink | Omada Router | Untagged VLAN 1 |
```

**왜 kosa3/kosa4는 VLAN 99 없음?** SYNC(VLAN 99)는 pfSense가 있는 kosa1/kosa2 사이만 동작. 다른
노드는 받을 필요 없음.

**왜 노트북은 Access 모드?** 노트북 NIC는 802.1Q 태그를 처리 못 함. Access면 untagged 패킷을 PVID
40으로 자동 마킹 → VLAN 40 정상 합류.

---

## 6. 실행 + 결과

### 6.1 CARP 동작 확인

```bash
[pfSense-1 CLI]: pfctl -s state | grep carp
```

기대 출력 (MASTER 측):

```
carp 172.16.23.1 - 224.0.0.18  MULTIPLE:SINGLE
```

`MULTIPLE:SINGLE` = MASTER 상태. BACKUP은 `SINGLE:MULTIPLE`.

### 6.2 게이트웨이 ping (4 VLAN)

```bash
[노트북]$ for vlan in 21 22 23 24; do
  ping -c 1 -W 1 172.16.${vlan}.1 >/dev/null && echo "VLAN ${vlan} OK" || echo "VLAN ${vlan} FAIL"
done
```

기대:

```
VLAN 21 OK
VLAN 22 OK
VLAN 23 OK
VLAN 24 OK
```

### 6.3 페일오버 테스트

```bash
# pfSense-1을 다운시킴
[kosa1]# qm shutdown 101

# 즉시 다른 터미널에서 ping 지속
[노트북]$ ping 172.16.23.1
# 기대: 1~3개 패킷 drop 후 자동 복구 (BACKUP이 MASTER로 승격)
```

```bash
# pfSense-2 CARP 상태 변화 확인
[pfSense-2 CLI]: pfctl -s state | grep carp
# MULTIPLE:SINGLE 으로 바뀌어 있어야 (BACKUP → MASTER 승격)
```

### 6.4 K8s 노드 Dual-NIC 확인

```bash
[k8s-cp1]$ ip addr show
```

기대 (요약):

```
2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 172.16.23.10/24 brd 172.16.23.255 scope global ens18

3: ens19: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000
    inet 10.10.10.110/24 brd 10.10.10.255 scope global ens19
```

- ens18 MTU 1500 + 172.16.23.10 = VLAN 30 정상
- ens19 MTU 9000 + 10.10.10.110 = Ceph 10G 정상

```bash
[k8s-cp1]$ ip route show
```

기대:

```
default via 172.16.23.1 dev ens18      ← pfSense CARP VIP
10.10.10.0/24 dev ens19 scope link     ← Ceph L2 직접
172.16.23.0/24 dev ens18 scope link
```

### 6.5 Jumbo Frame 검증

```bash
[k8s-cp1]$ ping -M do -s 8972 10.10.10.12
```

`-M do` = Don't Fragment, `-s 8972` = 페이로드 8972 (총 9000 with headers).

기대: 정상 응답 (loss 0%).

만약 `Frag needed and DF set` 에러 → MTU 어디선가 1500. 경로상 모든 장비(Proxmox vmbr1 + 물리 NIC +
스위치 + Ceph 노드) 모두 9000이어야 함.

### 6.6 Ceph 클러스터 확인

```bash
[ceph-mon]# ceph -s
```

기대:

```
  cluster:
    health: HEALTH_OK
  services:
    mon: 3 daemons, quorum a,b,c
    osd: 6 osds: 6 up, 6 in
  data:
    pools: 2 pools, 64 pgs
```

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 함정 1: MetalLB External-IP가 도달 안 됨

**증상**: `kubectl get svc` 에 EXTERNAL-IP는 172.16.22.X로 할당됐는데, 그 IP로 접속이 안 됨.

**원인**: MetalLB IP pool을 **VLAN 20 (172.16.22.0/24)** 에 뒀는데, K8s 노드는 **VLAN 30
(172.16.23.0/24)** 에 있음. MetalLB L2 모드는 ARP로 외부 IP를 알리는데, K8s 노드는 VLAN 20에
인터페이스가 없어서 ARP 응답 자체가 불가능.

**해결**:

```bash
[bastion]$ kubectl -n metallb-system patch ipaddresspool kosa-pool \
  --type='merge' \
  -p '{"spec":{"addresses":["172.16.23.100-172.16.23.150"]}}'

# Service 토글 (재할당 강제)
[bastion]$ kubectl -n kosa-tickets annotate svc ticket-app \
  metallb.universe.tf/loadBalancerIPs- --overwrite
```

**★ 왜 이 함정이 발생하는가**:

- MetalLB L2 모드 동작: "외부 IP의 ARP 요청에 K8s 노드 중 한 명이 응답"
- 응답하려면 그 노드가 **외부 IP와 같은 L2(같은 VLAN)** 에 있어야 함
- VLAN 20에 IP를 주면 K8s 노드(VLAN 30)는 그 VLAN의 broadcast 도메인에 없음
- 해결: 같은 VLAN에 두거나 BGP 모드 사용 (BGP 모드는 라우터 설정 필요)

### 함정 2: VLAN 10에서만 pfSense HA split-brain (VHID 10이 안 됨)

**증상**: VLAN 20/30/40 페일오버는 OK인데 VLAN 10에서만 양쪽 다 MASTER가 됨.

**원인**: Proxmox 호스트에 옛 VLAN 서브인터페이스(`nic0.10`)와 옛 브리지(`vmbr0v10`)가 남아있었음.
Linux 커널이 VLAN 10 프레임을 그쪽으로 demux시키면서 pfSense VM의 LAN trunk와 분리. CARP advertise
패킷이 두 노드 간 도달 못 함.

**해결**:

```bash
[kosa1]# ip link delete eno1.10 2>/dev/null
[kosa1]# ip link delete vmbr0v10 2>/dev/null

# /etc/network/interfaces에서 관련 entry 모두 삭제
[kosa1]# systemctl restart networking
```

**★ 왜 이 함정이 발생하는가**:

- Linux 브리지를 VLAN-aware로 설정해도, **그 외 인터페이스가 VLAN 처리 권한을 가져가면 우선됨**
- `nic0.10` 인터페이스는 VLAN 10 프레임을 자기 쪽으로 가져가 별도 처리
- 그러면 vmbr0의 VLAN 10 처리는 무효화됨
- **VLAN-aware 브리지 사용 시 절대 VLAN 서브인터페이스를 호스트 레벨에서 만들면 안 됨**

### 함정 3: XMLRPC Sync로 Skew까지 복사 → split-brain

**증상**: HA 구성 후 일주일 정도 정상 동작하다 양쪽 다 MASTER가 됨.

**원인**: pfSense의 XMLRPC Configuration Sync에서 "Virtual IPs" 항목을 sync 대상에 포함시킴.
MASTER의 Skew=0이 BACKUP에 복제되어 둘 다 Skew=0 → 같은 우선순위 → 둘 다 MASTER 주장.

**해결**:

- pfSense Web UI → System → High Avail Sync → "Synchronize Virtual IPs" **체크 해제**
- 또는 XMLRPC Sync 자체를 끄고 VIP는 양쪽 수동 관리

**★ 왜 이 함정이 발생하는가**:

- XMLRPC는 "설정 파일 자체"를 복제하므로 Skew도 같이 따라감
- CARP는 같은 VHID 그룹 안에서 **Skew가 같으면 MAC 주소 비교**로 결정
- MAC도 같아질 수 있어서 (가상 MAC) 양쪽 모두 자기가 MASTER라고 판단
- 결과: 두 노드가 같은 VIP에 응답 → 스위치 MAC 학습 flapping → 패킷 drop 폭증

### 함정 4: ICMP/ping은 되는데 TCP 끊김 (비대칭 라우팅)

**증상**: K8s 노드에서 ping은 잘 되는데 일부 TCP 연결이 가끔 끊김. 특히 외부 API 호출.

**원인**: 일부 트래픽이 pfSense-1로 나가고 응답은 pfSense-2로 돌아옴 (비대칭 경로). pfSense의
stateful 방화벽은 "outbound 상태를 본 쪽이 inbound도 처리"하는데, 다른 노드가 받으면 state 없음 →
drop.

**해결**:

- pfsync를 정상 동작시켜 state table 동기화 (이미 되어 있는데 multicast 누락 시 끊김)
- pfSense의 `System → Advanced → Firewall/NAT → State Killing on Gateway Down`
- 또는 outbound NAT 규칙을 일관성 있게 설정

**★ 왜 이 함정이 발생하는가**:

- CARP MASTER 한 대만 active라도, ARP 캐시 차이로 일부 패킷이 BACKUP쪽으로 갈 수 있음
- Stateful 방화벽 + 비대칭 경로 = "본 적 없는 응답"으로 인식 → drop
- pfsync로 state를 양쪽 동기화하면 이 문제 사라짐
- pfsync MTU/네트워크 문제 있으면 또 함정

### 함정 5: MTU 9000인데 일부 Ceph IO 느림

**증상**: Ceph 쓰기 IO가 들쭉날쭉. 같은 K8s 노드에서도 어떤 Pod는 빠르고 어떤 Pod는 느림.

**원인**: 경로상 한 장비라도 MTU 1500이면 ICMP "Frag needed"가 돌아가야 하는데, 방화벽이 그걸
차단하면 silently drop. 또는 K8s Pod 내부 인터페이스(veth)는 1500이라 외부와 mismatch.

**해결**:

```bash
# 모든 경로의 MTU 확인
[k8s-cp1]$ ip link show ens19 | grep mtu       # 9000 기대
[k8s-cp1]$ ping -M do -s 8972 10.10.10.12      # OK 기대

# Pod 내부 MTU 확인 (Calico/Flannel은 1500이 보통)
[k8s-cp1]$ kubectl exec -it <pod> -- ip link
```

K8s Pod 내부 트래픽은 1500 유지하되, Ceph IO는 **K8s 노드 → Ceph 노드** 구간만 9000.

**★ 왜 이 함정이 발생하는가**:

- Path MTU Discovery (PMTUD)는 ICMP "Frag needed" 메시지에 의존
- 방화벽/스위치가 ICMP 일부를 차단하면 PMTUD 깨짐 → TCP가 큰 패킷 보내고 답 없음 → retransmit 폭증
- 모든 장비 MTU 일치 + ICMP 허용 필수
- 의외로 일부 SFP+ 모듈은 9000 미지원 → 펌웨어 확인 필요

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- **pfSense Documentation**: https://docs.netgate.com/pfsense/en/latest/
- **CARP**: https://docs.netgate.com/pfsense/en/latest/highavailability/index.html
- **VLAN (Cisco)**: https://www.cisco.com/c/en/us/support/docs/lan-switching/8021q/17056-741-4.html
- **Ceph Network**: https://docs.ceph.com/en/latest/rados/configuration/network-config-ref/

### 추천 학습 자료

- **Lawrence Systems YouTube** — pfSense 실전 튜토리얼
- **Network Chuck** — VLAN/네트워크 입문
- **RFC 5798 (VRRP v3)** — CARP의 사촌 격, 동작 원리 동일

### 우리 프로젝트 내부 문서

- `pfSense_HA_Setup_Guide.md` — 실제 구축 단계 (이미 완료된 버전)
- `terraform/modules/vm/main.tf` — VM dual-NIC 코드
- `terraform/onprem/variables.tf` — VLAN/CIDR/gateway 변수
- `docs/learning/01_네트워크_VLAN_pfSense.md` — 학습 자료 (더 기초)

### 다음 챕터 미리보기

다음 챕터(예정 `04-k8s-bootstrap.md`)에서는 이 네트워크 위에 **K8s 클러스터를 부트스트랩**하는
과정을 다룹니다. kubeadm + Ansible로 6 노드(CP 3 + Worker 3) 구성, Calico CNI 설치, MetalLB(이
챕터에서 함정 1로 본 그 컴포넌트) 설치, 그리고 etcd quorum이 어떻게 동작하는지 봐요.

---

> **이 챕터 핵심 메시지**: pfSense HA(CARP) + VLAN 분리 + Dual-NIC + Spine-Leaf 패브릭은
> **중견기업/데이터센터 네트워크 표준**이에요. 우리는 한정된 하드웨어(Proxmox 4대)에서 이 표준을
> 거의 그대로 구현했고, 함정 5가지(MetalLB ARP, VLAN 잔재, XMLRPC Skew, 비대칭 라우팅, MTU 일치)를
> 거치며 실전 학습했어요. 게이트웨이가 죽어도 서비스가 살아있는 인프라가 어떻게 만들어지는지 직접
> 보여줄 수 있는 구성입니다.
