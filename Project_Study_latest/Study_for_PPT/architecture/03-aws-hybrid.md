# 03. AWS 하이브리드 아키텍처

> ⭐ **한 줄 요약**: AWS VPC (10.20.0.0/16) + Site-to-Site IPsec VPN으로 온프레와 연결. **NLB → EC2 HAProxy → EKS** 단일 진입점. 평시 0 노드, burst 시 자동 scale.

---

## 🎯 우리가 한 선택

### AWS 자원 (Phase 1-2)
| 자원 | ID/값 | 역할 |
|---|---|---|
| **Region** | ap-northeast-2 (Seoul) | 한국 사용자 latency ↓ |
| **VPC** | vpc-03859601c1dd5b658 (10.20.0.0/16) | 가상 네트워크 |
| **Public Subnet 2a** | 10.20.1.0/24 | NAT GW, NLB |
| **Public Subnet 2c** | 10.20.2.0/24 | NAT GW, NLB |
| **Private Subnet 2a** | 10.20.10.0/24 | EC2, EKS 노드 |
| **Private Subnet 2c** | 10.20.20.0/24 | EC2, EKS 노드 |
| **NAT GW × 2** | AZ별 | private → 인터넷 outbound |
| **EC2 HAProxy × 2** | t3.micro (kosa-tickets-haproxy-1a/1c) | EKS 앞단 L7 |
| **NLB** | kosa-tickets-nlb-...elb.ap-northeast-2.amazonaws.com | Cross-zone L4 |
| **CGW (Customer Gateway)** | cgw-0923e106392116cfc | TP-Link 공인 IP 125.131.208.229 |
| **VGW (Virtual Private GW)** | vgw-0f14a420ce5d30261 | AWS 측 VPN endpoint |
| **VPN Connection** | vpn-0906e8a06bb85a041 | 2 터널 (43.200.200.229, 54.116.133.94) |

### 다이어그램
```
온프레 (172.16.0.0/12)                AWS VPC (10.20.0.0/16)
─────────────────────                  ──────────────────────
[bastion 172.16.24.10]                 [Public Subnet 2a/2c]
  K8s + Pod (172.16.23.x)                NAT GW × 2
        │                                NLB
        │                                  │
[pfSense WAN .109]                       [Private Subnet 2a/2c]
        │ (NAT-T)                          EC2 HAProxy × 2
        │                                  EKS Karpenter Spot Node (burst 시)
[ER605 ISP 125.131.208.229]                  │
        │                                    │
        └─ IPsec VPN ──────────────────────┘
              (P1: AES256/SHA1/DH2)
              (P2: AES256/SHA1/PFS2)
              (rtt ~6ms)
```

---

## 🔍 고려한 대안들

### Q1. Site-to-Site VPN vs Direct Connect vs Transit Gateway

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **VPN (선택)** | 빠른 구축 (1일), 저렴 ($36/월) | 인터넷 경유 latency 변동 | ★★★★★ |
| **Direct Connect** | 전용선 (안정/빠름) | 월 $500+, 회선 신청 수 주 | ★ (소규모엔 과함) |
| **Transit Gateway** | multi-VPC + on-prem 허브 | $36 + 트래픽 + attachment 비용 | ★★★ (multi-VPC 시) |

### Q2. NLB vs ALB vs CloudFront

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **NLB (선택)** | L4 (TCP/TLS), 정적 IP, 초저지연 | L7 라우팅 X (Host/Path 안 봄) | ★★★★ |
| **ALB** | L7 라우팅, WAF 직접 통합 | 정적 IP X (DNS만), 약간 비쌈 | ★★★★ |
| **CloudFront** | 글로벌 CDN, edge caching | TCP만 (TLS termination only at edge) | ★★★ (보조용) |

→ 우리는 NLB + CloudFront 둘 다. NLB가 origin, CloudFront가 외부 진입점.

### Q3. EC2 HAProxy vs ALB

이건 다음 04 burst-architecture에서 더 자세히. 짧게:
- ALB → AWS 관리 L7, target group 직접 EKS pods
- EC2 HAProxy → 우리가 통제, runtime weight 조정 (Lambda로 burst 트리거 가능), 일관성

선택: **EC2 HAProxy** (Burst 흐름 제어 + 우리 패턴 일관성)

### Q4. 단일 AZ vs Multi-AZ

