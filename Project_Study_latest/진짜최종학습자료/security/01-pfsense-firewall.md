# 01. pfSense 방화벽 + DNS + VPN

> ⭐ **한 줄 요약**: **pfSense HA를 CARP로 구성**해 VLAN 4개의 게이트웨이 + 방화벽 + DNS Resolver + IPsec VPN을 통합 담당한다. 별도 어플라이언스 vs VM의 trade-off에서 학습 가치 + 비용을 우선해 VM 패턴을 골랐다.

---

## 🎯 우리가 한 선택

pfSense는 통합 어플라이언스의 매력이 크다. 별도 장비로 방화벽 + 라우터 + VPN + DNS를 4대 운영하는 대신, pfSense 하나가 모두 처리한다. 우리는 이걸 Proxmox VM 2개 (HA)로 띄워 사용한다.

| 역할 | 설정 |
|---|---|
| **방화벽** | Stateful firewall, default deny inbound, explicit allow |
| **라우터** | VLAN 10/20/30/40 게이트웨이 + WAN ↔ Internal |
| **NAT** | WAN (192.168.21.109) ↔ 내부 VIP (172.16.22.5) |
| **DNS Resolver** | Host Overrides (*.kosa.team2 → 172.16.23.50) |
| **VPN** | IPsec Site-to-Site to AWS (NAT-T 활성) |
| **HA** | CARP (VIP 공유) + pfsync (state) + XMLRPC (config) |

### 외부 노출 정확히 명시 — Port Forward

방화벽의 핵심 원칙은 **외부에서 들어올 수 있는 통로를 명시적으로만 허용**하는 거다. 우리는 단 2개만 외부에 노출한다:

| External | → Internal | 용도 |
|---|---|---|
| TCP 443 | 172.16.22.5:443 | HTTPS 진입 (Edge HAProxy) |
| TCP 80 | 172.16.22.5:80 | HTTP → HTTPS redirect |
| (그 외 모두 차단) | | |

내부 도메인 (jenkins.kosa.team2, harbor.kosa.team2 등)은 외부에서 직접 접근 불가하고, 모두 Edge HAProxy를 통과해야 한다.

### Outbound NAT bypass (VPN용)

VPN 트래픽이 pfSense의 NAT를 거치면 IPsec이 깨진다. 그래서 명시적으로 NAT bypass 룰을 추가했다.

```
Firewall → NAT → Outbound → Hybrid Mode
  맨 위 룰:
    Source: 172.16.0.0/12
    Destination: 10.20.0.0/16
    Translation: NO NAT     ← VPN으로 가는 트래픽 NAT X
```

이 한 줄이 빠지면 VPN이 동작하지 않는다. VPN 트래픽이 pfSense의 NAT pool을 거치면서 IPsec ESP 헤더가 mangle돼 AWS 측에서 인증 실패.

---

## 🔍 고려한 대안들

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **pfSense (선택)** | 무료, FreeBSD 검증, GUI, 방화벽+VPN+DNS 통합 | x86 하드웨어 필요 | ★★★★★ |
| OPNsense | pfSense fork, UI 모던 | 커뮤니티 작음 | ★★★★ |
| Cisco ASA | enterprise | 매우 비쌈, vendor lock | ★ |
| Linux iptables 직접 | 무료, 통제 ★★★★★ | GUI X, 학습 곡선 ★★★★★ | ★★ |
| OpenBSD pf | 검증 | 학습 곡선 | ★★★ |

### pfSense vs Cisco ASA

Cisco ASA는 진짜 enterprise 표준이지만 ASA 5506-X 한 대에 ₩200만+이라 HA 2대 = ₩400만. 학습 환경엔 부적합한 비용이다. pfSense Community Edition은 무료고 기능도 ASA에 크게 떨어지지 않는다.

### pfSense vs OPNsense

OPNsense는 pfSense의 fork인데 UI가 더 모던하고 update 주기가 빠르다. 단점은 커뮤니티가 pfSense보다 작아 자료가 적다. 학습 환경엔 자료 풍부한 pfSense가 유리하다.

### pfSense vs Linux iptables 직접

