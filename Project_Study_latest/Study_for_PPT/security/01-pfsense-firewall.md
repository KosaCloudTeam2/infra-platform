# 01. pfSense 방화벽 + DNS + VPN

> ⭐ **한 줄 요약**: **pfSense HA** (CARP) = 방화벽 + 라우터 + DNS Resolver + IPsec VPN 통합. VLAN 4개 게이트웨이 + Port Forward + Outbound NAT bypass. 보안 + 아키텍처 이중 역할.

---

## 🎯 우리가 한 선택

| 역할 | 설정 |
|---|---|
| **방화벽** | Stateful firewall, default deny inbound, explicit allow |
| **라우터** | VLAN 10/20/30/40 게이트웨이 + WAN ↔ Internal |
| **NAT** | WAN (192.168.21.109) ↔ 내부 VIP (172.16.22.5) |
| **DNS Resolver** | Host Overrides (*.kosa.team2 → 172.16.23.50) |
| **VPN** | IPsec Site-to-Site to AWS (NAT-T 활성) |
| **HA** | CARP (VIP 공유) + pfsync (state sync) + XMLRPC (config sync) |

### 외부 노출 (Port Forward) 정확히 명시
| External | → Internal | 용도 |
|---|---|---|
| TCP 443 | 172.16.22.5:443 | HTTPS 진입 (Edge HAProxy) |
| TCP 80 | 172.16.22.5:80 | HTTP → HTTPS redirect |
| (그 외 모두 차단) | | |

### Outbound NAT bypass (VPN용)
```
Firewall → NAT → Outbound → Hybrid Mode
  맨 위 룰:
    Source: 172.16.0.0/12
    Destination: 10.20.0.0/16
    Translation: NO NAT     ← VPN으로 가는 트래픽 NAT X
```

---

## 🔍 고려한 대안들

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **pfSense (선택)** | 무료, FreeBSD 기반 검증, GUI, 방화벽+VPN+DNS 통합 | x86 하드웨어 필요 | ★★★★★ |
| OPNsense | pfSense fork, UI 모던 | 커뮤니티 작음 | ★★★★ |
| Cisco ASA | enterprise | 매우 비쌈, vendor lock | ★ |
| Linux iptables 직접 | 무료, 통제 ★★★★★ | GUI X, 학습 곡선 ★★★★★ | ★★ |
| OPENBSD pf | 검증 | 학습 곡선 | ★★★ |

---

## 💡 왜 pfSense?

### 1. 🔧 **통합 어플라이언스**
- 방화벽 + 라우터 + DNS + VPN + DHCP 통합
- 별도 장비 4대 운영 vs 1 어플라이언스
- 운영 부담 ↓ (단일 GUI)

### 2. 🛡️ **HA (CARP)**
- VIP 공유 → 한 노드 죽으면 다른 노드가 즉시 흡수
- pfsync로 state 동기화 (TCP 연결 끊김 X)
- XMLRPC로 설정 동기화 (NAT rule 등)

### 3. 🌐 **VPN 통합**
- IPsec/OpenVPN/WireGuard 모두 지원
- AWS와 site-to-site 쉽게 (config wizard)

### 4. 💰 **무료 + 활발**
- pfSense Community Edition 무료
- Netgate (회사)가 상업 지원 옵션

### 5. 📚 **학습 가치**
- 방화벽 정책 깊이 학습
- VPN 트러블슈팅 경험
- 면접 어필

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| pfSense CE | 무료 |
| 하드웨어 | Proxmox VM 2개 (별도 어플라이언스 ₩100만 절약) |
| 운영 | 0.05 FTE |

비교:
- Cisco ASA 5506-X: ₩200만+ × 2 (HA) = ₩400만 (CapEx)
- 우리 pfSense VM: ₩0 (Proxmox 위에 무료)

→ **CapEx ₩400만 절감**

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 통합 | 별도 어플라이언스 hardware 안정성 |
| GUI + 학습 | enterprise vendor support |
| HA (CARP) | VM이라 호스트 의존 (Proxmox 죽으면 영향) |
| VPN 통합 | 전용 VPN 어플라이언스 성능 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **pfSense MASTER VM 죽음** | CARP failover (수 초) | 자동 |
| **pfSense BACKUP도 죽음** | 인터넷 끊김, 내부 라우팅 X | Proxmox 죽은 호스트 회복 |
| **NAT rule 잘못** | 외부 접근 안 됨 또는 무한 노출 | 콘솔에서 룰 수정 |
| **DNS Resolver 다운** | 내부 도메인 해결 X (외부 OK) | DNS Resolver 재시작 |
| **IPsec 터널 끊김** | AWS 통신 X | IPsec 재연결 (Connect P1) |

