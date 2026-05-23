# 04. Burst 아키텍처

> ⭐ **한 줄 요약**: 온프레 부하가 임계치에 도달하면 **Prometheus → AlertManager → Lambda → Route 53 weight 변경** 흐름으로 트래픽 일부가 AWS NLB로 가고, EKS HPA가 Pod 늘리면서 Karpenter가 자동으로 Spot 노드를 띄운다. EKS Pod은 **온프레 PXC + Redis**를 전용선으로 공유 사용 — single source of truth 유지. 평시 0 노드라 비용 거의 0, burst 시점만 과금.

---

## 🎯 우리가 한 선택

Burst 아키텍처의 핵심은 **사람 개입 없이 트래픽 폭증에 자동 대응**하는 거다. 평시엔 비용 0 (Karpenter가 노드를 안 띄움), burst 시점에만 자동 확장. **데이터 layer는 분기하지 않고 온프레 single source 유지** — EKS Pod이 전용선으로 온프레 ProxySQL + Redis를 그대로 쓴다.

### 트래픽 흐름 (12단계)

```
[1] 온프레 ticket-app 부하 ↑
        │ (Prometheus가 30s 간격 scrape)
        ▼
[2] Prometheus rule: cpu_usage > 80% for 5m
        │ alert firing
        ▼
[3] AlertManager
        │ matchers burst_trigger="true" → aws-burst receiver
        │ webhook
        ▼
[4] API Gateway HTTP API
        ▼
[5] Lambda burst-trigger
        │ Route 53 weight: aws 0 → 30
        ▼
[6] Route 53 weighted record (TTL 60s)
        │ DNS 캐시 만료 후
        ▼
[7] 클라이언트 일부가 AWS NLB로 라우팅
        ▼
[8] NLB → EC2 HAProxy → EKS Pod
        │
        │ HPA: CPU > 70% → replicas 2 → 16
        ▼
[9] Karpenter: Pending Pod 감지 → m5.large Spot Node 자동 생성 (40초)
        ▼
[10] EKS Pod 가동
        │
        ├── DB → aws-ticket-proxysql → 전용선/VPN → 온프레 ProxySQL (172.16.23.56) → PXC ⭐ 공유
        └── Cache → 전용선/VPN → 온프레 Redis (172.16.23.59 master) ⭐ 공유
        │
        │ (RDS는 등장 X — OLAP path와 분리)
        ▼
[11] 응답 → 사용자
        ▼
[12] 부하 진정 → alert resolve → 자동 weight 복귀 → Spot Node 자동 회수
```

### 데이터 layer — single source 유지

```
[온프레 사용자] ──→ 온프레 ticket-app ──┐
                                        ├─→ ⭐ 온프레 Redis (172.16.23.59) ─ 캐시 단일
                                        ├─→ ⭐ 온프레 ProxySQL → PXC ─ DB 단일
[AWS burst 사용자] ──→ EKS ticket-app ──┘   (전용선 통해)
```

각 컴포넌트의 역할:

| 컴포넌트 | 설정 |
|---|---|
| Prometheus alert rule | `cpu_usage > 80% for 5m` |
| AlertManager route | `burst_trigger="true"` 매처 → aws-burst receiver |
| Webhook | https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com/ |
| Lambda runtime | Python 3.x + IAM role with route53:ChangeResourceRecordSets |
| Route 53 | weighted A record (onprem 70 / aws 30 또는 0/30) |
| EKS HPA | min 2, max 16, CPU 70% |
| Karpenter NodePool | m5.large/xlarge spot, max 10 nodes |
| **EKS DB endpoint** | **aws-ticket-proxysql (cluster) → 172.16.23.56 (PXC)** ⭐ |
| **EKS Redis endpoint** | **172.16.23.59:6379 (온프레 master)** ⭐ |
| RDS Replica | **이 path엔 등장 X** — OLAP 분리 (`data-storage/06-rds-replication.md`) |

### Phase B Fallback — 다른 메커니즘

Burst와 별도로 **Route 53 Health Check 기반 fallback**도 구축돼 있다. 이건 burst가 "부하 분산"이라면, Health Check는 "DR 모드"다. 온프레가 자체적으로 죽으면 (예: edge VIP 죽음), Route 53이 외부에서 30초마다 health 폴링하다가 3번 연속 실패하면 onprem record를 unhealthy로 마킹해 weighted routing에서 자동 제외. 결과는 100% AWS 라우팅.

