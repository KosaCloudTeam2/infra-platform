# Part 4. 보안 — 발표자 D

- 슬라이드: 23~27 (총 5장)
- 발표 시간: 약 4분 (슬라이드당 약 50초)
- 톤: 다크 메인
- 역할: 5 계층 보안 + 이중 TLS + 자체 CA + AWS VPN

## 파트 전체 흐름

```
보안 계층화 (5계층) → 네트워크 보안 (pfSense+VLAN) → 이중 TLS
  → 자체 CA + cert-manager → AWS VPN + 장애 사례
```

## 핵심 메시지 1줄

"5 계층 다중 방어 — 한 계층 뚫려도 다음 계층이 막는다"

## 발표 진입 멘트

"보안 담당 ○○입니다. 우리 인프라의 보안은 5개 계층으로 구성됩니다. 외부 경계부터 클러스터 안까지 한 계층씩 보호막을 쌓아서, 한 곳이 뚫려도 다음 계층이 막는 구조입니다."

---

## 23. 보안 계층화 — DEFENSE IN DEPTH [다크]

### 한 메시지
5 계층 다중 방어 — Perimeter / Network / Transport / Identity / Hybrid

### 들어갈 내용
- 메인 다이어그램: 5 계층 동심원 또는 가로 단계
- 각 계층: 번호 + 영역명 + 1 키워드

**5 계층**:
1. **L1 Perimeter** — pfSense (방화벽, NAT, VLAN GW)
2. **L2 Network** — VLAN 10/20/30/40 분리
3. **L3 Transport** — 이중 TLS (Edge HAProxy + HAProxy Ingress)
4. **L4 Identity** — 자체 CA + cert-manager 자동 회전
5. **L5 Hybrid** — IPsec VPN (Site-to-Site)

### 발표 멘트
"보안 설계의 핵심은 다중 방어, defense in depth입니다. 외부에서 안쪽으로 5개 계층을 쌓았습니다. 첫째 외부 경계는 pfSense 방화벽이 막고, 둘째는 VLAN으로 관리·DMZ·내부망을 분리하고, 셋째는 TLS로 트래픽을 2번 종료해서 암호화하고, 넷째는 자체 CA로 인증서를 발급하고 자동 회전시키고, 다섯째는 AWS 하이브리드 통신을 IPsec VPN으로 보호합니다. 이제 각 계층을 더 자세히 보겠습니다."

---

## 24. 네트워크 보안 — pfSense HA + VLAN [다크]

### 한 메시지
이중화된 방화벽 + VLAN 4개 분리 + Outbound NAT bypass

### 들어갈 내용
- VLAN 다이어그램:

```
WAN (192.168.21.0/24)
  ↓ NAT 1:1 (.109 → .5)
pfSense HA (CARP + pfsync + XMLRPC)
  ↓
  ├── VLAN 10 — 관리 (172.16.21.0/24)
  ├── VLAN 20 — DMZ (172.16.22.0/24, Edge VIP .5)
  ├── VLAN 30 — Internal (172.16.23.0/24, K8s API VIP .5)
  └── VLAN 40 — Guest/Bastion (172.16.24.0/24)
```

### 핵심 구성
- **pfSense HA**: CARP (BSD 변형 VRRP) + pfsync (state 동기화) + XMLRPC Sync (설정 미러)
- **NAT 1:1**: WAN 192.168.21.109 → Edge VIP 172.16.22.5
- **Outbound NAT bypass**: 172.16.0.0/12 → 10.20.0.0/16 = NO NAT (AWS VPN용)

### 함정
- pfSense VM이 Proxmox 위에 있어서 부팅 순서 의존성 주의
- 관리망이 pfSense 의존하지 않도록 OOB 경로 확보

### 발표 멘트
"네트워크 보안의 첫 단계는 pfSense 방화벽입니다. 단일 노드가 아니라 두 대로 이중화했는데, CARP 프로토콜로 VIP를 공유하고 pfsync로 상태를 동기화하며 XMLRPC로 설정까지 미러링합니다. 그 아래 VLAN을 4개로 나눴습니다 — 관리망, DMZ, 내부망, 게스트망. 외부 트래픽은 WAN의 공인 IP에서 Edge VIP로 NAT 1:1 매핑되고, AWS VPN으로 가는 트래픽은 Outbound NAT를 우회하도록 별도 룰을 뒀습니다."

---

## 25. 이중 TLS — DOUBLE TERMINATION [다크]

### 한 메시지
Edge HAProxy 1차 종료 → 재암호화 → HAProxy Ingress 2차 종료

### 들어갈 내용
- 트래픽 흐름 다이어그램 (가로):

```
Internet
  ↓ HTTPS
pfSense WAN (.109)
  ↓ NAT
Edge VIP (172.16.22.5)
  ↓
Edge HAProxy → 1차 TLS 종료 (자체 CA wildcard *.kosa.team2)
  ↓ Host 헤더 분기
  ↓ 내부 재암호화
172.16.23.50 (MetalLB)
  ↓
HAProxy Ingress → 2차 TLS 종료 (cert-manager per-service cert)
  ↓
Pod
```

### 왜 두 번 종료하는가
1. **DMZ ↔ Internal 신뢰 경계 분리** — Edge HAProxy가 DMZ에 있으니 cert 검사 후 내부로 재암호화
2. **인증서 회전 독립** — 외부 cert와 클러스터 cert 각자 회전 가능
3. **내부 트래픽도 cleartext 아님** — 10G NIC tap/감청 방지

