# 09. AWS 하이브리드 클라우드

> Layer 4 / 학습 3일

---

## 1) 왜 하이브리드인가

| 옵션            | 장점                 | 단점                              | 우리 시나리오               |
| --------------- | -------------------- | --------------------------------- | --------------------------- |
| **풀 온프레**   | 비용 0               | Burst 처리 불가, 글로벌 latency ↑ | 평상시엔 OK, 티켓 오픈 시 X |
| **풀 클라우드** | 무한 확장, 글로벌    | 비용 ↑ (평소에도 결제)            | 비효율                      |
| **하이브리드**  | 평소 0, burst만 결제 | 운영 복잡                         | ✅                          |

---

## 2) AWS Edge 패턴 vs Cloud Bursting

### AWS Edge (우리 채택)

```
[글로벌 사용자] → [Route 53] → AWS NLB
                             ↓
                          [EC2 HAProxy × 2]
                             ↓
                     VPN ───→ 온프레 K8s
```

- AWS는 "관문" 역할
- 백엔드 (앱, DB)는 온프레
- 글로벌 latency 개선 (CloudFront 추가 시)

### Cloud Bursting (보조)

```
[부하 폭증 감지]
    ↓
[EventBridge → Lambda]
    ↓
[Karpenter → EKS Spot 워커 추가]
    ↓
[ArgoCD → 워크로드 sync]
```

- 평소 EKS 빈 클러스터
- 부하 시 Spot 인스턴스 자동 추가
- 부하 감소 후 자동 종료

**우리는 Edge + Bursting 결합.** 평소 트래픽도 AWS 거치고, burst 시 추가 처리만 EKS로.

---

## 3) Site-to-Site VPN vs Direct Connect

|               | **VPN**          | Direct Connect |
| ------------- | ---------------- | -------------- |
| 연결          | 인터넷 + IPsec   | 전용 회선      |
| 비용          | $36/월           | $200+/월       |
| 속도          | ~100Mbps         | 1~10Gbps       |
| latency       | ~30ms            | ~5ms           |
| **우리 선택** | ✅ (학습 + 비용) | -              |

학습 환경엔 VPN 충분. 운영 환경에선 트래픽 양에 따라 Direct Connect.

---

## 4) AWS NLB + EC2 HAProxy

### 왜 NLB?

- L4 LoadBalancer (TCP)
- TLS termination 가능
- 정적 IP (Elastic IP 연결)
- 대용량 트래픽 처리 (수십만 RPS)

### 왜 EC2 HAProxy까지?

NLB만으로도 백엔드 직접 라우팅 가능. 그런데:

- **TLS 인증서 관리** — ACM 보다 HAProxy 내부에서 처리하고 싶을 때
- **L7 라우팅** — URL path 기반 분기 (`/api/v1` vs `/admin`)
- **세션 sticky** — JWT 검증 후 같은 노드로
- **L7 로깅** — HAProxy stats 페이지

→ NLB는 L4, EC2 HAProxy가 L7. 두 단계 LB.

```
인터넷 → [NLB :443] → [HAProxy :443] → [VPN] → 온프레 K8s
```

### HAProxy × 2 (Active-Active)

```
[NLB Target Group]
  ├─ EC2 HAProxy-1 (AZ a)
  └─ EC2 HAProxy-2 (AZ b)
```

Keepalived 안 씀 (NLB가 헬스체크 + 분산). 두 EC2 모두 트래픽 받음.

---

## 5) EKS + Karpenter

### EKS

K8s를 AWS가 매니지드로 제공. Control Plane은 AWS가 운영, Worker만 우리 책임.

비용: Control Plane $73/월 (24시간) — 평소엔 끄거나 minimal.

### Karpenter vs Cluster Autoscaler

|                          | **Karpenter**          | Cluster Autoscaler |
| ------------------------ | ---------------------- | ------------------ |
| Pod 미스케줄 → 노드 추가 | 1~2분                  | 5~10분             |
| 인스턴스 타입            | 자동 선택 (cheapest)   | 수동 설정          |
| Spot 통합                | 강력                   | 가능               |
| **선택 이유**            | 빠른 burst + Spot 자동 | -                  |

Karpenter NodePool 예:

```yaml
spec:
  template:
    spec:
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [c, m, r]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot] # Spot만
```

Spot 인스턴스는 정가의 30~70%. AWS가 회수할 수 있지만 K8s가 Pod 재배치 처리.

---

## 6) RDS Read Replica (Percona binlog → RDS)

```
[온프레 PXC] ── binlog ──→ [AWS RDS MySQL Read Replica]
```

비동기 복제. 글로벌 사용자 SELECT는 RDS로 (edge 효과).

ProxySQL에서 hostgroup 30 (aws_replica)으로 라우팅.

---

## 7) Route 53 Weighted Routing

```yaml
record: api.kosa-tickets.com
  ├─ weight 70: AWS NLB DNS
  └─ weight 30: 온프레 pfSense WAN IP
```

평상시 30/70 분산. Burst 시 100/0 (AWS only)으로 조절.

---

## 8) EventBridge + Lambda Burst 자동화

```
[CloudWatch: NLB Request Count > 5000/min]
    ↓ alarm
[EventBridge rule]
    ↓ trigger
[Lambda function]
    ↓
- Karpenter NodePool size 증가
- Route 53 weight 100/0 변경
```

부하 감지 → 자동 burst → 부하 감소 시 자동 축소.

---

## 9) 비용 분석

### Phase 1 (Day 8): VPC + NLB + EC2 HAProxy

```
VPC, IGW, RT       무료
NAT Gateway        $33/월
NLB                $20/월 + LCU
EC2 t3.micro × 2   $8/월 (free tier 가능)
EBS gp3 20GB × 2   $3/월
─────────────────────────
                   ~$70/월
```

### Phase 2-5 추가 시

```
VPN                +$36/월
RDS db.t3.micro    +$15/월
EKS Control Plane  +$73/월
Karpenter Spot     burst 시간만 결제 (~$1~3/시간)
─────────────────────────
풀 활성             ~$200/월
```

학습 환경 50만원 = ~$370. 풀 활성 2개월 또는 Phase 1만 5개월 가능.

---

## 10) 발표 어필

> _"평상시엔 온프레미스만 운영해 비용이 0에 가깝고, 티켓 오픈 1시간 동안만 AWS Karpenter Spot으로
> burst하여 시간당 $3 미만으로 100배 부하를 처리합니다. EventBridge → Lambda 자동화로 사람 개입 없이
> burst 시작/종료가 이루어지며, Route 53 weighted routing이 트래픽을 동적으로 분산합니다."_

---

## 다음 단원

[`10_모니터링_Prometheus_Grafana.md`](10_모니터링_Prometheus_Grafana.md)