```
[온프레 자체 장애]
        │ (R53 외부 checker가 30s마다 폴링)
        ▼
[3번 연속 실패 (90초)]
        │
        ▼
[onprem record unhealthy 마킹]
        │ weighted routing에서 자동 제외
        ▼
[100% AWS로 라우팅]
```

Burst와 Phase B의 차이는 **트리거 주체**다. Burst는 우리 Prometheus가 결정하고 (능동적), Phase B는 AWS Route 53이 결정한다 (수동적). 두 메커니즘이 상호 보완.

---

## ⚡ "왜 EKS Pod도 온프레 Redis/PXC를 쓰나" (핵심 설계 결정)

burst 아키텍처에서 가장 헷갈리는 부분이다. EKS Pod이 AWS 안에 떴는데 DB/Redis는 온프레로 보낸다. 처음엔 비효율로 보일 수 있어서 정리한다.

### 옵션 비교

| 데이터 layer | EKS가 쓰는 곳 | 장점 | 단점 |
|---|---|---|---|
| **온프레 통일 (선택)** | 전용선 → 온프레 PXC + Redis | **single source of truth, 캐시 invalidation 일관** | 전용선 의존 (단절 시 일시 영향) |
| AWS 별도 Redis + RDS read | EKS 내 ElastiCache + RDS Replica | EKS 자체 완결 | 캐시 분기 → invalidation 어려움, 데이터 정합성 위험 |
| 혼합 (read는 AWS, write는 온프레) | 복잡 | 일부 read latency ↓ | 운영 복잡도 ↑↑ |

### 왜 통일했나

**1. 캐시 일관성** — 사용자 X가 좌석 A4 예약하면 PXC INSERT + Redis DEL이 발생한다. 만약 EKS가 별도 Redis를 쓰면 그 invalidate 신호를 못 받아서 stale cache가 남고, 다른 사용자가 A4를 다시 클릭하는 충돌이 발생한다.

**2. 운영 단순함** — 캐시 한 벌, DB 한 벌. 모니터링/백업/failover 모두 한 곳만 보면 된다.

**3. 전용선 가정이면 latency 차이 미미** — EKS Pod → 전용선 → 온프레 PXC = 2~3ms. EKS Pod → 같은 VPC RDS = 1ms. 차이 1~2ms는 사용자 체감 X.

**4. burst의 본질이 compute 확장이지 data 확장이 아님** — burst trigger는 "사용자 connection이 너무 많아서 Pod 부족" 때문이다. Pod만 추가하면 끝. DB capacity는 별개 문제고 별개 솔루션 (Read Replica, sharding 등).

### 그럼 RDS Read Replica는 어디 쓰나?

**OLAP 전용**이다. 관리자 대시보드 (매출, 점유율), Grafana 분석 패널이 RDS에서 read한다. burst path와는 완전 분리.

```
[운영 path - burst 포함] ──→ 온프레 PXC + Redis
[분석 path - admin/Grafana] ──→ RDS Replica
```

두 path가 독립이라 RDS 죽어도 운영 영향 0, 온프레 죽어도 분석은 마지막 sync까지 가능. 자세한 건 `data-storage/06-rds-replication.md`.

---

## 🔍 고려한 대안들

### Q1. 트래픽 분산 방식 — Route 53 weighted vs Global Accelerator vs DNS round-robin

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Route 53 weighted (선택)** | 비율 조정 자유, health check 통합 | DNS 캐시 (TTL) 지연 | ★★★★★ |
| Global Accelerator | Anycast IP, latency 기반 | 비용 ↑ ($18/월) | ★★ |
| DNS round-robin | 단순 | 비율 조정 어려움, health check X | ★ |

Route 53 weighted는 비율 자유 + Health Check 통합. TTL 60초로 1분 내 전환 보장.

### Q2. 트리거 — Prometheus + Lambda vs CloudWatch + Lambda vs 수동

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Prometheus → Lambda (선택)** | 온프레 메트릭 직접, 정밀 조건 | webhook 인증 추가 필요 | ★★★★★ |
| CloudWatch + Lambda | AWS native | 온프레 메트릭 → CloudWatch 전송 필요 | ★★★ |
| 수동 Lambda | 단순 | 자동화 X | ★ |

CloudWatch는 AWS 자원 메트릭만. 온프레 메트릭을 CloudWatch로 보내려면 별도 인프라 (AMP 등) + 비용 + latency. Prometheus가 직접 결정하는 게 정확하고 저렴.

