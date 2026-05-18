# 14. AWS 하이브리드 (VPC + Site-to-Site VPN)

> **이 챕터의 목적**
> 온프레미스 KOSA 인프라를 AWS와 **사설망처럼 연결**하는 단계.
> Phase 1(AWS 인프라 셋업)과 Phase 2(IPsec VPN 연결)를 다루며,
> Phase 3 이후(RDS Replica, EKS Karpenter, Lambda burst 트리거)는 별도 챕터로 분리 예정.

---

## 📌 핵심 (시간 없으면 이것만)

- **목표**: 온프레 사설망(172.16.0.0/12) ↔ AWS VPC(10.20.0.0/16)를 IPsec 터널로 묶어 **같은 사설망처럼** 통신
- **AWS 측**: VPC + Public/Private Subnet × 2 AZ + NAT GW × 2 + NLB + EC2(HAProxy) + VGW + VPN Connection
- **온프레 측**: pfSense에 IPsec 터널 정의 + **Outbound NAT bypass 룰** (이게 핵심)
- **결과**: bastion(172.16.24.10) ↔ EC2(10.20.10.121) 양방향 ping 6ms 성공
- **다음**: 이 VPN 위에 RDS Read Replica, EKS Burst를 얹는 게 Phase 3+

---

## 1. 왜 하이브리드인가

### 시나리오: T-30 오픈런 (티켓팅)

평소에는 온프레만으로 충분하지만, **티켓 오픈 시점(T-30분~T+10분)** 같은 일회성 폭발 트래픽에 온프레만으로는 대응이 어렵습니다:

- **온프레 K8s 워커 4대**: 정해진 CPU/메모리. 갑자기 10배 부하 오면 OOM/CPU saturation.
- **온프레 추가 증설**: 물리 하드웨어 구입 + 설치 + 셋업 → 수일~수주. 일회성 부하엔 비효율.

이때 **AWS를 "탄력적 외부 캐파"로** 활용:

- 평소: AWS 쪽 노드 0개 (비용 0)
- 부하 폭증 임박: CloudWatch + Lambda가 EKS Karpenter trigger → 노드 자동 생성 → ArgoCD가 같은 앱 배포 → ALB/NLB가 일부 트래픽 라우팅
- 폭발 종료: Karpenter가 노드 축소 → 다시 비용 0

### 💡 왜? (대안 비교)

| 옵션 | 장점 | 단점 |
|---|---|---|
| **온프레 over-provision** | 가장 단순, 외부 의존 X | 평시 자원 낭비, 캐파 한계 명확 |
| **퍼블릭 클라우드 only** | scale 자유, 운영 단순 | 비용 ↑↑, 데이터 주권/규제 |
| **하이브리드 (우리)** | 평시 비용 ↓, 폭발 시 scale, 데이터는 온프레 | 네트워크 복잡, VPN 운영 비용 |

> **우리 환경에 맞춤**: 온프레 6TB Ceph + 4 Proxmox는 이미 매몰비용. AWS는 burst용으로만 사용 → 평소 50만원 이내 가능.

---

## 2. 전체 토폴로지

```
온프레미스 (KOSA Team2)                       AWS (ap-northeast-2)
─────────────────────────────                 ──────────────────────────────
[Internet] ─ ISP ─ TP-Link ER605 ─ pfSense    Public Subnet (2a, 2c)
                  (NAT-T 통과)    │           ├─ NAT GW × 2
                                  │           ├─ EC2 HAProxy × 2 (옵션)
                  ┌───────────────┘           └─ ALB/NLB (Public)
                  │ IPsec VPN
                  │ (UDP 500/4500)            Private Subnet (2a, 2c)
                  │                           ├─ EC2 HAProxy × 2 ◄─── NLB target
                  │                           ├─ EKS nodes (Karpenter, 향후)
                  ↓                           └─ RDS (향후)
            ┌──────────────┐                      │
            │  VGW (AWS)   │ ◄── VPN Connection──┤
            │  vgw-xxxxx   │     (Static routes)
            └──────────────┘                      │
                                                  Route Table에 propagation:
                                                  172.16.0.0/12 → vgw

[Internal Network 172.16.0.0/12]            [AWS VPC 10.20.0.0/16]
  bastion 172.16.24.10  ─────VPN 터널─────►  EC2 10.20.10.121
  K8s Pods 192.168.x.x                       NLB / RDS / EKS
```

