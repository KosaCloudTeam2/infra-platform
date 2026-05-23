# 03. AWS 하이브리드 아키텍처

> ⭐ **한 줄 요약**: AWS VPC를 10.20.0.0/16에 만들고, 온프레와 **Site-to-Site IPsec VPN**으로 연결했다. AWS 측 진입점은 **NLB → EC2 HAProxy → EKS** 3단 구조로, 평시엔 0 노드지만 burst trigger 시 자동 확장된다.

---

## 🎯 우리가 한 선택

AWS 측은 multi-AZ Private Subnet 패턴을 따랐다. 외부 노출되는 워크로드는 단 하나 — NLB뿐이고, 나머지 (EC2, EKS, RDS)는 모두 Private Subnet에 배치돼 NAT Gateway를 통해서만 인터넷 outbound가 가능하다. 이는 **외부 공격 표면을 최소화**하기 위한 AWS 표준 패턴이다.

| 자원 | 값 | 역할 |
|---|---|---|
| **Region** | ap-northeast-2 (Seoul) | 한국 사용자 latency ↓ |
| **VPC** | vpc-03859601c1dd5b658 (10.20.0.0/16) | 가상 네트워크 |
| **Public Subnet 2a/2c** | 10.20.1.0/24 / 10.20.2.0/24 | NAT GW, NLB |
| **Private Subnet 2a/2c** | 10.20.10.0/24 / 10.20.20.0/24 | EC2, EKS 노드 |
| **NAT GW × 2** | AZ별 | private → 인터넷 outbound |
| **EC2 HAProxy × 2** | t3.micro | EKS 앞단 L7 |
| **NLB** | kosa-tickets-nlb-...elb | Cross-zone L4 |
| **VPN Connection** | vpn-0906e8a06bb85a041 | 2 터널 (active-active) |

이 토폴로지를 시각화하면 다음과 같다.

```
온프레 (172.16.0.0/12)                AWS VPC (10.20.0.0/16)
─────────────────────                  ──────────────────────
[bastion 172.16.24.10]                 [Public Subnet 2a/2c]
  K8s + Pod (172.16.23.x)                NAT GW × 2
        │                                NLB
        │                                  │
[pfSense WAN .109]                       [Private Subnet 2a/2c]
        │ (NAT-T)                          EC2 HAProxy × 2
        │                                  EKS Karpenter Spot (burst 시)
[ER605 ISP 125.131.208.229]                  │
        │                                    │
        └─ IPsec VPN ──────────────────────┘
              (rtt ~6ms)
```

---

## 🔍 고려한 대안들

### Q1. 사이트 간 연결 — VPN vs Direct Connect vs Transit Gateway

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **VPN (선택)** | 빠른 구축 (1일), 저렴 ($36/월) | 인터넷 경유 latency 변동 | ★★★★★ |
| **Direct Connect** | 전용선 (안정/빠름) | 월 $500+, 회선 신청 수 주 | ★ (소규모엔 과함) |
| **Transit Gateway** | multi-VPC + on-prem 허브 | $36 + 트래픽 + attachment 비용 | ★★★ (multi-VPC 시) |

AWS와 온프레를 연결하는 방법은 크게 세 가지가 있다. Direct Connect는 진짜 전용선으로 가장 안정적이지만, **회선 신청에 수 주 걸리고 월 비용이 $500+**라 학습 환경엔 과하다. Transit Gateway는 여러 VPC와 on-prem을 허브 패턴으로 연결할 때 좋지만, 우리는 VPC 1개라 의미가 적다. **VPN은 1일이면 구축 가능하고 월 $36**으로 가장 저렴하며, 우리 워크로드의 latency 요구 (6ms 정도)에 충분히 부합한다.

VPN의 단점은 인터넷 경유라 latency가 변동할 수 있다는 점인데, 실측 6ms는 진짜 우수한 수치다. 같은 region 내 EC2 ↔ EC2가 1ms 이하인 걸 감안하면 VPN 추가 latency 5ms 정도다. 우리 워크로드 (PXC → RDS replication, EKS Pod 간 통신)에는 충분히 빠르다.

