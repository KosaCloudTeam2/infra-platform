# pfSense 설치부터 이중화(HA) 구성 완벽 가이드

Proxmox 환경에서 pfSense를 설치하고 CARP 기반 이중화까지 구성하는 전체 과정입니다.

---

## 1. 전체 구성 개요

### 최종 목표 아키텍처

```
              [ 인터넷 (Omada 라우터) ]
                       ↓
              [ 관리형 스위치 ]
                       ↓
        ┌──────────────┼──────────────┐
        ↓                              ↓
   [ pve-node1 ]                  [ pve-node2 ]
   pfSense Master                pfSense Backup
        ↓                              ↓
   WAN: 192.168.31.10           WAN: 192.168.31.11
   LAN: 192.168.10.1            LAN: 192.168.10.2
        └───────── SYNC ──────────────┘
                10.10.10.1 ↔ 10.10.10.2

   [ CARP 가상 IP (외부에서 보이는 IP) ]
   WAN VIP: 192.168.31.100
   LAN VIP: 192.168.10.254  ← LAN PC들의 게이트웨이

   [ Master 장애 시 ]
   1~3초 내 Backup이 가상 IP 인계 → 무중단 통신
```

### 사용 IP 정리

| 항목 | Master | Backup | CARP VIP |
|---|---|---|---|
| WAN | 192.168.31.10 | 192.168.31.11 | 192.168.31.100 |
| LAN | 192.168.10.1 | 192.168.10.2 | 192.168.10.254 |
| SYNC | 10.10.10.1 | 10.10.10.2 | (CARP 사용 안 함) |

---

## 2. 사전 준비

### 2-1. ISO 다운로드

pfSense 공식 사이트:

```
https://www.pfsense.org/download/

선택:
- Architecture: AMD64
- Installer: ISO Installer
```

### 2-2. ISO 압축 풀기 + Proxmox 업로드

```bash
# Proxmox SSH 접속
cd /var/lib/vz/template/iso/

# 다운받은 .iso.gz 풀기
gunzip pfSense-CE-2.7.2-RELEASE-amd64.iso.gz

# 확인
ls -lh
```

또는 웹 UI에서 **노드 → local → ISO Images → Upload**.

### 2-3. Proxmox 브리지 구성

각 노드(pve-node1, pve-node2)에 다음 브리지 필요:

| 브리지 | 용도 | 물리 NIC |
|---|---|---|
| vmbr0 | WAN (인터넷) | 외부 연결된 NIC |
| vmbr1 | LAN (내부망) | 내부 연결된 NIC 또는 가상 |
| vmbr2 | SYNC (HA 동기화) | 별도 NIC 또는 VLAN |

#### 브리지 추가 (없으면)

웹 UI: **노드 → System → Network → Create → Linux Bridge**

```
Name: vmbr1
IPv4: (비움)
Bridge ports: (해당 NIC 또는 비움)
```

vmbr2도 동일하게 추가.

**중요**: vmbr2(SYNC)는 노드1과 노드2 간 통신이 가능해야 합니다. 가상 브리지로만 만들면 노드 간 통신 불가하니, **물리 NIC을 같은 스위치에 연결**하거나 **별도 VLAN(예: VLAN 99)을 trunk로** 사용.

---

## 3. pfSense VM 생성 (양쪽 노드)

### 3-1. Master VM 생성 (pve-node1)

웹 UI: **Create VM**

#### General

```
Node: pve-node1
VM ID: 100
Name: pfsense-master
```

#### OS

```
ISO image: pfSense-CE-2.7.2-RELEASE-amd64.iso
Type: Other
```

#### System

```
Graphic card: Default
SCSI Controller: VirtIO SCSI single
QEMU Agent: 체크 안 함
```

#### Disks

```
Bus/Device: SCSI / 0
Storage: local-lvm
Disk size: 20 GB
```

#### CPU

```
Sockets: 1
Cores: 2
Type: host
```

#### Memory

```
Memory: 2048 MiB
```

#### Network

첫 번째 NIC (WAN):

```
Bridge: vmbr0
Model: VirtIO
Firewall: 체크 해제 ← 중요
```

#### Confirm