### VLAN/Subnet 매핑

| 위치 | CIDR | 용도 |
|---|---|---|
| **온프레** | | |
| VLAN 10 | 172.16.21.0/24 | 관리 (Proxmox UI 등) |
| VLAN 20 | 172.16.22.0/24 | DMZ (Edge HAProxy) |
| VLAN 30 | 172.16.23.0/24 | Internal (K8s 노드, lb-1/2) |
| VLAN 40 | 172.16.24.0/24 | Guest (bastion, 운영용) |
| **AWS** | | |
| VPC | 10.20.0.0/16 | 전체 |
| Public 2a | 10.20.1.0/24 | NAT GW, ALB/NLB |
| Public 2c | 10.20.2.0/24 | NAT GW, ALB/NLB |
| Private 2a | 10.20.10.0/24 | EC2 HAProxy, EKS, RDS |
| Private 2c | 10.20.20.0/24 | EC2 HAProxy, EKS, RDS |

### 💡 왜 사설 IP를 안 겹치게 설계했나
온프레 172.16.x.x, AWS 10.20.x.x — 겹치면 VPN으로 묶었을 때 라우팅 충돌. 새 환경 설계할 땐 **양쪽 CIDR이 절대 겹치지 않도록 미리 RFC1918 영역을 쪼개두는 게 정석**.

---

## 3. Phase 1: AWS 인프라 셋업 (콘솔)

### 3.1 VPC 생성

AWS Console → VPC → "Create VPC" → "VPC and more"

- Name: `kosa-tickets-vpc`
- IPv4 CIDR: `10.20.0.0/16`
- AZ: 2 (ap-northeast-2a, ap-northeast-2c)
- Public subnet: 2 (`10.20.1.0/24`, `10.20.2.0/24`)
- Private subnet: 2 (`10.20.10.0/24`, `10.20.20.0/24`)
- NAT gateway: **1 per AZ** (HA, 단 비용 2배)
- VPC endpoints: S3 Gateway (무료, 권장)

### 💡 왜 NAT GW를 AZ당 1개?
AZ당 1개면 한 AZ 장애에도 다른 AZ가 살아있음. 1개만 두면 SPoF + cross-AZ 트래픽 비용. 비용 절감 vs 가용성 트레이드오프 — 데모면 1개도 OK.

### 3.2 Security Group

EC2 / NLB / RDS / EKS 각각 분리하는 게 정석. 데모 단계에서는 단순화:

| SG | Inbound 허용 | 용도 |
|---|---|---|
| `kosa-sg-public` | 80/443 from 0.0.0.0/0, 22 from 본인 IP | ALB/NLB |
| `kosa-sg-private` | 80/443 from kosa-sg-public, ICMP from 172.16.0.0/12 | EC2/RDS |
| `kosa-sg-vpn` | ICMP/all from 172.16.0.0/12 | VPN 도달 대상 |

### 3.3 EC2 (HAProxy) 생성

- AMI: Ubuntu 22.04 LTS
- 인스턴스 타입: t3.micro (데모) / t3.medium 이상 (운영)
- **반드시 Private Subnet에 배치** (Public IP 없음)
- IAM Role: `AmazonSSMManagedInstanceCore` (SSH 키 없이 SSM 접속용)
- Security Group: `kosa-sg-private`
- User Data:
  ```bash
  #!/bin/bash
  apt update && apt install -y haproxy
  cat > /etc/haproxy/haproxy.cfg << 'EOF'
  frontend ft_http
    bind *:80
    default_backend bk_health

  backend bk_health
    server local 127.0.0.1:8080
  EOF
  python3 -m http.server 8080 &
  systemctl enable --now haproxy
  ```

### ⚠️ 함정: SSM 접속 안 됨
SSM Session Manager로 접속하려면:
1. EC2에 IAM Role 부여 (`AmazonSSMManagedInstanceCore`)
2. Private Subnet에서 **NAT GW를 통해 ssm.amazonaws.com 도달 가능해야** 함
3. Public Subnet에 EC2를 두면서 Public IP를 안 주면 SSM 못 함 (NAT 경로 없음)

