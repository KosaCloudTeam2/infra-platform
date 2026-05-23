# 04. Burst 아키텍처

> ⭐ **한 줄 요약**: 온프레 부하가 임계치에 도달하면 **Prometheus → AlertManager → Lambda → Route 53 weight 변경** 흐름으로 트래픽 일부가 AWS NLB로 가고, EKS HPA가 Pod 늘리면서 Karpenter가 자동으로 Spot 노드를 띄운다. 평시 0 노드라 비용 거의 0, burst 시점만 과금.

---

## 🎯 우리가 한 선택

Burst 아키텍처의 핵심은 **사람 개입 없이 트래픽 폭증에 자동 대응**하는 거다. 단순히 EKS에 Pod을 띄워두는 게 아니라, 평시엔 비용 0 (Karpenter가 노드를 안 띄움)에서 burst 시점에만 자동으로 확장된다. 이 흐름을 단계별로 보면 11단계가 된다.

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
[4] API Gateway HTTP API (le24sqo79b.execute-api...)
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
[10] EKS Pod이 RDS replica에서 read, 온프레 PXC로 write
        ▼
[11] 부하 진정 후 alert resolve → 자동 weight 복귀 → Spot Node 자동 회수
```

각 컴포넌트의 역할은 다음과 같다.

| 컴포넌트 | 설정 |
|---|---|
| Prometheus alert rule | `cpu_usage > 80% for 5m` |
| AlertManager route | `burst_trigger="true"` 매처 → aws-burst receiver |
| Webhook | https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com/ |
| Lambda runtime | Python 3.x + IAM role with route53:ChangeResourceRecordSets |
| Route 53 | weighted A record (onprem 70 / aws 30 또는 0/30) |
| EKS HPA | min 2, max 16, CPU 70% |
| Karpenter NodePool | m5.large/xlarge spot, max 10 nodes |
| RDS replica | external replica (PXC binlog) |

### Phase B Fallback — 다른 메커니즘

Burst와 별도로 **Route 53 Health Check 기반 fallback**도 구축돼 있다. 이건 burst가 "부하 분산"이라면, Health Check는 "DR 모드"다. 온프레가 자체적으로 죽으면 (예: edge VIP 죽음), Route 53이 외부에서 30초마다 health 폴링하다가 3번 연속 실패하면 onprem record를 unhealthy로 마킹해 weighted routing에서 자동 제외한다. 결과는 100% AWS 라우팅.

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

Burst와 Phase B의 차이는 **트리거 주체**다. Burst는 우리 Prometheus가 결정하고 (능동적), Phase B는 AWS Route 53이 결정한다 (수동적). 두 메커니즘이 상호 보완적으로 동작한다.

---

## 🔍 고려한 대안들

### Q1. 트래픽 분산 방식 — Route 53 weighted vs Global Accelerator vs DNS round-robin

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Route 53 weighted (선택)** | 비율 조정 자유, health check 통합 | DNS 캐시 (TTL) 지연 | ★★★★★ |
| **Global Accelerator** | Anycast IP, latency 기반 | 비용 ↑ ($18/월), Asia 한정 효과 | ★★ |
| **DNS round-robin** | 단순 | 비율 조정 어려움, health check X | ★ |

Route 53 weighted routing은 **비율을 자유롭게 조정 (10:90, 50:50, 70:30 등)** 할 수 있고, Health Check와 통합돼 unhealthy record를 자동 제외한다. 단점은 DNS 캐시 (TTL) 지연으로 즉시 트래픽 전환이 안 된다는 점인데, TTL을 60초로 짧게 설정해 우리는 1분 내 전환을 보장했다.

Global Accelerator는 anycast IP로 글로벌 사용자의 latency를 줄이는 솔루션인데, 우리 사용자가 한국에 집중돼 있어 효과가 적고 월 $18+ 비용이 들어 제외했다. DNS round-robin은 가장 단순하지만 비율 조정이나 health check 통합이 없어 진짜 운영엔 부적합하다.

### Q2. 트리거 방식 — Prometheus + Lambda vs CloudWatch + Lambda vs 수동

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Prometheus → Lambda (선택)** | 온프레 메트릭 직접, 정밀 조건 | webhook 인증 추가 필요 | ★★★★★ |
| CloudWatch + Lambda | AWS native | 온프레 메트릭 → CloudWatch 전송 필요 | ★★★ |
| 수동 Lambda 호출 | 단순 | 자동화 X | ★ |

이건 정말 중요한 결정이었다. CloudWatch + Lambda 패턴이 AWS native라 깔끔해 보이지만, **온프레 메트릭이 CloudWatch에 안 들어간다**는 큰 문제가 있다. Prometheus를 remote_write로 CloudWatch로 보내려면 별도 인프라 (예: AWS Managed Prometheus) + 비용 + 추가 latency가 발생한다.

우리는 그 대신 **온프레 Prometheus가 직접 결정하고 webhook으로 알리는** 패턴을 골랐다. Prometheus rule이 5분 sustained CPU 80%를 감지하면 AlertManager가 webhook을 발사하고, 그게 우리 Lambda를 호출한다. 트리거 정밀도 (5분 sustained, 노이즈 무시)도 높고 비용도 거의 0이다.

### Q3. Burst 노드 — EKS Karpenter Spot vs EC2 ASG vs ECS Fargate

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **EKS Karpenter Spot (선택)** | 빠른 provisioning (40초), Spot 75% 할인 | Spot interruption (2분 notice) | ★★★★★ |
| EC2 ASG (Cluster Autoscaler) | 표준, 안정 | scale 느림 (분), 인스턴스 타입 1개만 | ★★★ |
| ECS Fargate | 서버리스, 노드 관리 X | EKS와 다른 API, 학습 추가 | ★★ |
| EKS On-Demand | 안정성 ↑ | Spot 75% 절감 포기 | ★★★ |

Karpenter는 Cluster Autoscaler (CA)의 차세대 대체품이라 할 수 있다. CA는 ASG를 통해 노드를 생성하니 ASG warm pool 대기 + EC2 boot로 약 5분 걸리는데, **Karpenter는 직접 EC2 API를 호출**해 40초~1분 만에 노드가 ready된다. Burst 응답성 관점에서 차이가 크다.

게다가 Spot 인스턴스로 가면 m5.large가 시간당 $0.096 → $0.029로 **75% 할인**된다. Spot은 AWS가 2분 notice를 주고 회수할 수 있는데, Karpenter가 이걸 자동 감지해서 새 Spot으로 옮긴다. Burst 워크로드 (일시적, stateless)에 spot이 잘 맞는다.

---

## 💡 왜 이걸 선택했나

이 결정들을 종합하면 다섯 가지 핵심 이유로 정리된다.

**첫째, Prometheus 트리거 = 온프레 정밀 조건 보장.** CloudWatch는 AWS 자원만 보고, 온프레 메트릭을 가져오려면 추가 인프라가 필요하다. 우리는 이미 Prometheus를 온프레에서 정밀하게 운영 중이라, AlertManager webhook으로 직접 Lambda를 호출하는 패턴이 가장 정확하고 비용도 거의 0이다. 5분 sustained 조건으로 단발성 spike는 무시하고, 진짜 부하 폭증만 트리거한다.

**둘째, Spot 75% 할인 = 비용 ★★★** 효과. Burst는 일시적이라 spot interruption (2분 notice 후 회수)을 충분히 허용 가능하다. m5.large 기준 $0.096 → $0.029로 75% 절감인데, burst 자주 발생하면 효과가 누적적이다. Karpenter가 interruption 자동 재배치도 해줘서 운영 부담도 적다.

**셋째, Karpenter 40초 provisioning = burst 응답성.** Cluster Autoscaler가 5분 걸리는 일을 Karpenter는 40초에 끝낸다. Burst 시점은 사용자가 실제로 응답 지연을 느끼는 순간이라, 5분 vs 40초 차이가 사용자 경험에 직접 영향을 준다.

**넷째, Phase B 이중 fallback으로 안전망 강화.** Burst가 어떤 이유로 안 됐을 때 (Lambda 실패, AlertManager 죽음 등)에도 Route 53 Health Check가 자동으로 onprem을 제외해 100% AWS로 보낸다. 코드 0줄로 DR 모드를 구현한 셈이다.

**다섯째, 모든 컴포넌트가 관찰 가능 (observability).** Prometheus가 burst trigger 메트릭 자체를 기록하고, Lambda는 CloudWatch로 로그, EKS HPA + Karpenter 메트릭도 수집된다. 사고 시 어디서 문제 났는지 추적 가능하다.

---

## 💰 비용 분석

### 평시 (burst 미발생)

| 자원 | 월 비용 |
|---|---|
| EKS Cluster (제어 평면) | $72 |
| RDS db.t3.micro (replica) | $12 |
| Lambda (요청 거의 없음) | $0 |
| Route 53 hosted zone + health check | $1 |
| **소계** | **~$85/월** |

EKS 제어 평면이 평시에도 $72/월 부과되는 게 가장 큰 비중이다. 이건 EKS 사용의 기본 비용이라 피할 수 없다. (대안은 EKS 안 쓰고 self-managed K8s이지만 그러면 burst 관리 부담 ↑)

### Burst 1시간 발생 시 추가

| 자원 | 단가 | 추가 비용 |
|---|---|---|
| Karpenter Spot m5.large × 3 | $0.029/h × 3 × 1h | ~$0.09 |
| 데이터 전송 (cross-zone + 외부) | $0.01/GB × ~10GB | $0.1 |
| **burst당** | | **~$0.2** |

진짜 burst가 자주 발생해도 (월 100시간이라 가정), **연간 추가 비용은 ~$300 정도**다. 자동 burst 인프라로는 매우 저렴한 수준이고, 트래픽 대응 실패 시 발생할 수 있는 매출 손실/사용자 이탈에 비하면 ROI가 크다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 자동 burst (수동 개입 0) | 트리거 잘못되면 false burst (비용 발생) |
| Spot 절감 | interruption (2분 notice) |
| Karpenter 빠른 provisioning | 학습 곡선 |
| 이중 fallback (R53 HC) | 1분 정도 fallback 지연 |
| 양방향 (트래픽 ↔ DR) | 컴포넌트 많음 (Prometheus + AlertManager + Lambda + R53 + EKS + Karpenter + RDS) |

가장 우려되는 trade-off는 **컴포넌트 수가 많다는 점**이다. 7개 이상의 컴포넌트가 chain으로 동작하니, 어디 하나 죽으면 burst가 안 된다. 그래서 각 컴포넌트의 HA와 모니터링이 중요하고, Phase B fallback이 안전망 역할을 한다.

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **Prometheus 죽음** | alert 자체 발생 X → burst 미동작 | sys2 추가 시 HA replica |
| **AlertManager 죽음** | webhook 못 보냄 | sts replicas 3 (이미 spec) |
| **Lambda 코드 에러** | R53 weight 변경 실패 | CloudWatch 로그 + alarm |
| **R53 API 일시 장애** | DNS 캐시 풀릴 때까지 옛 weight 유지 | TTL 60s라 자연 회복 |
| **EKS 노드 spot interruption** | Pod evict (2분 notice) → 다른 노드 자동 | Karpenter 자동 |
| **RDS replica down** | EKS Pod read 실패 | 다른 RDS 또는 직접 PXC |

Prometheus가 죽으면 burst 자체가 발동 안 한다는 게 가장 critical한 SPoF다. 현재 Prometheus는 sys1 단일 노드라 sys1이 죽으면 burst도 못 한다. **이게 sys2 추가가 시급한 이유 중 하나**고, sys2 추가 시 Prometheus replicas 2 + Thanos sidecar로 HA 확보가 가능하다.

Spot interruption은 AWS가 2분 notice를 주는데, Karpenter가 즉시 다른 spot 또는 on-demand로 자동 재배치한다. 사용자 입장에선 일시적 5xx 응답 가능하지만 (재시도하면 OK), 진짜 운영급 SLA 목표면 mixed strategy (50% spot + 50% on-demand)로 완화 가능하다.

---

## 🚀 확장 가능성

### Option A: ⭐ Multi-cluster ArgoCD (EKS도 GitOps 관리)

현재는 ArgoCD가 온프레 K8s만 관리하고, EKS는 manual deploy다. 그래서 새 코드를 push하면 온프레만 업데이트되고 EKS는 옛 버전 그대로다. **Burst 시점에 EKS Pod이 옛 버전을 서빙**할 위험이 있다.

해결책은 bastion의 ArgoCD에 EKS cluster를 등록하고, git repo를 kustomize overlay 구조로 재편성하는 거다. 같은 git push에 두 cluster가 동기 배포된다. 작업은 4~6시간 정도.

- 🎯 **추천 시점**: burst 자주 발생 + EKS 코드 일관성 중요해질 때

### Option B: Karpenter NodePool 다양화

현재는 m5.large 단일 타입의 spot pool이다. 같은 타입이라 AWS 측 spot 공급이 일시적으로 부족하면 노드 생성이 실패할 수 있다. NodePool에 m5.large + m5a.large + m6i.large + m5.xlarge 4개 옵션을 두면, 그 중 가용한 타입으로 자동 선택해 interruption 회복성이 ↑된다.

- 🎯 **추천 시점**: 단일 타입 interruption 자주 발생할 때

### Option C: ALB로 교체 + WebSocket sticky

우리 현재 NLB + EC2 HAProxy 구조는 WebSocket이나 sticky session에 최적은 아니다. WebSocket 같은 장기 connection 워크로드면 ALB로 가는 게 합리적이다. 다만 우리 runtime weight 패턴은 재구성해야 한다.

### Option D: Argo Rollouts 도입 (canary/blue-green)

새 버전을 EKS에 5%만 먼저 배포하고, Prometheus 메트릭 (에러율, latency)을 기준으로 정상 확인되면 100%로 점진 배포하는 패턴이다. 잦은 배포 + 안전성 ↑이 필요할 때 효과적.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 코드 한쪽만 옛 버전 | A (multi-cluster ArgoCD) ⭐ |
| spot interruption 잦음 | B (NodePool 다양화) |
| WebSocket 워크로드 | C (ALB) |
| 잦은 배포 안전성 ↑ | D (Rollouts) |

---

## 🔗 다른 파트와의 연결

이 burst 아키텍처는 여러 파트와 맞물려 있다. `03-aws-hybrid.md`는 burst가 동작하는 AWS 인프라 기반을 다룬다. `05-observability-design.md`는 Prometheus + AlertManager의 라우팅을 자세히 설명한다. 데이터 측면에서 `data-storage/06-rds-replication.md`는 EKS Pod이 RDS replica를 어떻게 사용하는지 다루고, 보안은 `security/06-burst-trigger-security.md`에서 webhook 인증 (현재 미구현)을 설명한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Burst trigger가 false positive 내면? (실제 부하 아닌데 EKS scale up)**

A. 세 가지 완화 장치가 있습니다. **첫째, 비용 영향이 작습니다** — Karpenter spot이 시간당 $0.029라 false burst 1시간 발생해도 $0.03 정도라 즉시 회수 가능합니다. **둘째, AlertManager의 resolve_timeout 설정**으로 alert가 해소되면 자동으로 weight를 0으로 복귀시킵니다. **셋째, Prometheus rule을 5분 sustained 조건**으로 잡아 단발성 spike는 무시하고 진짜 지속 부하만 트리거합니다.

**Q2. 클라이언트가 DNS 캐시로 옛날 IP를 가지고 있으면?**

A. **TTL을 60초로 짧게** 설정해서 1분 내 전환됩니다. 진짜 즉시 트래픽 분산이 필요하면 R53 weighted 대신 ALB target group weighted (TTL 무시)를 쓸 수 있지만, 우리 demo 환경엔 60s 지연으로 충분합니다.

**Q3. Karpenter Spot이 interruption 받으면 Pod은?**

A. **AWS가 2분 전 termination notice를 보내고**, Karpenter가 그걸 감지해서 다른 spot 또는 on-demand로 자동 재배치합니다. Pod은 evict되고 다른 노드에 재시작됩니다. 사용자 입장에선 일시적 5xx 가능하지만 재시도하면 OK입니다. SLA가 critical하면 mixed strategy (spot + on-demand 50:50)로 완화 가능합니다.

**Q4. AlertManager → Lambda webhook 인증은 어떻게요?**

A. **솔직히 현재 무인증입니다 (학습 환경)**. 누구나 webhook URL을 알면 false burst를 발사할 수 있는 위험이 있죠. 진짜 운영이면 API Gateway에 API key 추가나 IAM authentication을 적용해야 합니다. 자세한 건 `security/06-burst-trigger-security.md`에 정리돼 있습니다. Phase 6 우선 작업 중 하나입니다.

**Q5. Phase B (R53 Health Check)와 burst trigger 차이는?**

A. 트리거 주체와 시나리오가 다릅니다. **Burst**는 우리 Prometheus가 "온프레 부하 ↑"를 감지하면 트래픽 일부를 AWS로 보냅니다 (성능 보강). **Phase B**는 AWS Route 53이 외부에서 30초마다 ping해서 온프레가 죽었다고 판단하면 100% AWS로 보냅니다 (DR 모드). 두 메커니즘이 보완적으로 안전망을 만듭니다.

**Q6. 강의장 NAT 환경에서 Phase B는 어떻게요? R53 checker가 못 들어오는데?**

A. **강의장에선 health check가 영구적으로 unhealthy로 마킹**됩니다 — R53 외부 checker가 우리 NAT 뒤를 못 뚫으니까요. 결과적으로 100% AWS로 라우팅되는 셈이라 사실상 강제 burst 상태가 됩니다. 그래서 강의장에선 cloudflared로 외부 시연용 URL을 따로 운영합니다. 실제 운영 환경 (ER605 = ISP 직결)으로 가면 정상 fallback 동작합니다.