| 대안 | 장점 | 단점 |
|---|---|---|
| 단일 AZ | 비용 ↓ (NAT 1대), 단순 | AZ 죽으면 전체 down |
| **Multi-AZ (선택)** | HA, AWS 권장 | NAT GW 2배, cross-AZ 트래픽 비용 |

---

## 💡 왜 이걸 선택했나 (4가지)

### 1. 🔧 **VPN = 빠른 PoC + 학습**
- Direct Connect는 회선 신청 수 주 + 비용 ★★★★★
- VPN으로 1일에 양방향 연결 검증 가능

### 2. 💰 **NLB + EC2 HAProxy = 통제 + 비용**
- NLB만 두면 L7 라우팅 못 함
- ALB는 우리 burst 패턴(runtime weight)과 안 맞음
- EC2 HAProxy = 온프레와 동일 도구 → 운영 일관성

### 3. 📊 **Multi-AZ = AWS 표준 + 학습**
- 진짜 운영이면 무조건 multi-AZ
- 학습 환경에서도 single AZ 함정 직접 경험하기 비추

### 4. 🌐 **Private Subnet에 모든 워크로드**
- EC2/EKS는 외부 직접 노출 X
- 유일한 진입점 = NLB (public)
- 외부 outbound는 NAT GW 통해 (security ↑)

---

## 💰 비용 분석 (월간, USD)

| 자원 | 단가 | 사용량 | 월 비용 |
|---|---|---|---|
| **VPN Connection** | $0.05/시간 | 24×30 = 720h | **$36** |
| **NAT Gateway × 2** | $0.045/시간 + 데이터 처리비 | 720h × 2 + ~10GB | **$66** (≈ $32 × 2 + 데이터) |
| **EC2 t3.micro × 2** | $0.0104/시간 (서울) | 720h × 2 | **$15** |
| **NLB** | $0.0225/시간 + LCU | 720h | **$16** |
| **데이터 전송 (cross-AZ + outbound)** | $0.01~0.126/GB | ~10GB | **~$1** |
| **Route 53 hosted zone** | $0.50/zone/월 | 1 | **$0.5** |
| **합계 (Phase 1-2)** | | | **~$135 (₩17만)** |

### Burst 활성 시 추가
| 자원 | 단가 | 사용량 | 추가 비용 |
|---|---|---|---|
| EKS cluster | $0.10/시간 (제어 평면) | 720h | +$72/월 (cluster는 평시도 ON) |
| Karpenter Spot Node (m5.large) | ~$0.029/시간 (Spot 75% 할인) | burst 시간만 | 변동 |
| RDS db.t3.micro (replica) | $0.017/시간 | 720h | +$12/월 |
| CloudFront | $0.085/GB outbound | ~5GB | +$0.5/월 |
| WAF | $5 + $1/rule | 5 rules | +$10/월 |

→ **풀 phase 1-5 운영 시 ~$230/월 (₩30만)**

### 100% AWS로 했을 때 (가설)
- 온프레 워커 워크로드를 EKS로: t3.xlarge × 4 = ~$240/월
- Ceph 6TB → EBS gp3 = ~$480/월
- DB → RDS t3.medium HA = ~$80/월
- 합계 약 **$800+/월 = ₩100만+/월**

**→ 하이브리드가 약 70% 절감** (하드웨어 감가 포함해도)

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 양방향 통신 (VPN) | 인터넷 경유 latency (6ms) |
| Multi-AZ HA | NAT GW 2배 비용 |
| 통제 가능 (EC2 HAProxy) | 직접 운영 부담 |
| 정적 IP (NLB) | L7 라우팅 우회 (HAProxy 추가) |
| 평시 EKS 0 | Karpenter 학습 필요 |

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **VPN 양쪽 터널 끊김** | 온프레 ↔ AWS 단절 → RDS replication lag, Lambda 등 영향 | pfSense IPsec 재연결 (Disconnect→Connect) |
| **NAT GW 1대 죽음** | 해당 AZ의 outbound 끊김 | 다른 AZ NAT으로 라우팅 (수동 RT 변경) |
| **EC2 HAProxy 1대** | 다른 1대가 NLB로 받음 | NLB 자동 health check |
| **NLB** | EKS 진입 불가 | AWS 책임 (관리형) |
| **RDS replica** | EKS Pod read 못함 → 온프레 PXC로 fallback 필요 (현재 미구현) | RDS reboot 또는 다른 replica |