→ **권장**: 처음부터 Private Subnet + NAT GW. Public Subnet + Public IP는 보안상 권장 X.

### 3.4 NLB 생성

- Type: Network Load Balancer
- Scheme: Internet-facing (외부 노출)
- Subnet: 2 AZ의 Public Subnet 선택
- Listener: TCP/80, TCP/443
- Target group: Instance type, healthcheck `/healthz` 또는 TCP/80
- Target: 위에서 만든 EC2 2대

### 검증

```bash
# 본인 노트북에서
curl -I http://kosa-tickets-nlb-xxx.elb.ap-northeast-2.amazonaws.com/healthz
# HTTP 200 OK 나오면 Phase 1 끝
```

---

## 4. Phase 2: Site-to-Site VPN

### 4.1 개념 정리 (꼭 알아야 하는 것)

| 용어 | 의미 | 비유 |
|---|---|---|
| **IPsec** | 사설망끼리 인터넷 위에서 암호 터널 만드는 프로토콜 | 우편물을 잠긴 가방에 넣어 보냄 |
| **IKE (Internet Key Exchange)** | 양쪽이 암호 키 협상하는 단계 (Phase 1) | "우리 어떤 잠금 장치 쓸까?" 합의 |
| **ESP (Encapsulating Security Payload)** | 실제 데이터 암호화/전송 (Phase 2) | 합의된 방식으로 실제 가방을 보냄 |
| **CGW (Customer Gateway)** | AWS 입장에서 "온프레 라우터" 표현 | 우체국에서 보는 "받는 분 주소" |
| **VGW (Virtual Private Gateway)** | AWS VPC에 붙는 VPN 종단점 | 우체국 |
| **NAT-T (NAT Traversal)** | 라우터 뒤에서 IPsec 쓸 때 UDP 4500으로 wrap | 익명 우편함 통해 우편 발송 |
| **Pre-shared Key (PSK)** | 양쪽이 미리 공유하는 비밀 키 | 합의된 비밀 암호 |
| **Traffic Selector** | "이 터널은 어떤 src→dst만 받는다" 규칙 | 우체국이 받는 우편 종류 제한 |

### 💡 왜 IPsec? 다른 옵션은?

| 옵션 | 장점 | 단점 |
|---|---|---|
| **IPsec Site-to-Site** (우리) | 표준, AWS 네이티브 지원, 무료 (월 ~$36 + 데이터) | 설정 복잡, NAT 뒤일 때 NAT-T 필요 |
| **AWS Direct Connect** | 전용 회선, 안정성 ↑↑, 저지연 | 월 수백만원, 물리 회선 필요 |
| **AWS Client VPN** | OpenVPN 기반, 개별 사용자 접속 | Site-to-Site 부적합 |
| **Transit Gateway + VPN** | 다중 VPC/온프레 한 곳에서 관리 | TGW 시간당 비용 추가 |
| **자가 구축 WireGuard** | 매우 단순, 빠름 | AWS 매니지드 X (직접 운영) |

### 4.2 토폴로지 (NAT 뒤의 pfSense)

```
[온프레 LAN]
  pfSense WAN: 192.168.21.110 (사설 IP, ISP가 NAT)
       │
       ↓ NAT (TP-Link ER605)
[ISP/인터넷]
  공인 IP: 125.131.208.229 (TP-Link의 외부 IP)
       │
       ↓ UDP 500 (IKE) + UDP 4500 (NAT-T)
[AWS]
  VGW 공인 IP: 43.200.200.229 (터널 1)
            : 54.116.133.94  (터널 2)
```

### ⚠️ 핵심 함정: NAT-T 필수
pfSense가 직접 공인 IP를 가졌다면 UDP 500만 쓰면 되지만, **우리처럼 NAT 뒤에 있으면 UDP 4500이 필수**. ER605에서 UDP 4500 포워딩이 자동으로 처리됨 (대부분 SMB 라우터는 NAT-T passthrough 지원).

### 4.3 AWS 측 설정 단계