---

## 🚀 확장 가능성

### Option A: ⭐ Cisco ASA 또는 Palo Alto NGFW 도입
- ✅ **장점**: enterprise 안정, vendor support, IDS/IPS 통합
- ❌ **단점**: ₩200만+ × 2 비용
- 🎯 **추천 시점**: 진짜 운영 + 컴플라이언스

### Option B: Suricata/Snort (IDS/IPS)
- ✅ **장점**: 침해 시도 탐지 (포트 스캔, exploit 등)
- ❌ **단점**: CPU 부담, false positive
- 💰 **비용**: 0 (pfSense 패키지)
- 🎯 **추천 시점**: 진짜 운영

### Option C: pfBlockerNG (IP/domain blacklist)
- ✅ **장점**: 알려진 악성 IP/domain 차단
- 💰 **비용**: 0 (pfSense 패키지)
- 🎯 **추천 시점**: 즉시 (security polish)

### Option D: WireGuard로 VPN 교체
- ✅ **장점**: IPsec보다 빠름, 단순
- ❌ **단점**: AWS native 지원 X (자체 구현 필요)
- 🎯 **추천 시점**: site-to-site 신규 구축 시 검토

### Option E: pfSense 별도 어플라이언스로 분리
- ✅ **장점**: Proxmox 의존성 제거, 진짜 HA
- ❌ **단점**: 하드웨어 비용
- 🎯 **추천 시점**: 진짜 운영

### Option F: DNSSEC 활성
- ✅ **장점**: DNS spoofing 방어
- 🎯 **추천 시점**: 외부 도메인 정식 운영

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 침해 시도 증가 | B (Suricata) + C (pfBlocker) |
| 운영급 진입 | A (enterprise FW) + E (별도 어플라이언스) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 (`architecture/01-physical-and-network.md`) | pfSense가 VLAN 게이트웨이 + 라우팅 |
| 🏛️ 아키텍처 (`architecture/03-aws-hybrid.md`) | IPsec VPN |
| 🔒 자기 (`07-security-policy.md`) | 방화벽 정책 = 보안 정책의 핵심 |
| 🔒 자기 (`05-secrets-rbac.md`) | pfSense admin password 관리 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. pfSense를 별도 어플라이언스 아니라 VM으로 한 이유?**
A. (1) 학습 환경 자원 효율, (2) Proxmox HA + pfSense HA 이중 보호, (3) hardware 비용 회피. 단점은 Proxmox 죽으면 pfSense도 죽음 → CARP HA 효과 반감. 그래서 pfSense VM 2대를 **다른 Proxmox 호스트**에 분산.

**Q2. CARP가 keepalived와 다른 점?**
A. CARP = BSD 표준 (Common Address Redundancy Protocol), VRRP의 라이센스 우려 회피로 BSD가 만듦. 기능은 거의 동일 (VIP 공유 + 우선순위 election). pfSense (FreeBSD 기반)는 CARP native.

**Q3. VPN NAT-T가 뭔지?**
A. IPsec은 ESP (Protocol 50)를 쓰는데 NAT 통과 시 ESP가 mangle됨. NAT-T (NAT Traversal)는 UDP 4500으로 ESP를 encapsulation해서 NAT 통과 가능. 우리 ER605 (NAT) 뒤라 NAT-T 필수.

**Q4. Port Forward 외에 외부 노출 더 있나?**
A. 80/443만. 나머지 (Jenkins, ArgoCD, Grafana 등) 모두 내부 도메인 (*.kosa.team2) → 외부 직접 X. 외부 접근은 모두 Edge HAProxy 통해 (DMZ 통제).

**Q5. DNS Resolver가 죽으면 외부 인터넷도 안 되나?**
A. 외부는 OK (Resolver는 내부 *.kosa.team2 해결만). 외부 도메인은 ISP DNS 또는 1.1.1.1로 forward.

**Q6. 방화벽 default deny? 실제로 어떻게 동작?**
A. inbound (외부 → 내부)는 default deny. 명시적 allow rule (예: WAN 443 → 172.16.22.5) 만 통과. outbound (내부 → 외부)는 default allow (인터넷 접속 필요). VLAN 간도 명시적 룰.