### 비용
- TLS 핸드셰이크 2배 (우리 QPS 규모에선 무시 가능)

### 발표 멘트
"보안 3계층 Transport는 이중 TLS 구조입니다. 외부에서 들어온 HTTPS는 Edge HAProxy에서 한 번 종료돼 cert와 Host 헤더가 검사된 뒤, 내부에서 다시 암호화돼 K8s Ingress에 전달됩니다. Ingress에서 두 번째로 TLS 종료하고 Pod에 평문으로 전달됩니다. 왜 두 번? 첫째 DMZ와 내부망의 신뢰 경계를 분리하기 위해서, 둘째 외부 cert와 클러스터 cert를 독립적으로 회전하기 위해서, 셋째 내부 트래픽도 wire에서 평문이 아니기 위해서입니다. 핸드셰이크 2배 비용은 우리 트래픽 규모에서 무시 가능합니다."

---

## 26. 자체 CA + cert-manager [다크]

### 한 메시지
내부 도메인 → Let's Encrypt 불가 → 자체 CA + cert-manager 자동 회전

### 들어갈 내용
- 다이어그램:

```
KOSA Team 2 Internal CA (10년, bastion ~/pki/ca.crt)
  ↓ 서명
  ├── wildcard.pem (1년) → Edge HAProxy
  └── cert-manager K8s Secret (cert-manager/kosa-ca-secret)
        ↓ ClusterIssuer kosa-ca-issuer
        ├── ticket.kosa.team2 cert (90일) → Ingress
        ├── admin.kosa.team2 cert (90일)
        ├── harbor.kosa.team2 cert (90일)
        ├── jenkins.kosa.team2 cert (90일)
        ├── argocd.kosa.team2 cert (90일)
        └── grafana.kosa.team2 cert (90일)
```

### 핵심 구성
- 자체 CA: KOSA Team 2 Internal CA (10년 만기)
- Wildcard cert: `*.kosa.team2` (1년, Edge HAProxy용)
- per-service cert: 90일 자동 회전 (cert-manager 기본)
- Docker/containerd CA trust 등록 필요 (Harbor 이미지 push/pull)

### 왜 자체 CA?
- 내부 도메인 `*.kosa.team2`은 외부 도메인 검증 불가 → Let's Encrypt 사용 불가
- 자체 CA가 유일한 선택지

### 발표 멘트
"인증서 관리입니다. kosa.team2는 외부에 등록된 도메인이 아니라 내부 전용이라서 Let's Encrypt 같은 public CA를 쓸 수 없습니다. 그래서 자체 CA를 만들었습니다 — KOSA Team 2 Internal CA, 10년 만기입니다. 이 CA로 두 가지 cert를 발급하는데, 첫째는 wildcard cert로 Edge HAProxy용, 1년 만기입니다. 둘째는 cert-manager가 서비스별로 자동 발급하는 cert로 90일마다 자동 회전합니다. ticket-app, admin-app, harbor, jenkins, argocd, grafana 모두 자동으로 cert를 받고 갱신합니다."

---

## 27. AWS VPN 보안 + 장애 사례 [다크]

### 한 메시지
Site-to-Site IPsec + 검증 6ms RTT + Outbound NAT bypass가 90% 원인

### 들어갈 내용 (좌·우 2분할)

**좌 — VPN 구성 다이어그램**:
```
온프레 172.16.0.0/12
  ↓ pfSense (IPsec endpoint)
  ↓ ER605 (NAT-T)
인터넷
  ↓
AWS VGW
  ├── Tunnel 1 → 43.200.200.229
  └── Tunnel 2 → 54.116.133.94
  ↓
AWS VPC 10.20.0.0/16
```

**우 — 설정 + 장애 사례**:

**IPsec 설정 (P1)**:
- IKEv1 / AES256 / SHA1 / DH2 / 28800s
- P2: AES256 / SHA1 / PFS2 / 3600s
- **NAT-T Force** (pfSense가 NAT 뒤니까 필수)

**검증 결과**:
- bastion (172.16.24.10) ↔ EC2 (10.20.10.121) ping
- **6ms RTT** 정상

**장애 사례 — VPN UP인데 ping 실패**:
- 원인 우선순위:
  1. **Outbound NAT bypass (90%)** ⭐ 가장 흔함
  2. AWS Route Propagation
  3. EC2 Security Group ICMP 허용
  4. state cache (1~3분 대기)

### 발표 멘트
"마지막 계층은 AWS 하이브리드 통신 보안입니다. Site-to-Site IPsec VPN으로 양 환경을 연결했고, 검증 결과 bastion에서 EC2로 ping 6ms 정도 나옵니다. 인터넷을 통하지만 LAN처럼 동작합니다. 한 가지 운영 노하우를 공유드리면, VPN이 양쪽 다 UP인데도 ping이 안 가는 케이스가 자주 발생합니다. 원인이 4가지인데, 그 중 90%가 pfSense의 Outbound NAT bypass 룰 누락입니다 — 172.16.0.0/12에서 10.20.0.0/16으로 가는 트래픽에 NO NAT 룰을 추가해야 합니다. 이걸 깜빡하면 VPN 자체는 살아있는데 라우팅이 안 됩니다."

### 다음 발표자에게 패스 (또는 클로징)
"여기까지가 우리 인프라의 보안 5 계층이었습니다. 마지막으로 회고와 다음 단계를 함께 발표하겠습니다."