#### 4.3.1 CGW (Customer Gateway) 생성

VPC → Customer Gateways → Create

- Name: `kosa-cgw-pfsense`
- BGP ASN: `65000` (Static 라우팅이면 아무 숫자 OK)
- IP address: **TP-Link ER605의 공인 IP** (예: `125.131.208.229`) ← pfSense WAN IP 아님!
- Certificate: 없음
- Device: pfSense (참고용)

### 💡 왜 pfSense WAN IP가 아니고 TP-Link 공인 IP?
AWS 입장에서 IKE 패킷의 source IP는 **NAT-T를 통과한 최외곽 IP** — 즉 TP-Link의 공인 IP. pfSense WAN(192.168.21.110)을 적으면 절대 매칭 안 됨.

확인 방법: 노트북에서 `curl ifconfig.me` 또는 pfSense에서 외부 사이트 접속 시 보이는 IP.

#### 4.3.2 VGW (Virtual Private Gateway) 생성 + Attach

VPC → Virtual Private Gateways → Create

- Name: `kosa-vgw`
- ASN: Amazon default (64512)
- 생성 후 → Actions → Attach to VPC → `kosa-tickets-vpc`

#### 4.3.3 VPN Connection 생성

VPC → Site-to-Site VPN Connections → Create

- Name: `kosa-vpn-pfsense`
- Target gateway: VGW (위에서 만든)
- Customer Gateway: 위에서 만든 CGW
- Routing options: **Static** (BGP는 양쪽 모두 BGP 지원해야)
- Static IP prefixes: `172.16.0.0/12` (온프레 전체)
- Local IPv4 CIDR: `0.0.0.0/0` (또는 정확히 `172.16.0.0/12`)
- Remote IPv4 CIDR: `0.0.0.0/0` (또는 정확히 `10.20.0.0/16`)
- Tunnel options: 양쪽 터널 PSK를 직접 지정 (혹은 자동 생성)

#### 4.3.4 Configuration 다운로드

생성 후 → "Download Configuration" → Vendor: pfSense → 다운로드.

여기에 양쪽 터널의 공인 IP, PSK, IKE/IPsec 파라미터가 다 들어있음. pfSense 설정 시 이 파일을 보면서 입력.

#### 4.3.5 Route Propagation 활성화 ⭐ 꼭 해야 함

VPC → Route Tables → Private Subnet에 연결된 RT 선택 → Route propagation 탭 → Edit → VGW 체크 → Save

**이걸 안 하면 EC2가 ping 받아도 답장을 못 보냄** (route table에 `172.16.0.0/12 → vgw` 없음).

### 4.4 pfSense 측 설정 단계

#### 4.4.1 IPsec Phase 1 (터널당 1개씩, 총 2개)

VPN → IPsec → Tunnels → Add P1

- Key Exchange version: **IKEv1** (AWS Static VPN 기본)
- Internet Protocol: IPv4
- Interface: WAN
- Remote Gateway: 터널 1의 AWS 공인 IP (예: `43.200.200.229`)
- Authentication Method: Mutual PSK
- My identifier: My IP address
- Peer identifier: Peer IP address
- Pre-Shared Key: AWS configuration 다운로드에서 복사
- Encryption: AES256, SHA1, DH group 2 (AWS 기본값과 일치)
- Lifetime: 28800 sec
- NAT Traversal: **Force** (NAT 뒤이므로 필수!)
- Dead Peer Detection: Enable, delay 10, retries 3

#### 4.4.2 IPsec Phase 2 (터널당 1개씩)

방금 만든 P1 옆 → "+ Show Phase 2 Entries" → Add P2

- Mode: Tunnel IPv4
- Local Network: `172.16.0.0/12`
- Remote Network: `10.20.0.0/16`
- Protocol: ESP
- Encryption: AES256
- Hash: SHA1
- PFS key group: 2
- Lifetime: 3600 sec

**터널 2도 동일하게**: Remote Gateway만 `54.116.133.94` (예시), PSK 다르게.

#### 4.4.3 Firewall 룰 (IPsec 인터페이스)

Firewall → Rules → IPsec → Add

- Action: Pass
- Interface: IPsec
- Protocol: any
- Source: `10.20.0.0/16` (AWS에서 오는 트래픽)
- Destination: any