---

## 🚀 확장 가능성

### Option A: Direct Connect 도입
- ✅ **장점**: 전용선 (안정/저지연), AWS Marketplace 가능
- ❌ **단점**: 월 $500+, 회선 신청 수 주
- 🎯 **추천 시점**: 트래픽 100Mbps 이상 또는 SLA 99.99% 요구

### Option B: Transit Gateway (multi-VPC 시)
- ✅ **장점**: 여러 VPC + 온프레 허브, 라우팅 단순화
- ❌ **단점**: $36/월 + attachment 비용
- 🎯 **추천 시점**: VPC 3개 이상

### Option C: VPC Peering
- ✅ **장점**: cross-region 또는 cross-account 연결
- ❌ **단점**: full mesh 관리 부담
- 🎯 **추천 시점**: 다른 팀의 VPC와 통신 필요

### Option D: VPC Endpoint (S3, ECR)
- ✅ **장점**: NAT GW 우회 → 데이터 처리비 절감, latency ↓
- ❌ **단점**: endpoint당 $7/월
- 💰 **비용 절감**: NAT 데이터비 GB당 $0.045 → endpoint $0 (Gateway endpoint)
- 🎯 **추천 시점**: 월 100GB+ S3/ECR 트래픽 시

### Option E: PrivateLink (외부 SaaS와 연결)
- ✅ **장점**: VPN/인터넷 없이 SaaS와 직접 통신
- 🎯 **추천 시점**: 특정 SaaS (Snowflake, Datadog 등) 사용 시

### Option F: Multi-region
- ✅ **장점**: 지리적 DR, 글로벌 latency
- ❌ **단점**: 비용 2배, 복제 복잡도
- 🎯 **추천 시점**: 진짜 글로벌 운영

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| VPN 트래픽 자주 100Mbps+ | A |
| 다른 팀 VPC 연결 | B/C |
| NAT 데이터비 월 $50+ | D |
| 글로벌 사용자 | F |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 자기 (`04-burst-architecture.md`) | NLB/HAProxy/EKS는 burst 흐름의 일부 |
| 💾 데이터 | RDS replica는 VPN 위에서 동작 (`data-storage/06-rds-replication.md`) |
| 🔧 CI/CD | Lambda burst-trigger 배포 (terraform/aws/) |
| 🔒 보안 | IPsec 정책, IAM Role, Security Group, WAF |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 왜 Direct Connect 안 쓰고 VPN?**
A. (1) 학습 환경엔 비용 ★★★★★, (2) VPN은 1일 PoC 가능, (3) 우리 워크로드 트래픽 작아서 latency 6ms로 충분. 운영급 100Mbps+면 DC 권장.

**Q2. NLB + EC2 HAProxy 이중 구조 왜?**
A. NLB는 L4라 Host header 못 봄. EC2 HAProxy가 L7 라우팅 + runtime weight 조정 (Lambda가 socat으로 weight 변경 → burst 트리거). ALB로도 가능하지만 우리 패턴(weight 조정)과 안 맞아 직접 통제 가능한 EC2 HAProxy 선택.

**Q3. NAT Gateway가 비싸다. 줄일 방법?**
A. (1) NAT instance (저렴하지만 HA 직접 구현), (2) VPC Endpoint로 S3/ECR 트래픽 우회 (Gateway endpoint 무료), (3) 다른 AZ 죽일 거면 1개로 줄임 (HA 포기). 우리는 학습 목적이라 1개 줄여도 됨.

**Q4. VPN에서 6ms인데 PXC ↔ RDS replication 지연 영향?**
A. binlog replication은 비동기 → 지연 OK. read replica 쿼리는 EKS Pod에서 발생하니 latency 영향 없음 (EKS ↔ RDS는 같은 region 내). 온프레에서 RDS 조회 시만 6ms 영향.

**Q5. 강의장 NAT 뒤라 ER605 ISP IP 사용 안 되는데 VPN 어떻게?**
A. pfSense가 NAT-T (NAT Traversal) 활성 → UDP 4500으로 IPsec encapsulation. ER605도 NAT-T 통과시킴 (ALG 끔). 그래서 사설 IP 뒤에서도 동작.