### Q3. Burst 노드 — EKS Karpenter Spot vs EC2 ASG vs ECS Fargate

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **EKS Karpenter Spot (선택)** | 빠른 provisioning (40초), Spot 75% 할인 | Spot interruption (2분 notice) | ★★★★★ |
| EC2 ASG (Cluster Autoscaler) | 표준, 안정 | scale 느림 (분), 단일 타입 | ★★★ |
| ECS Fargate | 서버리스, 노드 관리 X | EKS와 다른 API | ★★ |
| EKS On-Demand | 안정성 ↑ | Spot 75% 절감 포기 | ★★★ |

Karpenter는 직접 EC2 API 호출 → 40초~1분 만에 노드 ready. CA는 ASG warm pool + boot로 5분. burst 응답성 차이 큼.

### Q4. EKS Pod의 데이터 endpoint — 온프레 직결 vs AWS 별도

(위 "왜 EKS Pod도 온프레 Redis/PXC를 쓰나" 섹션 참고)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **온프레 직결 (선택)** | single source, 캐시 일관, 단순 | 전용선 의존 | ★★★★★ |
| AWS 별도 (ElastiCache + RDS) | EKS 자체 완결 | invalidation 복잡, 데이터 정합성 위험 | ★★ |
| 혼합 (read AWS, write 온프레) | 일부 latency ↓ | 운영 복잡도 ↑↑ | ★ |

---

## 💡 왜 이걸 선택했나

### 핵심 5가지

**첫째, Prometheus 트리거 = 온프레 정밀 조건 보장.** CloudWatch는 AWS 자원만 보고, 온프레 메트릭을 가져오려면 추가 인프라 필요. 우리는 이미 Prometheus를 온프레에서 정밀하게 운영 중이라 AlertManager webhook으로 직접 Lambda 호출하는 패턴이 가장 정확. 5분 sustained 조건으로 단발성 spike 무시.

**둘째, Spot 75% 할인.** Burst는 일시적이라 spot interruption (2분 notice)을 충분히 허용. m5.large 기준 $0.096 → $0.029. Karpenter가 interruption 자동 재배치도 해줌.

**셋째, Karpenter 40초 provisioning.** CA가 5분 걸리는 일을 40초에 끝냄. burst 시점은 사용자가 응답 지연 느끼는 순간이라 차이가 사용자 경험에 직접 영향.

**넷째, 데이터 single source = 정합성 보장.** EKS Pod이 온프레 PXC + Redis를 쓰니 invalidate가 자연히 cluster-wide. 별도 캐시 layer로 데이터 분기 안 일어남. burst가 정합성 risk 없이 안전하게 동작.

**다섯째, OLTP/OLAP 분리.** 운영 path (burst 포함)에선 PXC + Redis만 쓰고, 분석 path는 RDS Replica로 완전 격리. 무거운 분석 쿼리가 운영 영향 0.

---

## 💰 비용 분석

### 평시 (burst 미발생)

| 자원 | 월 비용 |
|---|---|
| EKS Cluster (제어 평면) | $72 |
| RDS db.t4g.micro (OLAP 전용) | $9.4 |
| Lambda (요청 거의 없음) | $0 |
| Route 53 hosted zone + health check | $1 |
| **소계** | **~$82/월** |

EKS 제어 평면이 가장 큰 비중. RDS는 OLAP만 받으니 미니멀 사이즈.

### Burst 1시간 발생 시 추가

| 자원 | 단가 | 추가 비용 |
|---|---|---|
| Karpenter Spot m5.large × 3 | $0.029/h × 3 × 1h | ~$0.09 |
| 데이터 전송 (cross-zone + 외부) | $0.01/GB × ~10GB | $0.1 |
| 전용선 데이터 (EKS ↔ 온프레) | (전용선 정액제 가정) | 0 |
| **burst당** | | **~$0.2** |

월 100시간 burst라 가정 시 **연간 ~$240 추가**. 자동 burst 인프라치고 매우 저렴.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 자동 burst (수동 개입 0) | 트리거 잘못되면 false burst |
| Spot 절감 75% | interruption (2분 notice) |
| Karpenter 빠른 provisioning | 학습 곡선 |
| 이중 fallback (R53 HC) | 1분 정도 fallback 지연 |
| **데이터 single source — 정합성 보장** | **전용선 의존 (단절 시 일시 영향)** |
| **OLTP/OLAP 분리** | 컴포넌트 많음 |