### 4.4.4 ⭐ Outbound NAT Bypass ⭐ (이게 핵심 중의 핵심)

Firewall → NAT → Outbound

- Mode를 **Hybrid Outbound NAT** 로 변경 (자동 룰 유지하면서 수동 룰 추가 가능)
- Save → Apply
- **Mappings에 새 룰 추가, 반드시 가장 위로**:
  - Interface: WAN
  - Source: `172.16.0.0/12`
  - Destination: `10.20.0.0/16`
  - Translation: **No NAT** (체크박스)
  - Description: `Bypass NAT for AWS VPC via IPsec`

### 💡 이 룰이 왜 결정적인가
이 룰이 없으면 pfSense가 AWS로 가는 트래픽까지 src IP를 자기 WAN(192.168.21.110)로 바꿔서 IPsec 터널에 던집니다. AWS VGW는 traffic selector(`172.16.0.0/12`)에 안 맞는 src를 조용히 drop → 터널은 UP이지만 트래픽 흐름 X.

#### 4.4.5 Apply + 터널 시작

- Status → IPsec → 양쪽 터널 옆 "Connect P1 and P2s" 클릭 (pfSense는 NAT 뒤라 initiator 역할, 안 누르면 안 됨)
- 1-2분 후 양쪽 다 "ESTABLISHED" 보여야 함

### 4.5 검증

```bash
# bastion (172.16.24.10)에서
ping -c 5 10.20.10.121
# 5 packets transmitted, 5 received, 0% packet loss
# rtt ~6ms 면 성공
```

AWS Console에서:
- VPC → Site-to-Site VPN Connections → Tunnel details → 양쪽 다 "UP" 보여야

EC2 안에서 (SSM 접속):
```bash
ping -c 5 172.16.24.10
# 양방향 모두 OK여야 진짜 완성
```

---

## 5. 트러블슈팅 (실제 발생한 순서대로)

### 5.1 EC2 SSM 접속 안 됨 (Phase 1)

**증상**: EC2 콘솔에서 SSM Session Manager 아이콘이 회색, 접속 불가.

**원인**:
- IAM Role 누락
- Public Subnet에 두면서 Public IP 안 줌 → 인터넷 outbound 없음 → SSM agent가 ssm.amazonaws.com 도달 불가

**해결**:
1. EC2 종료 → 새로 생성하면서 Private Subnet 선택 + IAM Role `AmazonSSMManagedInstanceCore` 부여
2. Private Subnet의 Route Table에 `0.0.0.0/0 → NAT GW` 있는지 확인

### 5.2 NLB에 EC2 등록 안 됨

**증상**: Target group의 Health check가 "unhealthy".

**원인**: EC2 Security Group이 NLB(또는 그 source IP 범위)에서 오는 healthcheck를 막음.

**해결**: SG inbound에 `Source: NLB SG (또는 VPC CIDR 10.20.0.0/16)` 허용.

### 5.3 VPN 터널 한쪽만 UP

**증상**: AWS console에서 터널 1은 UP, 터널 2는 DOWN.

**원인**: pfSense에 P1/P2를 한 터널만 만듦. AWS는 항상 2개 터널 제공.

**해결**: pfSense에서 두 번째 P1/P2도 만들고 "Connect P1 and P2s" 클릭.

### 5.4 양쪽 다 UP인데 ping 안 됨 (가장 어려웠던 단계)

**증상**: AWS console에서 양쪽 터널 다 UP. 하지만 `ping 10.20.10.121` timeout.

**진단 순서**:

1. **AWS Route Propagation 확인**
   - Route Tables → Private Subnet RT → Routes 탭
   - `172.16.0.0/12 → vgw-xxx (propagated)` 있어야 함
   - 없으면 → Route propagation 탭 → VGW 활성화

2. **pfSense Outbound NAT 확인** ⭐
   - tcpdump on pfSense WAN 또는 IPsec 인터페이스
   - 패킷이 src=192.168.21.110으로 보이면 → NAT 되고 있음, bypass 룰 추가 필요
   - 패킷이 src=172.16.24.10으로 보이면 OK