### Q2. L4 분산 — NLB vs ALB vs CloudFront 어떻게 조합?

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **NLB (선택)** | L4 (TCP/TLS), 정적 IP, 초저지연 | L7 라우팅 X | ★★★★ |
| **ALB** | L7 라우팅, WAF 직접 통합 | 정적 IP X (DNS만) | ★★★★ |
| **CloudFront** | 글로벌 CDN, edge caching | TCP만 (TLS termination only at edge) | ★★★ (보조용) |

원래 ALB가 L7 라우팅을 직접 지원하니까 더 단순해 보이지만, 우리는 **burst trigger 시 runtime weight 조정**이 필요했다. Lambda가 EC2 HAProxy의 admin socket에 socat으로 weight를 변경하는 패턴인데, 이건 ALB로는 불가능하다 (ALB는 target group weighted forward만 가능). 그래서 NLB + EC2 HAProxy 조합으로 우리가 통제 가능한 layer를 추가했다.

최종 구조는 **CloudFront (외부 진입) → NLB (L4) → EC2 HAProxy (L7 + runtime 조정 가능) → EKS** 4단으로 좀 복잡하지만, 각 layer가 명확한 역할을 한다.

### Q3. AZ 전략 — 단일 AZ vs Multi-AZ

| 대안 | 장점 | 단점 |
|---|---|---|
| 단일 AZ | 비용 ↓ (NAT 1대), 단순 | AZ 죽으면 전체 down |
| **Multi-AZ (선택)** | HA, AWS 권장 | NAT GW 2배, cross-AZ 트래픽 비용 |

Multi-AZ는 AWS의 표준 권장 사항이다. 단일 AZ는 비용이 절반 (NAT 1대)이지만, AZ 자체가 죽으면 전체 서비스가 멈춘다. AZ 장애는 빈도가 낮지만 (연 0.01% 수준), 일단 발생하면 서비스 전면 중단이라 critical 워크로드는 무조건 multi-AZ다. **학습 환경에서도 multi-AZ 함정 (cross-AZ 트래픽 비용, NAT GW 중복 비용)을 직접 경험해보는 게 중요**해서 multi-AZ를 선택했다.

---

## 💡 왜 이걸 선택했나

종합하면 우리 AWS 측 설계의 진짜 이유는 네 가지다.

**첫째, VPN은 빠른 PoC + 학습 가치**다. Direct Connect는 신청부터 회선 인입까지 수 주 걸리고 월 $500+이라 학습 환경엔 부적합하다. VPN으로 1일에 양방향 연결을 검증할 수 있었고, IPsec/NAT-T/터널 등 네트워크 깊이도 학습할 수 있었다.

**둘째, NLB + EC2 HAProxy 이중 구조는 통제력 + 비용의 균형**이다. NLB만 두면 L7 라우팅을 못 하고 Host header도 못 본다. ALB로 가면 L7은 되지만 우리 burst 패턴 (runtime weight 조정)과 안 맞는다. EC2 HAProxy는 온프레와 동일한 도구라 **운영 일관성**도 챙긴다.

**셋째, Multi-AZ는 AWS 표준 + 학습 가치다.** 진짜 운영급은 무조건 multi-AZ고, 학습 환경에서도 multi-AZ 함정 (NAT GW 2배 비용, cross-AZ 데이터 비용)을 직접 경험해보는 게 중요하다. 단일 AZ로 갔다가 나중에 multi-AZ로 옮기는 마이그레이션 비용이 훨씬 크다.

**넷째, 모든 워크로드를 Private Subnet에 배치**해 외부 공격 표면을 최소화했다. EC2/EKS는 public IP 없이 NAT GW만 통해 outbound. 유일한 외부 진입점은 NLB (public)뿐. 이건 AWS Well-Architected Framework의 기본 패턴이다.

---

## 💰 비용 분석 (월간 USD)

| 자원 | 단가 | 사용량 | 월 비용 |
|---|---|---|---|
| **VPN Connection** | $0.05/시간 | 720h | **$36** |
| **NAT Gateway × 2** | $0.045/시간 + 데이터 처리비 | 720h × 2 | **$66** |
| **EC2 t3.micro × 2** | $0.0104/시간 (서울) | 720h × 2 | **$15** |
| **NLB** | $0.0225/시간 + LCU | 720h | **$16** |
| **Route 53** | $0.50/zone/월 | 1 | **$0.5** |
| **소계 (Phase 1-2)** | | | **~$135 (₩17만)** |