**Start after created 체크 해제** (NIC 추가 후 시작).

### 3-2. Master VM에 NIC 2개 추가

VM 생성 후 NIC 2개 더 추가:

#### LAN NIC (net1)

```
VM → Hardware → Add → Network Device
Bridge: vmbr1
Model: VirtIO
Firewall: 체크 해제
```

#### SYNC NIC (net2)

```
Bridge: vmbr2
Model: VirtIO
Firewall: 체크 해제
```

### 3-3. Backup VM 생성 (pve-node2)

같은 방식으로 pve-node2에 생성:

```
Node: pve-node2
VM ID: 101
Name: pfsense-backup

NIC 3개:
   net0 → vmbr0 (WAN)
   net1 → vmbr1 (LAN)
   net2 → vmbr2 (SYNC)
```

---

## 4. pfSense 설치 (Master 먼저)

### 4-1. VM 시작 + 콘솔 진입

```
pfsense-master VM 우클릭 → Start
→ Console 메뉴 클릭
```

### 4-2. 설치 진행

#### 1) Copyright Notice

`Accept` → Enter

#### 2) Install pfSense

`Install` → Enter

#### 3) Keymap

`Continue with default keymap` → Enter

#### 4) Partitioning

`Auto (ZFS)` → Enter

#### 5) ZFS Configuration

```
Pool Type/Disks: stripe
[*] da0 (또는 vtbd0) - 디스크 선택 (스페이스로)
→ >>> Select 선택
→ Yes (확인)
```

#### 6) 자동 설치 진행

5~10분 대기.

#### 7) Manual Configuration

`No` → Enter

#### 8) Reboot

`Reboot` → Enter

### 4-3. 첫 부팅 - 인터페이스 자동 할당

재부팅 후 인터페이스 할당 화면이 나옵니다.

#### VLAN 설정 여부

```
Should VLANs be set up first? (y/n)
→ n
```

#### WAN 인터페이스 선택

```
Please select the WAN interface
→ vtnet0 선택 → Tab → OK
```

#### WAN Network Mode

```
Interface Mode: DHCP (그대로)
→ Tab → Continue → OK
```

#### LAN 인터페이스 선택

```
Please select the LAN interface
→ vtnet1 선택 → Tab → OK
```

#### LAN Network Mode

```
Interface Mode: Static IPv4
IPv4 Settings: Continue 선택 (나중에 변경)
→ Tab → Continue → OK
```

#### Interface Assignment 확인

```
LAN  vtnet1 (active)
WAN  vtnet0 (active)
→ Tab → [ Continue ] → Enter
```

#### 라이선스 화면

```
[ Install CE ] → Enter   (무료 버전)
```

설치 진행 후 콘솔 메뉴가 나옵니다.

### 4-4. Master LAN IP 변경

콘솔 메뉴에서 **`2`** 입력.

```
Available interfaces:
1 - WAN (vtnet0 - dhcp)
2 - LAN (vtnet1 - static)
3 - OPT1 (vtnet2)

Enter the number: 2

Configure IPv4 via DHCP? (y/n): n
Enter LAN IPv4 address: 192.168.10.1
Subnet bit count (1-31): 24
Enter LAN IPv4 gateway: (그냥 Enter)
Configure IPv6 via DHCP6? (y/n): n
IPv6 address: (그냥 Enter)

Do you want to enable DHCP server on LAN? (y/n): y
Start address: 192.168.10.100
End address: 192.168.10.200

Revert to HTTP? (y/n): n
```

설정 완료되면 메시지:

```
The IPv4 LAN address has been set to 192.168.10.1/24
You can now access the webConfigurator at:
   https://192.168.10.1/
```

### 4-5. SYNC 인터페이스 설정 (Master)

콘솔 메뉴에서 **`2`** 입력.

```
Enter the number: 3 (OPT1)

Configure IPv4 via DHCP? (y/n): n
Enter IPv4 address: 10.10.10.1
Subnet bit count (1-31): 30
Gateway: (Enter)
IPv6: n, Enter
DHCP server: n
HTTP: n
```

---

## 5. Backup pfSense 설치

Master와 동일하게 진행하되, IP만 다르게:

### 설치 과정

위 4-1 ~ 4-3 동일하게 진행.

### LAN IP 설정 (Backup)

```
LAN IPv4: 192.168.10.2
Subnet: 24

DHCP server: n   ← Backup에서는 DHCP 끔 (Master에서만 운영)
```

**중요**: Backup에서는 DHCP 끄기. Master가 동기화로 DHCP 설정을 보내줍니다.

### SYNC IP 설정 (Backup)

```
OPT1 IPv4: 10.10.10.2
Subnet: 30
```

---

## 6. Master 웹 UI 초기 설정

### 6-1. 웹 UI 접속

LAN쪽 PC에서 (192.168.10.x 대역의 PC):

```
https://192.168.10.1
```

기본 계정:
- ID: `admin`
- Password: `pfsense`

### 6-2. Setup Wizard

처음 로그인하면 마법사가 나옵니다.

#### Step 1 - General Information

```
Hostname: pfsense-master
Domain: local
Primary DNS: 8.8.8.8
Secondary DNS: 1.1.1.1
Override DNS: 체크
```

#### Step 2 - Time

```
Time server: kr.pool.ntp.org
Timezone: Asia/Seoul
```

#### Step 3 - WAN

```
SelectedType: Static (또는 DHCP)

Static 선택 시:
   IPv4 Address: 192.168.31.10
   Subnet: 24
   Upstream Gateway: 192.168.31.1
```

체크박스에서 **Block private networks**, **Block bogon networks** 체크 해제 (LAN 통신 위해).

#### Step 4 - LAN

```
LAN IP: 192.168.10.1
Subnet: 24
```

#### Step 5 - Admin Password

```
Admin Password: <강력한 새 비밀번호>
Confirm: <동일>
```

#### Step 6 - Reload

설정 적용.

### 6-3. 기본 동작 확인

LAN PC에서:

```bash
ping 192.168.10.1     # pfSense LAN
ping 8.8.8.8          # 외부 (Master 통해 나감)
ping google.com       # DNS
```

다 되면 Master 단독 동작 OK.

---

## 7. Backup 웹 UI 초기 설정

### 7-1. 웹 UI 접속

LAN PC에서 임시로 192.168.10.2를 IP로 설정 후 접속:

```
https://192.168.10.2
```

또는 Master의 LAN과 같은 대역에 있는 PC라면 그대로 192.168.10.2로 접근 가능.

### 7-2. Setup Wizard

Master와 동일하게 진행하되:

```
Hostname: pfsense-backup
WAN IP: 192.168.31.11   ← Master와 다른 IP
LAN IP: 192.168.10.2    ← Master와 다른 IP
Admin Password: <Master와 동일하게 설정>
```

**Admin 비밀번호는 양쪽 동일하게**. 동기화 인증에 필요.

---

## 8. 양쪽 SYNC 인터페이스 활성화

### Master 웹 UI

#### Interfaces → Assignments

```
Interface assignments:
   WAN: vtnet0
   LAN: vtnet1
   
Available network ports:
   vtnet2 (보임)
   → +Add 클릭 → OPT1 추가됨
```

#### Interfaces → OPT1

```
Enable interface: ✓
Description: SYNC

IPv4 Configuration: Static IPv4
IPv4 Address: 10.10.10.1/30

Save → Apply Changes
```

#### Firewall → Rules → SYNC

```
+Add (Pass)
Action: Pass
Interface: SYNC
Address Family: IPv4
Protocol: Any
Source: SYNC net
Destination: Any
Description: Allow SYNC

Save → Apply Changes
```

### Backup 웹 UI

위와 동일하게 진행하되 IP만:

```
OPT1 → Description: SYNC
IPv4: 10.10.10.2/30
방화벽 룰 동일하게 추가
```

### 통신 확인

Master 웹 UI: **Diagnostics → Ping**

```
Hostname: 10.10.10.2
Source Address: SYNC
→ Ping
```

응답이 오면 SYNC 통신 정상.

---

## 9. CARP 가상 IP 생성 (Master에서만)

### 9-1. WAN CARP VIP

웹 UI: **Firewall → Virtual IPs → +Add**