3. **EC2 Security Group**
   - Inbound에 ICMP from 172.16.0.0/12 허용

4. **state table 비우기**
   - pfSense → Diagnostics → States → Reset states (또는 1분 기다리기)

### 5.5 "설정 다 고쳤는데 안 되다가 갑자기 됨"

**원인 후보 (시간 순)**:

| 대기 시간 | 진짜 원인 |
|---|---|
| 30~60초 | pfSense state table의 ICMP entry 만료 |
| 1~3분 | AWS Route Propagation 반영 |
| 5~10분 | IPsec SA rekey (잘못된 traffic selector로 협상된 게 재협상) |
| 즉시 됐는데 못 봄 | 다른 터미널/tcpdump 필터 오타 |

**즉시 해결법**:
- pfSense: Diagnostics → States → Reset states
- pfSense: Status → IPsec → Disconnect → Connect (SA 재협상)
- 새 터미널에서 ping 시도 (기존 conntrack 우회)

### 5.6 ER605에서 NAT-T 안 됨

**증상**: pfSense IPsec 로그에 "no NAT-T support" 또는 Phase 1 negotiation timeout.

**원인**: 일부 라우터는 NAT-T (UDP 4500) passthrough를 막거나 ALG 충돌.

**해결**:
- ER605 → Advanced → ALG → IPsec ALG **disable**
- ER605 → NAT → Port Forward로 UDP 500, 4500을 pfSense WAN IP로 명시적 포워딩 (안 해도 되는 경우 많지만 안 되면 시도)

---

## 6. 진단 명령어 cheat sheet

### pfSense에서

```bash
# IPsec 상태 (Shell 접속 후)
ipsec statusall

# 터널 트래픽 확인
tcpdump -i ipsec0 -n
tcpdump -i wan -n udp port 500 or port 4500

# state table 확인 (특정 dst)
pfctl -ss | grep 10.20

# state 강제 삭제
pfctl -F state
```

### Linux (bastion/EC2)에서

```bash
# Route 확인
ip route
# 172.16.x.x로 가는 라우트 있어야 (EC2 측), 10.20.x.x로 가는 라우트 있어야 (bastion 측)

# 패킷 흐름 추적
sudo tcpdump -i any -n host 10.20.10.121
sudo tcpdump -i any -n icmp

# MTU 확인 (IPsec은 패킷 크기 줄어드니까)
ping -c 5 -s 1400 -M do 10.20.10.121
# do = don't fragment. 깨지면 MTU 줄여야
```

### AWS 측

```bash
# CloudWatch Logs (VPN 흐름)
# Console: VPC → Site-to-Site VPN Connections → 해당 connection → "Tunnel Details" → "View Tunnel Activity"

# VPC Flow Logs (활성화돼있다면)
# Console: VPC → Flow logs → 필터로 srcaddr/dstaddr 검색
```

---

## 7. 비용 (월 예상)

| 자원 | 예상 비용 (USD/월) |
|---|---|
| VPN Connection | $36 (시간당 $0.05 × 720h) |
| Data Transfer (VPN out) | $0.09/GB (양방향 약 10GB 가정 → $0.9) |
| NAT Gateway × 2 | $64 (시간당 $0.045 × 720h × 2) |
| NAT Gateway 데이터 | $0.045/GB (10GB → $0.45) |
| EC2 t3.micro × 2 | $15 |
| NLB | $16 (시간당 $0.0225 × 720h) + LCU |
| **합계** | **약 $130 = 17만원** |

> 데모용으로는 NAT GW를 1개로 줄이고 (32 USD 절감), EC2를 stop해두면 더 줄일 수 있음. 50만원 예산 안에서 충분히 운영 가능.

---

## 8. 학습 포인트 / 면접 talking point

### Q. "왜 IPsec이고 왜 NAT-T가 필요했나?"
- IPsec은 인터넷 위에서 두 사설망을 마치 같은 LAN처럼 묶는 표준 프로토콜
- 우리 pfSense는 ISP NAT 뒤에 있어서 IKE의 source IP가 NAT으로 바뀜
- 그래서 UDP 500(평문 IKE) 대신 UDP 4500(NAT-T로 wrap된 IKE)을 써야 양쪽이 서로 인식 가능
- NAT-T는 "야 나 NAT 뒤야, 내 진짜 IP는 이거야" 같은 메타데이터를 추가로 교환