iptables 직접 구성도 가능하지만 GUI가 없어 운영 부담이 크고, 정책 변경 시 사람 실수 위험이 높다. pfSense는 GUI에서 룰 추가 + 검증 + apply가 가능해 안전하다.

---

## 💡 왜 pfSense?

### 1. 통합 어플라이언스 = 운영 단순화

방화벽 + 라우터 + VPN + DNS + DHCP를 별도 장비 4대로 운영하면 정책 동기화도 어렵고 장애 분석도 복잡하다. pfSense 하나로 통합하면 **단일 GUI로 모든 정책 관리**가 가능하다.

### 2. HA가 native 지원 (CARP)

CARP (Common Address Redundancy Protocol)는 BSD가 만든 VIP HA 프로토콜이다. VRRP의 BSD 라이선스 friendly 버전이라 보면 된다. **VIP를 두 노드가 공유**해서 한 노드 죽으면 다른 노드가 즉시 흡수한다. pfsync로 firewall state도 동기화돼 TCP connection도 끊김 없이 유지된다.

### 3. VPN이 통합돼 있다

IPsec/OpenVPN/WireGuard 모두 native 지원. AWS와 site-to-site 연결할 때 config wizard로 쉽게 설정 가능하다. 별도 VPN 어플라이언스 필요 없음.

### 4. 무료 + 활발

pfSense Community Edition은 완전 무료고, Netgate (회사)가 상업 지원 옵션도 제공한다. 매년 release되고 보안 패치도 빠르다.

### 5. 학습 + 포트폴리오 가치

방화벽 정책 깊이 학습, VPN 트러블슈팅 경험, NAT-T 같은 깊은 개념 다뤄볼 수 있다. 면접에서 "pfSense HA 직접 구축" 어필 가능.

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| pfSense CE | 무료 |
| 하드웨어 | Proxmox VM 2개 (별도 어플라이언스 ₩400만 절약) |
| 운영 | 0.05 FTE |

Cisco ASA 5506-X HA 2대 ₩400만+ 회피했다. Proxmox 자원만 쓰니 CapEx 0이다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 통합 | 별도 어플라이언스 hardware 안정성 |
| GUI + 학습 | enterprise vendor support |
| HA (CARP) | VM이라 호스트 의존 (Proxmox 죽으면 영향) |
| VPN 통합 | 전용 VPN 어플라이언스 성능 |

가장 큰 trade-off는 **VM이라 Proxmox 호스트 의존성**이다. Proxmox 호스트가 죽으면 그 위의 pfSense VM도 같이 죽어 CARP HA 효과가 반감된다. 우리는 pfSense VM 2개를 **다른 Proxmox 호스트에 분산 배치**해서 완화했다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **pfSense MASTER VM 죽음** | CARP failover (수 초) | 자동 |
| **pfSense BACKUP도 죽음** | 인터넷 끊김, 내부 라우팅 X | Proxmox 호스트 회복 |
| **NAT rule 잘못** | 외부 접근 안 됨 또는 무한 노출 | 콘솔에서 룰 수정 |
| **DNS Resolver 다운** | 내부 도메인 해결 X | DNS Resolver 재시작 |
| **IPsec 터널 끊김** | AWS 통신 X | IPsec 재연결 |

가장 흔한 시나리오는 MASTER 죽음인데 CARP가 수 초 내 자동 failover 한다. BACKUP까지 죽는 케이스는 매우 드물지만 (두 다른 Proxmox 호스트가 동시에 죽어야 함), 발생하면 인터넷 자체가 끊긴다. 이건 진짜 비상 상황이라 콘솔 + Proxmox 직접 복구.

---

## 🚀 확장 가능성

### Option A: Cisco ASA / Palo Alto NGFW 도입

진짜 enterprise 안정성과 vendor support + IDS/IPS 통합 원하면 별도 어플라이언스. ₩200만+ × 2 비용 + 학습 + 운영 정책 다 새로 짜야 함.

- 🎯 **추천 시점**: 진짜 운영 + 컴플라이언스

### Option B: ⭐ Suricata/Snort (IDS/IPS)

침해 시도를 탐지하는 도구. 포트 스캔, exploit 시도 같은 패턴을 식별. pfSense 패키지로 무료 설치 가능하다. 단점은 CPU 부담과 false positive.