가장 우려되는 trade-off는 **전용선 의존**. EKS Pod이 온프레 PXC/Redis 의존하니 전용선 끊기면 burst path가 일시 마비. 다만 (1) 전용선 자체 SLA 높음 (99.9%+), (2) 단절 빈도 낮음, (3) 단절 시에도 온프레 정상이면 사용자는 온프레 path로 정상 응답. 큰 사고로 이어지진 않음.

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **Prometheus 죽음** | alert 자체 발생 X → burst 미동작 | sys2 추가 시 HA replica |
| **AlertManager 죽음** | webhook 못 보냄 | sts replicas 3 (이미 spec) |
| **Lambda 코드 에러** | R53 weight 변경 실패 | CloudWatch 로그 + alarm |
| **R53 API 일시 장애** | DNS 캐시 풀릴 때까지 옛 weight 유지 | TTL 60s라 자연 회복 |
| **EKS 노드 spot interruption** | Pod evict (2분 notice) → 다른 노드 자동 | Karpenter 자동 |
| **전용선 단절** | EKS Pod이 PXC/Redis 못 봄 → 응답 fail | 1) 즉시 weight onprem 100 복귀, 2) 전용선 복구 |
| **온프레 PXC 죽음** | EKS Pod write 실패 (burst path 마비) | PXC HA 복구 + ProxySQL retry |
| **온프레 Redis master 죽음** | EKS Pod cache MISS 폭증 → PXC 부담 ↑ | Sentinel 자동 failover (수초), EKS env 갱신 필요 ⚠️ |

**가장 critical SPoF는 Prometheus 단일** — 현재 sys1 단일 노드라 sys1이 죽으면 burst 자체가 발동 안 됨. **sys2 추가가 시급**.

Redis master failover 시 client (EKS Pod)는 stale IP를 가지고 있을 수 있음. **Sentinel-aware client로 코드 개선이 운영 grade 필수 작업**. 데모용 현재는 master IP 하드코딩으로 동작.

---

## 🚀 확장 가능성

### Option A: ⭐ Multi-cluster ArgoCD (EKS도 GitOps 관리)

현재는 ArgoCD가 온프레 K8s만 관리. EKS는 manual deploy. 새 코드 push 시 온프레만 업데이트되고 EKS는 옛 버전 그대로 → **Burst 시점에 EKS Pod이 옛 버전을 서빙**할 위험. bastion ArgoCD에 EKS cluster 등록 + kustomize overlay 구조로 재편성. 4~6시간 작업.

### Option B: Sentinel-aware Redis client로 ticket-app 개선

현재 ticket-app은 단순 `redis.Redis(host=...)` 사용. failover 시 stale IP. `redis.sentinel.Sentinel(...)` 패턴으로 변경하면 자동 master discovery. 운영 grade 필수.

### Option C: Karpenter NodePool 다양화

현재 m5.large 단일 spot pool. m5.large + m5a.large + m6i.large + m5.xlarge 4개 옵션으로 spot 가용성 ↑. interruption 회복성 ↑.

### Option D: Argo Rollouts (canary/blue-green)

새 버전을 EKS에 5%만 먼저 배포, Prometheus 메트릭 기준으로 안전 확인되면 100%로 점진. 잦은 배포 + 안전성.

### Option E: 데이터 layer DR — 온프레 PXC down 시 RDS promote

진짜 운영급 DR. 온프레 PXC가 죽으면 RDS Replica를 promote해서 새 master로. RTO ~30분 (DNS 변경 + 앱 reconfig). 자동화 스크립트 + Lambda + Route 53 변경.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 코드 한쪽만 옛 버전 | A (multi-cluster ArgoCD) ⭐ |
| Redis failover 시 burst 마비 | B (Sentinel client) ⭐ |
| spot interruption 잦음 | C |
| 잦은 배포 안전성 | D |
| 진짜 운영급 DR | E |

---

## 🔗 다른 파트와의 연결

이 burst 아키텍처는 여러 파트와 맞물려 있다. `03-aws-hybrid.md`는 burst가 동작하는 AWS 인프라 기반을 다룬다. `05-observability-design.md`는 Prometheus + AlertManager 라우팅을 자세히 설명. 데이터 측면에서 `data-storage/05-pxc-redis.md`가 EKS와 공유되는 PXC/Redis를 설명하고, `data-storage/06-rds-replication.md`는 **이 burst path와 분리된 RDS의 OLAP 전용 역할**을 다룬다. 보안은 `security/06-burst-trigger-security.md`에서 webhook 인증 (현재 미구현).

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. EKS Pod이 떴는데 왜 RDS를 안 쓰고 온프레 PXC를 써요?**