### Q. "왜 Outbound NAT bypass가 필요했나?"
- pfSense는 default로 모든 outbound 트래픽을 WAN IP로 source-NAT (사설→공인 변환)
- 하지만 IPsec 터널 안의 트래픽은 **원본 src IP가 유지되어야** AWS VGW의 traffic selector(172.16.0.0/12)에 매칭됨
- NAT가 되면 src=192.168.21.110이 되어 traffic selector에 안 맞아 drop
- 그래서 "AWS 대상 트래픽은 NAT 하지 마라" 예외 룰을 명시적으로 추가해야 함

### Q. "Route Propagation은 왜 따로 켜야 하나?"
- VPN Connection의 static route는 VGW에만 등록됨
- 실제 EC2의 트래픽을 결정하는 건 EC2가 있는 subnet의 route table
- 두 가지가 자동 연결 안 됨 — Route Table에 명시적으로 "VGW에서 광고되는 route를 받겠다" 설정 필요
- 비유: 본사에 회의 결과는 전달됐는데, 본사가 그걸 각 지점에 알리지 않으면 지점은 모름

### Q. "이 위에 뭘 얹을 거고 왜?"
- **Phase 3**: RDS Read Replica — 온프레 Percona의 read 부하 일부를 AWS로 (read scaling)
- **Phase 4**: EKS + Karpenter — burst compute (오픈런 시간에 노드 자동 생성)
- **Phase 4**: CloudWatch + Lambda → burst trigger
- **Phase 5**: WAF, Route 53 (운영 단계)

---

## 9. 다음 챕터 예고

이 챕터의 토대(VPC + VPN) 위에 Phase 3+를 구축하면 별도 챕터로 분리 예정:
- `15-aws-rds-replica.md`: 온프레 PXC binlog → AWS RDS Read Replica
- `16-aws-eks-burst.md`: EKS + Karpenter + CloudWatch trigger
- `17-aws-multicluster-argocd.md`: ArgoCD multi-cluster 등록 + App-of-Apps 확장

각 단계의 트러블슈팅도 발생하는 대로 해당 챕터에 누적.

---

## 부록 A. 우리가 실제로 구축한 자원 (lookup용)

| 자원 | ID / 값 |
|---|---|
| VPC | `vpc-03859601c1dd5b658` (10.20.0.0/16) |
| Public Subnet 2a | 10.20.1.0/24 |
| Public Subnet 2c | 10.20.2.0/24 |
| Private Subnet 2a | 10.20.10.0/24 |
| Private Subnet 2c | 10.20.20.0/24 |
| NAT GW 2a | `nat-06228d0a2634bda13` |
| NAT GW 2c | `nat-0639891e22679e62b` |
| EC2 (2a) | `i-05ad4f4a40f2c7103` (kosa-tickets-haproxy-1a) |
| EC2 (2c) | 10.20.10.121 |
| NLB | `kosa-tickets-nlb-091d28bb8f4ca020.elb.ap-northeast-2.amazonaws.com` |
| CGW | `cgw-0923e106392116cfc` (TP-Link 공인 IP: 125.131.208.229) |
| VGW | `vgw-0f14a420ce5d30261` |
| VPN Connection | `vpn-0906e8a06bb85a041` |
| Tunnel 1 | 43.200.200.229 |
| Tunnel 2 | 54.116.133.94 |

---

## 부록 B. 참고 자료

- AWS Site-to-Site VPN User Guide: https://docs.aws.amazon.com/vpn/latest/s2svpn/
- pfSense IPsec Configuration: https://docs.netgate.com/pfsense/en/latest/vpn/ipsec/
- AWS VPN troubleshooting: https://docs.aws.amazon.com/vpn/latest/s2svpn/Tunnel-Troubleshooting.html
- RFC 7296 (IKEv2): https://datatracker.ietf.org/doc/html/rfc7296

---

[← 13. Validation](13-validation.md) | [00. README](00-README.md) | [15. RDS Replica →](15-aws-rds-replica.md)