```
Type: CARP
Interface: WAN
Address Type: Single Address
Address: 192.168.31.100/24

Virtual IP Password: SecretCarpPassword123
   (양쪽 동일하게 입력될 비밀번호)

VHID Group: 1
Advertising Frequency:
   Base: 1
   Skew: 0    ← Master는 0 (낮을수록 우선)

Description: WAN CARP VIP

Save → Apply Changes
```

### 9-2. LAN CARP VIP

```
Firewall → Virtual IPs → +Add

Type: CARP
Interface: LAN
Address Type: Single Address
Address: 192.168.10.254/24

Virtual IP Password: SecretCarpPassword123
   (위와 동일!)

VHID Group: 2    ← WAN과 다른 번호
Advertising Frequency:
   Base: 1
   Skew: 0

Description: LAN CARP VIP

Save → Apply Changes
```

---

## 10. High Availability Sync 설정 (Master)

웹 UI: **System → High Avail. Sync**

### 10-1. State Synchronization Settings (pfsync)

```
Synchronize states: ✓
Synchronize Interface: SYNC
pfsync Synchronize Peer IP: 10.10.10.2
```

### 10-2. Configuration Synchronization Settings (XMLRPC Sync)

```
Synchronize Config to IP: 10.10.10.2
Remote System Username: admin
Remote System Password: <Backup의 admin 비밀번호>
   (Master와 같게 설정했으므로 같은 값)

[ 동기화할 항목 모두 체크 ]
✓ Synchronize Users and Groups
✓ Synchronize Auth Servers
✓ Synchronize Certificate Authorities
✓ Synchronize Certificates
✓ Synchronize Firewall Rules
✓ Synchronize Firewall Schedules
✓ Synchronize Aliases
✓ Synchronize NAT
✓ Synchronize IPsec
✓ Synchronize OpenVPN
✓ Synchronize DHCP Server settings
✓ Synchronize DHCP Relay settings
✓ Synchronize DNS Forwarder
✓ Synchronize DNS Resolver
✓ Synchronize Captive Portal
✓ Synchronize Static Routes
✓ Synchronize Load Balancer
✓ Synchronize Virtual IPs ★
✓ Synchronize Traffic Shaper
✓ Synchronize Wake-on-LAN
```

**Virtual IPs는 반드시 체크**. CARP VIP 정보가 Backup에 자동 전파됩니다.

**Save**

---

## 11. Backup의 동기화 수신 설정

웹 UI: **System → High Avail. Sync** (Backup에서)

### State Synchronization만 설정

```
Synchronize states: ✓
Synchronize Interface: SYNC
pfsync Synchronize Peer IP: 10.10.10.1
```

### Configuration Synchronization은 비움

Master에서 push로 보내주므로 Backup은 받기만 함.

```
Synchronize Config to IP: (비움)
Remote System Username: (비움)
Remote System Password: (비움)
```

**Save**

---

## 12. 동기화 확인

### Master에서 확인

웹 UI: **Status → CARP**

```
LAN CARP (vhid 2)
   IP: 192.168.10.254
   Status: MASTER

WAN CARP (vhid 1)
   IP: 192.168.31.100
   Status: MASTER
```

### Backup에서 확인

```
LAN CARP (vhid 2)
   Status: BACKUP

WAN CARP (vhid 1)
   Status: BACKUP
```

이렇게 보이면 정상.

### Backup에 VIP가 자동 생성됐는지

Backup 웹 UI: **Firewall → Virtual IPs**

Master에서 만든 VIP 2개가 자동으로 보여야 함. 안 보이면 동기화 실패 → Master에서 비밀번호/IP 재확인.

---

## 13. NAT 및 DHCP 조정

### 13-1. Outbound NAT (Master에서)

웹 UI: **Firewall → NAT → Outbound**

```
Mode: Hybrid Outbound NAT (Manual + Auto)

→ Save

[ 자동 생성된 룰 편집 ]
- LAN to WAN 룰의 NAT Address를:
  Interface Address (기본) → WAN CARP VIP (192.168.31.100)
```

이렇게 해야 LAN PC가 외부로 나갈 때 항상 VIP에서 나갑니다. Master 장애 시에도 NAT가 끊기지 않음.