이 비용 구조에서 가장 큰 비중은 **NAT GW** (월 $66)다. NAT GW는 시간당 $0.045인데, AZ별로 1대씩이라 2배가 된다. 게다가 데이터 처리비 (GB당 $0.045)가 따로 붙어서, outbound 트래픽이 많으면 더 늘어난다. **NAT GW 비용 절감 = VPC Endpoint 도입**이 정석이다 (S3/ECR 트래픽은 endpoint로 우회).

Burst 활성 시 추가 비용은 EKS 제어 평면 $72 + Karpenter Spot 노드 (시간당 ~$0.029) + RDS replica $12 등이 더해진다. 풀 phase 1-5 운영 시 약 **$230/월 (₩30만)** 수준이다.

### 100% AWS로 했을 때 비교

같은 워크로드를 100% AWS로 가져가면 어떻게 될까. EC2 m5.xlarge × 4 (워커 대체) $553, m5.large × 3 (CP 대체) $207, EBS gp3 6TB (Ceph 대체) $480, RDS HA $98, 기타 인프라 $200 정도로 **월 $1,600+ (₩212만+)** 수준이다.

→ **하이브리드가 약 70% 절감**이다. 단, 초기 투자금 ₩1660만 회수 ~5년 가정.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 양방향 통신 (VPN) | 인터넷 경유 latency (6ms) |
| Multi-AZ HA | NAT GW 2배 비용 |
| 통제 가능 (EC2 HAProxy) | 직접 운영 부담 |
| 정적 IP (NLB) | L7 라우팅 우회 (HAProxy 추가) |
| 평시 EKS 0 | Karpenter 학습 필요 |

가장 큰 trade-off는 **"비용 vs 통제"**다. EKS 관리형 제어 평면 + ALB + Karpenter native만 쓰면 운영 부담이 거의 0이지만, 우리 burst 패턴을 위해 EC2 HAProxy를 추가하면서 운영 layer가 늘었다. 통제력은 얻었지만 그만큼 직접 관리할 게 많아진다.

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **VPN 양쪽 터널 끊김** | 온프레↔AWS 단절 → RDS lag | pfSense IPsec 재연결 |
| **NAT GW 1대 죽음** | 해당 AZ outbound 끊김 | 다른 AZ NAT으로 RT 변경 |
| **EC2 HAProxy 1대** | 다른 1대가 NLB로 받음 | NLB 자동 health check |
| **NLB** | EKS 진입 불가 | AWS 책임 (관리형) |
| **RDS replica** | EKS Pod read 못함 | RDS reboot 또는 다른 replica |

VPN 양쪽 터널이 다 끊기는 게 가장 위험한 시나리오다. 우리 VPN은 active-active로 2개 터널이 동시 작동하므로, 한쪽만 끊겨도 다른 쪽이 그대로 트래픽을 받는다. 둘 다 끊기려면 (1) AWS VPN 서비스 전체 장애, (2) ER605/pfSense 동시 죽음, (3) 양쪽 NAT-T 동시 차단 같은 드문 케이스다.

NAT GW 1대가 죽는 케이스는 AZ별로 1대씩이라 그 AZ만 outbound가 끊긴다. 그 AZ의 EC2/EKS도 인터넷 못 나가니 영향이 있지만, 다른 AZ는 정상. Route Table을 수동으로 다른 AZ NAT으로 임시 변경하면 회복된다.

---

## 🚀 확장 가능성

### Option A: VPC Endpoint 도입 ⭐ 비용 절감 명확

NAT GW를 통해 S3/ECR로 나가는 트래픽을 VPC Endpoint로 우회시키면 데이터 처리비가 거의 0이 된다. Gateway endpoint (S3, DynamoDB)는 무료고, Interface endpoint (ECR 등)는 endpoint당 월 $7 정도다. 월 100GB+ S3 트래픽 환경이면 ROI가 명확하다.

- 💰 **비용 절감**: NAT 데이터비 GB당 $0.045 → 0
- 🎯 **추천 시점**: 월 100GB+ S3/ECR 트래픽 시

### Option B: Direct Connect 도입