A. 세 가지 이유입니다. **첫째, single source of truth** — EKS도 온프레 PXC + Redis를 쓰면 캐시 invalidation이 cluster-wide로 일관됩니다. 별도 캐시 두면 stale 위험. **둘째, 전용선 가정이라 latency 차이 미미** — EKS Pod → 전용선 → PXC = 2~3ms, vs RDS = 1ms. 거의 무의미. **셋째, OLTP/OLAP 분리** — RDS는 분석 전용으로 격리해서 OLAP 쿼리가 OLTP에 영향 0이 되도록 설계했습니다.

**Q2. Burst는 read heavy 때문에 하는 건가요?**

A. **아니에요**. burst trigger는 **사용자 connection이 많아서 Pod compute가 부족할 때** 발동합니다 (CPU > 80%, queue > 1000 등). read heavy든 write heavy든 무관하게 Pod이 처리 못하면 burst. 데이터 layer 부하 분산은 별개 layer 문제 (Redis cache + PXC reader가 처리).

**Q3. 100만 동접 시나리오도 burst로 처리 가능?**

A. **아니에요**. 우리 인프라 한계는 약 5천~3만 동접입니다. 100만 동접은 (1) 대기열 시스템으로 99% 차단, (2) CDN으로 정적 자산 edge 캐시, (3) DB 샤딩 — 이런 별개 아키텍처가 필요. burst는 **티켓 오픈 같은 5천~3만 spike** 대상입니다.

**Q4. Burst trigger가 false positive 내면?**

A. 세 가지 완화 장치. **비용 영향 작음** — Spot 75% 할인으로 false burst 1시간 = $0.03. **resolve_timeout** — alert 해소되면 자동 weight 복귀. **5분 sustained 조건** — 단발성 spike 무시.

**Q5. 전용선 끊기면 EKS Pod은?**

A. **EKS Pod이 온프레 PXC/Redis 못 봄 → 응답 fail**. 즉시 Route 53 weight를 onprem 100으로 복귀시켜 burst path 차단해야 합니다 (수동 또는 자동 alert로). 전용선 복구 후 자동 catch-up. 이게 전용선 의존의 trade-off지만, 단절 빈도 매우 낮아 사업적으로 수용 가능.

**Q6. Karpenter Spot이 interruption 받으면?**

A. **AWS가 2분 전 termination notice**. Karpenter가 감지해서 다른 spot/on-demand로 자동 재배치. Pod evict + 재시작. 사용자 일시 5xx 가능, 재시도 OK. SLA critical하면 mixed (spot+on-demand 50:50).

**Q7. AlertManager → Lambda webhook 인증?**

A. **솔직히 현재 무인증입니다 (학습 환경)**. 외부자가 URL 알면 false burst 가능. Phase 6 우선 작업 — API Gateway API key 또는 HMAC 인증 추가 예정. 자세한 건 `security/06-burst-trigger-security.md`.

**Q8. Phase B (R53 Health Check)와 burst trigger 차이는?**

A. **트리거 주체와 시나리오가 다름**. **Burst**는 우리 Prometheus가 "온프레 부하 ↑" 감지하면 트래픽 일부를 AWS로 보냄 (성능 보강). **Phase B**는 AWS Route 53이 외부에서 30초마다 ping해서 온프레가 죽었다고 판단하면 100% AWS (DR 모드). 보완적 안전망.

**Q9. EKS Pod이 Sentinel-aware client가 아니라던데?**

A. **맞아요, 현재 단순 Redis client + master IP 하드코딩**입니다. Redis master failover 시 stale IP로 connection 실패 가능. 데모용으론 동작하지만 **운영 grade는 `redis.sentinel.Sentinel(...)` 패턴으로 코드 개선 필수**. Phase 6 작업 중 하나.

**Q10. 강의장 NAT 환경에서 Phase B는 어떻게요?**

A. **강의장에선 health check가 영구 unhealthy** — R53 외부 checker가 NAT 뒤를 못 뚫음. 결과적으로 100% AWS 라우팅이라 사실상 강제 burst. 그래서 강의장에선 cloudflared로 외부 시연 URL 별도 운영. 실제 운영 환경 (ER605 = ISP 직결)이면 정상 fallback.