### 13-2. DHCP Server (Master에서)

웹 UI: **Services → DHCP Server → LAN**

```
Enable: ✓
Range: 192.168.10.100 - 192.168.10.200

Server Settings:
   Gateway: 192.168.10.254  ← LAN CARP VIP
   DNS Servers: 192.168.10.254

Failover Peer IP: 10.10.10.2  ← Backup의 SYNC IP
```

LAN PC들이 받는 게이트웨이를 **CARP VIP**로 만들어야 페일오버 시에도 통신 유지됨.

---

## 14. LAN PC 설정

### DHCP 사용 시

자동으로 게이트웨이가 192.168.10.254 (CARP VIP)로 설정됨.

### 고정 IP 사용 시

```
IP: 192.168.10.50 (예시)
Subnet: 255.255.255.0
Gateway: 192.168.10.254  ← CARP VIP
DNS: 192.168.10.254
```

---

## 15. 페일오버 테스트

### 시나리오 1 - Master 정지

LAN PC에서:

```bash
ping -t 8.8.8.8       # Windows
ping 8.8.8.8          # Linux
```

Master pfSense를 Proxmox에서 Stop:

```
pfsense-master VM → Shutdown
```

결과:
- 1~3초 동안 ping 1~2회 timeout
- 그 후 정상 응답 재개
- LAN PC는 IP 변경 없이 계속 통신

### 시나리오 2 - Master 복귀

Master 다시 시작:

```
pfsense-master VM → Start
```

결과:
- Master가 자동으로 다시 MASTER 상태 인계
- Skew=0이라 우선순위 높음
- Backup은 다시 BACKUP으로 돌아감

### Status → CARP에서 실시간 확인

Master 끄면 Backup의 Status가 MASTER로 전환되는 게 보임.

---

## 16. Proxmox 클러스터 환경에서의 추천 배치

이전 대화의 4노드 클러스터 환경이라면:

```
[ pve-node1 ] → pfsense-master (HA Group: never-migrate)
[ pve-node2 ] → pfsense-backup (HA Group: never-migrate)
[ pve-node3 ] → 다른 워크로드
[ pve-node4 ] → 다른 워크로드
```

**핵심 원칙**:

1. **Master와 Backup은 다른 물리 노드에 배치**
   - 같은 노드에 두면 노드 장애 시 둘 다 죽음

2. **pfSense VM은 Live Migration 권장 안 함**
   - WAN 물리 NIC 의존성
   - 마이그레이션 중 일시 단절 발생
   - HA 자체로 충분한 가용성

3. **각 VM을 노드에 고정**
   - HA Group 또는 Migration 제한 설정

---

## 17. 문제 해결 (Troubleshooting)

### 양쪽이 모두 MASTER 상태 (Split-brain)

원인: SYNC 인터페이스 통신 불가

확인:

```
Master에서:
Diagnostics → Ping → 10.10.10.2 (Backup SYNC IP)

응답 없음 → SYNC 네트워크 점검:
- vmbr2가 양쪽 노드 간 통신 가능한지
- 방화벽 룰에 SYNC Pass 룰 있는지
- SYNC 인터페이스 IP 정확한지
```

### Backup이 BACKUP 상태로 안 됨

원인: VIP 비밀번호 또는 VHID 불일치

확인: Master와 Backup의 VIP 설정이 동일한지
- Virtual IP Password
- VHID Group 번호

### 동기화 실패 (Backup에 VIP 안 보임)

원인: XMLRPC 인증 실패

확인:
```
System → High Avail. Sync (Master)

Synchronize Config to IP: 10.10.10.2 (정확한지)
Remote System Username: admin
Remote System Password: (Backup admin 비번과 일치하는지)
```

테스트:
```
System → High Avail. Sync 페이지 하단 "Test"
```

### LAN PC에서 외부 통신 안 됨

원인: 게이트웨이가 CARP VIP가 아님

확인:
```
LAN PC에서:
ipconfig (Windows) 또는 ip route (Linux)

Default Gateway가 192.168.10.254인지
   아니면 → 192.168.10.1 또는 192.168.10.2 (실제 IP) 가리키는 중
   → CARP VIP로 변경 필요
```