- 💰 **비용**: 0
- 🎯 **추천 시점**: 진짜 운영

### Option C: ⭐ pfBlockerNG (IP/domain blacklist)

알려진 악성 IP/domain을 자동으로 차단. pfSense 패키지로 무료. 즉시 효과가 보이는 security polish 옵션이다.

- 🎯 **추천 시점**: 즉시 (적용 쉬움)

### Option D: WireGuard로 VPN 교체

IPsec보다 빠르고 단순하다. 단점은 AWS native 지원이 없어 자체 구현 필요. site-to-site 신규 구축 시점에 검토.

### Option E: pfSense를 별도 어플라이언스로 분리

Proxmox 의존성 제거. ₩100만~ 어플라이언스 하드웨어 비용. 진짜 운영급에서 검토.

### Option F: DNSSEC 활성

DNS spoofing 방어. 외부 도메인 정식 운영 시 권장.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 침해 시도 증가 | B (Suricata) + C (pfBlocker) |
| 운영급 진입 | A (enterprise FW) + E (별도 어플라이언스) |
| 외부 도메인 정식 운영 | F (DNSSEC) |

---

## 🔗 다른 파트와의 연결

pfSense는 보안 + 아키텍처 두 파트에 걸쳐 있다. `architecture/01-physical-and-network.md`는 pfSense의 라우팅 역할을, `architecture/03-aws-hybrid.md`는 IPsec VPN 역할을 다룬다. 보안 측면에선 `07-security-policy.md`가 방화벽 정책 = 보안 정책의 핵심임을 강조한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. pfSense를 별도 어플라이언스 아니라 VM으로 한 이유는?**

A. 세 가지 이유입니다. **학습 환경 자원 효율** (별도 어플라이언스 ₩200만+ × 2 회피), **Proxmox HA + pfSense HA 이중 보호** (그 안에서도 어느 정도 격리), **hardware 비용 회피**. 단점은 Proxmox 죽으면 pfSense도 죽어 CARP HA 효과 반감인데, **pfSense VM 2대를 다른 Proxmox 호스트에 분산 배치**해서 완화했습니다.

**Q2. CARP가 keepalived와 다른 점은요?**

A. **CARP = BSD 표준 (Common Address Redundancy Protocol)**이고 VRRP의 라이센스 우려 회피로 BSD가 만든 겁니다. 기능은 거의 동일 (VIP 공유 + 우선순위 election). pfSense는 FreeBSD 기반이라 CARP native입니다. Linux 환경에선 keepalived가 같은 역할입니다.

**Q3. VPN의 NAT-T가 뭔지?**

A. **IPsec은 ESP (Protocol 50)를 쓰는데 NAT 통과 시 ESP 헤더가 mangle**됩니다. NAT-T (NAT Traversal)는 UDP 4500으로 ESP를 encapsulation해서 NAT 통과 가능하게 만드는 표준입니다. 우리는 ER605 (NAT) 뒤에 있어 NAT-T 필수였습니다.

**Q4. Port Forward 외에 외부 노출이 더 있나요?**

A. **80/443만 노출**합니다. 나머지 (Jenkins, ArgoCD, Grafana 등) 모두 내부 도메인 (*.kosa.team2)라 외부 직접 접근 불가. 외부 접근은 모두 Edge HAProxy를 통해 라우팅됩니다 (DMZ 통제).

**Q5. DNS Resolver 죽으면 외부 인터넷도 안 되나요?**

A. **외부는 OK**입니다. DNS Resolver는 내부 도메인 (*.kosa.team2) 해결만 담당하고, 외부 도메인은 ISP DNS 또는 1.1.1.1로 forward됩니다. 내부 도메인 (jenkins.kosa.team2 등)만 해결 못 하는 상태가 됩니다.

**Q6. 방화벽 default deny? 실제로 어떻게 동작하나요?**

A. **inbound (외부 → 내부)는 default deny**입니다. 명시적 allow 룰 (예: WAN 443 → 172.16.22.5)만 통과합니다. **outbound (내부 → 외부)는 default allow** (인터넷 접속 필요). VLAN 간도 명시적 룰로 통제합니다.