전용선이라 latency가 ~1ms 수준으로 떨어지고 SLA 99.99%다. 월 $500+이지만, 진짜 운영 + 트래픽 100Mbps+ 환경이면 검토 가치 있다.

- 🎯 **추천 시점**: 트래픽 100Mbps 이상 또는 SLA 요구

### Option C: Transit Gateway

VPC를 3개 이상 운영하거나 다른 사이트와도 연결할 때 hub-and-spoke 패턴이 단순화된다. 우리는 VPC 1개라 아직 의미가 적다.

### Option D: Multi-region

진짜 글로벌 운영 + DR이 필요할 때 다른 region (예: us-west-2)에 같은 VPC 복제. 비용 2배지만 지리적 DR 확보.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| NAT 데이터비 월 $50+ | A (VPC Endpoint) ⭐ 가장 가성비 |
| VPN 트래픽 자주 100Mbps+ | B (Direct Connect) |
| 다른 팀 VPC 연결 | C (Transit Gateway) |
| 글로벌 사용자 | D (Multi-region) |

---

## 🔗 다른 파트와의 연결

이 AWS 인프라는 burst 아키텍처의 기반이 된다. `04-burst-architecture.md`는 이 인프라 위에서 어떤 흐름으로 burst가 동작하는지 설명한다. `data-storage/06-rds-replication.md`는 RDS replica가 VPN 위에서 어떻게 동작하는지 다룬다. 보안 측면에선 `security/04-aws-waf-cloudfront.md`가 외부 진입점 보호를 담당한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Direct Connect 안 쓰고 VPN 한 이유는?**

A. 세 가지입니다. **학습 환경엔 비용이 부적합**합니다 (월 $500+). **VPN은 1일 PoC가 가능**한 반면 Direct Connect는 회선 신청부터 인입까지 수 주 걸립니다. **우리 워크로드 트래픽이 작아 6ms latency로 충분**합니다. 진짜 운영 + 100Mbps+ 트래픽이면 Direct Connect 권장입니다.

**Q2. NLB + EC2 HAProxy 이중 구조 왜요?**

A. **NLB는 L4라 Host header를 못 봅니다**. 그래서 그 뒤에 L7 라우팅이 가능한 컴포넌트가 필요합니다. ALB로도 가능하지만, **우리 burst 패턴 (Lambda가 HAProxy admin socket에 socat으로 weight 변경)이 ALB와 안 맞아서** 직접 통제 가능한 EC2 HAProxy를 선택했습니다. 운영 일관성 (온프레와 같은 HAProxy)도 챙기는 부수 효과가 있죠.

**Q3. NAT Gateway 비용이 비싼데 줄일 방법은?**

A. 세 가지가 있습니다. **VPC Endpoint로 S3/ECR 트래픽 우회 (Gateway endpoint는 무료)**가 가장 효과적이고, **NAT Instance (직접 EC2)로 대체**하면 저렴해지지만 HA를 직접 구현해야 합니다. 또는 **AZ 하나 죽일 거면 NAT 1개로 줄임** (HA 포기). 학습 목적이라 1개 줄여도 됩니다만, multi-AZ 학습이 우선이라 그대로 뒀습니다.

**Q4. VPN 6ms인데 PXC ↔ RDS replication 지연 영향은?**

A. **binlog replication은 비동기라 지연 OK**입니다. RDS는 PXC binlog를 약간 늦게 받지만 (몇 초 이내), 그게 EKS Pod의 read에는 영향 없습니다. EKS Pod이 RDS 조회 시 같은 region 내라 1ms 이하고, 6ms latency는 온프레에서 RDS 조회 시에만 영향입니다.

**Q5. 강의장 NAT 뒤라 ER605 ISP IP 사용 안 되는데 VPN 어떻게요?**

A. **pfSense가 NAT-T (NAT Traversal)를 활성화**해서 UDP 4500으로 IPsec을 encapsulation합니다. ER605도 NAT-T 통과를 막지 않아서 (ALG 옵션 끔), 사설 IP 뒤에서도 동작합니다. 다만 Route 53 Health Check (Phase B) 같은 inbound 트래픽은 못 받아 fallback 일부 기능이 강의장에선 제한적입니다.