### 페일오버 후 외부 통신 안 됨

원인: Outbound NAT가 실제 IP를 사용 중

확인:
```
Firewall → NAT → Outbound

NAT Address가 WAN address (실제 IP) → CARP VIP로 변경
```

---

## 18. HA 동작 검증 명령어

콘솔에서 (메뉴 8번 Shell):

```sh
# CARP 상태
ifconfig | grep carp

# 출력 예 (Master):
#   carp: MASTER vhid 1 advbase 1 advskew 0
#   carp: MASTER vhid 2 advbase 1 advskew 0

# pfsync 상태
ifconfig pfsync0
# 정상이면 syncpeer: 10.10.10.2 보임

# 동기화된 상태 개수
pfctl -s state | wc -l
# 양쪽이 비슷한 숫자여야 함
```

---

## 19. 운영 팁

### 19-1. 펌웨어 업그레이드

이중화 환경에서 업그레이드:

```
1. Backup 먼저 업그레이드 → 재부팅
2. 양쪽 정상 동작 확인
3. Master 업그레이드 시:
   - 임시로 Master를 maintenance mode (CARP demotion)
   - Backup이 MASTER 인계
   - Master 업그레이드 → 재부팅
   - 정상 인계
```

### 19-2. 설정 백업

웹 UI: **Diagnostics → Backup & Restore**

- Master 설정 백업 (XML 다운로드)
- 정기적으로 자동 백업 활성화

### 19-3. 모니터링

추천 패키지: **System → Package Manager**

- **pfBlockerNG**: 광고/멀웨어 차단
- **Telegraf**: Prometheus 연동
- **Suricata**: IDS/IPS

---

## 20. 작업 체크리스트

```
[ 사전 준비 ]
[ ] pfSense ISO 다운로드 + 압축 해제
[ ] Proxmox에 ISO 업로드
[ ] vmbr0/vmbr1/vmbr2 브리지 구성

[ Master 설치 ]
[ ] VM 생성 (NIC 3개)
[ ] pfSense 설치
[ ] WAN/LAN/SYNC IP 할당
[ ] 웹 UI Setup Wizard
[ ] LAN PC 통신 확인

[ Backup 설치 ]
[ ] VM 생성 (NIC 3개)
[ ] pfSense 설치
[ ] WAN/LAN/SYNC IP 할당 (Master와 다른 IP)
[ ] 웹 UI Setup Wizard

[ HA 구성 ]
[ ] 양쪽 SYNC 인터페이스 활성화 + 방화벽 룰
[ ] SYNC 통신 ping 확인
[ ] Master에서 CARP VIP 2개 생성
[ ] Master High Avail. Sync 설정
[ ] Backup pfsync 설정
[ ] Backup에 VIP 자동 동기화 확인
[ ] Outbound NAT를 CARP VIP로 변경
[ ] DHCP Server 게이트웨이를 CARP VIP로

[ 검증 ]
[ ] Status → CARP에서 Master/Backup 표시 확인
[ ] LAN PC 게이트웨이 192.168.10.254 확인
[ ] 외부 통신 정상
[ ] Master 정지 → 1~3초 내 페일오버 확인
[ ] Master 복귀 → 자동 인계 확인
```

---

## 한 줄 요약

```
설치: VM 생성 → ISO 부팅 → 인터페이스 할당 → LAN IP 설정 → 웹 UI

이중화: 두 pfSense에 SYNC 추가 → CARP VIP 생성 → 
        High Avail. Sync 설정 → LAN PC 게이트웨이를 VIP로
```

진행하시면서 막히는 단계가 있으면 어느 화면에서 어떤 메시지가 나오는지 알려주세요. 그 단계만 집중해서 도와드릴게요.

가장 중요한 포인트:
- **SYNC 네트워크가 진짜 통신 가능해야 함** (vmbr2가 양쪽 노드 간 연결돼야)
- **VIP 비밀번호와 VHID는 양쪽 동일** (CARP 동작 핵심)
- **LAN PC 게이트웨이는 CARP VIP** (페일오버 시 통신 유지)
