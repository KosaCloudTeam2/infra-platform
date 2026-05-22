# 04. Burst 아키텍처 (트래픽 폭증 자동 대응)

> ⭐ **한 줄 요약**: 온프레 부하 임계치 도달 → **Prometheus → AlertManager → Lambda → Route 53 weight 변경** → 트래픽 AWS로 → **EKS HPA + Karpenter Spot 자동 확장**. 평시 0 노드, burst 시 자동 scale.

---

## 🎯 우리가 한 선택

### 트리거 흐름 (E2E)
```
[온프레 ticket-app 부하 ↑]
        │
        │ (Prometheus가 scrape, 30s 간격)
        ▼
[Prometheus rule: cpu_usage > 80% for 5m]
        │
        │ alert firing
        ▼
[AlertManager]
        │ routing: matchers burst_trigger="true" → aws-burst receiver
        │ webhook
        ▼
[API Gateway HTTP API: le24sqo79b.execute-api...amazonaws.com]
        │
        ▼
[Lambda burst-trigger]
        │ Route 53 update: aws weight 0 → 30
        ▼
[Route 53 weighted record]
        │ DNS 캐시 만료 후 (TTL 60s)
        ▼
[클라이언트 일부가 AWS NLB로 라우팅]
        │
        ▼
[NLB → EC2 HAProxy → EKS Pod]
        │
        │ HPA: CPU > 70% → replicas 2 → 16
        ▼
[Karpenter: Pending Pod 감지 → m5.large Spot Node 자동 생성]
        │
        ▼
[EKS Pod이 RDS replica에서 read, 온프레 PXC로 write]
```

### Phase B Fallback (R53 Health Check)
```
[온프레 자체 장애 (예: edge VIP 죽음)]
        │
        │ Route 53 health checker가 외부에서 30s마다 ticket.caffeinism.cloud/healthz 폴링
        ▼
[3번 연속 실패 (90초)]
        │
        ▼
[onprem record를 unhealthy 마킹]
        │ weighted routing에서 자동 제외
        ▼
[100% AWS로 라우팅]
```

### 핵심 컴포넌트
| 컴포넌트 | 설정 |
|---|---|
| Prometheus alert rule | `cpu_usage > 80% for 5m` (예시) |
| AlertManager route | `burst_trigger="true"` 매처 → aws-burst receiver |
| Webhook | https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com/ |
| Lambda runtime | Python 3.x, IAM role with route53:ChangeResourceRecordSets |
| Route 53 | weighted A record (onprem 70 / aws 30 또는 0/30) |
| EKS HPA | min 2, max 16, CPU 70% |
| Karpenter NodePool | m5.large/xlarge spot, max 10 nodes |
| RDS replica | external replica (PXC binlog) |

---

## 🔍 고려한 대안들

### Q1. 트래픽 분산 방식 (Route 53 weight vs Global Accelerator vs DNS round-robin)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Route 53 weighted (선택)** | 비율 조정 자유, health check 통합 | DNS 캐시 (TTL) 지연, 클라이언트별 sticky 안됨 | ★★★★★ |
| **Global Accelerator** | Anycast IP, latency 기반 | 비용 ↑ ($18/월/AG), Asia 한정 효과 적음 | ★★ |
| **DNS round-robin** | 단순 | 비율 조정 어려움, health check X | ★ |

### Q2. Burst 트리거 방식 (Prometheus + Lambda vs CloudWatch + Lambda vs 수동)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Prometheus → Lambda (선택)** | 온프레 메트릭 직접, 정밀 조건 | webhook 인증 추가 필요 | ★★★★★ |
| **CloudWatch + Lambda** | AWS native | 온프레 메트릭 → CloudWatch 보내야 (remote_write 필요) | ★★★ |
| **수동 Lambda 호출** | 단순 | 자동화 X | ★ |

### Q3. Burst 노드 (EKS Karpenter Spot vs EC2 ASG vs ECS Fargate)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **EKS Karpenter Spot (선택)** | 빠른 provisioning (40초), spot 75% 할인, K8s 일관성 | spot interruption (2분 notice) | ★★★★★ |
| **EC2 ASG (Cluster Autoscaler)** | 표준, 안정 | scale 느림 (분), 인스턴스 타입 1개만 | ★★★ |
| **ECS Fargate** | 서버리스, 노드 관리 X | EKS와 다른 API, 학습 추가 | ★★ |
| **EKS On-Demand** | 안정성 ↑ | spot 75% 절감 포기 | ★★★ |

### Q4. AWS 측 진입점 구조

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **CloudFront + NLB + EC2 HAProxy + EKS (선택)** | DDoS 흡수 + WAF + L7 통제 | 컴포넌트 많음, 복잡 | ★★★★★ |
| NLB + EKS (HAProxy 생략) | 단순 | runtime weight 조정 못함 (Lambda 트리거 어려움) | ★★ |
| ALB + EKS | 표준 | 정적 IP X, 우리 패턴과 안 맞음 | ★★★ |

---

## 💡 왜 이걸 선택했나 (5가지)

### 1. 🔧 **Prometheus 트리거 = 온프레 정밀 조건**
> 🔥 **핵심**: 진짜 부하 정보는 온프레가 안다. CloudWatch는 AWS 자원만 본다.

- 온프레 ticket-app CPU/RPS/latency → Prometheus가 정확히 측정
- CloudWatch로 보내려면 remote_write 인프라 + 지연 + 비용
- 우리는 PrometheusRule + AlertManager webhook으로 5분 condition + 정밀 라우팅

### 2. 💰 **Spot 75% 할인 = 학습 + 비용**
- Burst는 일시적이라 spot interruption 허용 가능
- m5.large on-demand $0.096 → spot $0.029 (75% 절감)
- Karpenter가 interruption 자동 재배치

### 3. ⚡ **Karpenter = 40초 provisioning**
- Cluster Autoscaler는 ASG 통해 ~5분
- Karpenter는 직접 EC2 API → 40초~1분
- Burst 응답성 ★★★★★

### 4. 🛡️ **이중 fallback (R53 Health Check)**
- Phase B 추가: 온프레 자체 죽으면 R53이 자동으로 onprem 제외
- 코드 0줄로 DR 모드 구현
- "burst 안 됐을 때" 대비

### 5. 📊 **모든 컴포넌트 관찰 가능**
- Prometheus가 burst 트리거 메트릭 자체 기록
- Lambda는 CloudWatch로 로그
- EKS HPA + Karpenter 메트릭도 수집

---

## 💰 비용 분석

### 평시 (burst 미발생)
| 자원 | 월 비용 |
|---|---|
| EKS Cluster (제어 평면) | $72 |
| RDS db.t3.micro (replica) | $12 |
| Lambda (요청 거의 없음) | $0 |
| Route 53 hosted zone | $0.5 |
| Route 53 health check | $0.5 |
| **소계** | **~$85/월** |

### Burst 1시간 발생 시 추가
| 자원 | 단가 | 추가 비용 |
|---|---|---|
| Karpenter Spot m5.large × 3 | $0.029/h × 3 × 1h | ~$0.09 |
| 데이터 전송 (cross-zone + 외부) | $0.01/GB × ~10GB | $0.1 |
| CloudWatch 메트릭 | 무시 | ~$0 |
| **burst당** | | **~$0.2** |

### 진짜 burst 시 (월 100시간)
- 추가 ~$20/월

→ **연간 burst 자원 비용 < $300**. 진짜 트래픽 대응 인프라치곤 매우 저렴.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 자동 burst (수동 개입 0) | 트리거 잘못되면 false burst (비용 발생) |
| Spot 절감 | interruption (2분 notice) |
| Karpenter 빠른 provisioning | 학습 곡선 |
| 이중 fallback (R53 HC) | 1분 정도 fallback 지연 |
| 양방향 (트래픽 ↔ DR) | 컴포넌트 많음 |

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **Prometheus 죽음** | alert 자체 발생 안 함 → burst 미동작 | sys2 추가 시 HA replica |
| **AlertManager 죽음** | webhook 못 보냄 | sts replicas 3 (이미 spec) |
| **Lambda 코드 에러** | R53 weight 변경 실패 | CloudWatch 로그 + alarm |
| **R53 API 일시 장애** | DNS 캐시 풀릴 때까지 옛 weight 유지 | TTL 60s라 자연 회복 |
| **EKS 노드 spot interruption** | Pod evict (2분 notice) → 다른 노드 또는 새 spot 자동 | Karpenter 자동 |
| **RDS replica down** | EKS Pod read 실패 → write도 fallback 필요 | 다른 RDS 또는 직접 PXC (VPN 위) |

---

## 🚀 확장 가능성

### Option A: ⭐ Multi-cluster ArgoCD (EKS도 GitOps 관리)
- 현재: ArgoCD가 온프레 K8s만 관리. EKS는 manual deploy.
- 확장: bastion ArgoCD에 EKS cluster 등록 → 같은 git repo로 양쪽 동기 배포
- ✅ **장점**: git push 1번에 양쪽 동기 → 진짜 같은 코드 보장
- ❌ **단점**: kustomize overlay 필요 (onprem vs eks 환경 변수 차이)
- 💰 **비용**: 0 (ArgoCD 기존 자원)
- ⏱️ **작업**: 4~6시간
- 🎯 **추천 시점**: burst 자주 + EKS 코드와 온프레 코드 어긋남 발견

### Option B: Karpenter NodePool 다양화
- ✅ **장점**: spot fleet (여러 타입) → interruption 회복성 ↑
- 예: m5.large + m5a.large + m6i.large + m5.xlarge (4 옵션)
- 🎯 **추천 시점**: 단일 타입 interruption 자주 발생

### Option C: 트래픽 split을 latency 기반으로 (R53 latency routing)
- ✅ **장점**: 사용자 위치 기반 가장 빠른 곳으로
- ❌ **단점**: 한국 사용자 한정엔 의미 적음 (양쪽 다 KR region)
- 🎯 **추천 시점**: 글로벌 사용자

### Option D: ALB로 교체 + WebSocket sticky
- ✅ **장점**: ALB의 sticky session, WebSocket 지원
- ❌ **단점**: 우리 runtime weight 패턴 재구성
- 🎯 **추천 시점**: WebSocket/장기 connection 워크로드

### Option E: 진짜 multi-region active-active
- ✅ **장점**: 글로벌 DR
- ❌ **단점**: 비용 2배, 데이터 일관성 어려움
- 🎯 **추천 시점**: 진짜 운영 + 글로벌

### Option F: Argo Rollouts (canary/blue-green)
- ✅ **장점**: 새 버전 EKS에 먼저 5% → 정상 확인 → 100%
- ❌ **단점**: 워크플로 학습
- 🎯 **추천 시점**: 잦은 배포 + 안전성 ↑

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 코드 한쪽만 옛 버전 | A (multi-cluster ArgoCD) |
| spot interruption 잦음 | B (NodePool 다양화) |
| 잦은 배포 안전성 | F (Rollouts) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 자기 (`03-aws-hybrid.md`) | NLB/EC2/EKS 기반 인프라 |
| 🏛️ 자기 (`05-observability-design.md`) | Prometheus alert + AlertManager가 트리거 |
| 💾 데이터 (`06-rds-replication.md`) | EKS Pod이 RDS replica 사용 |
| 🔒 보안 (`06-burst-trigger-security.md`) | webhook 인증, Lambda IAM |
| 🔧 CI/CD | Lambda 코드 배포 (terraform/aws/) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Burst 트리거가 false positive 내면? (실제 부하 아닌데 EKS scale up)**
A. (1) 비용 약간 발생 (Karpenter spot이라 시간당 $0.029, 즉시 회수 가능), (2) AlertManager에서 resolve_timeout 설정으로 자동 weight 복귀, (3) Prometheus rule을 5분 sustained로 잡아 단발성 spike 회피.

**Q2. 클라이언트가 DNS 캐시로 옛날 IP 가지고 있으면?**
A. TTL 60초로 짧게. 진짜 즉시 트래픽 분산 필요면 R53 weighted 대신 ALB target group weighted (TTL 무시) 사용. 우리 demo엔 60s 지연 충분.

**Q3. Karpenter Spot이 interruption 받으면 Pod은?**
A. AWS가 2분 전 termination notice → Karpenter가 다른 spot 또는 on-demand로 자동 재배치 → Pod 재시작. 사용자엔 일시적 5xx 가능 (재시도하면 OK).

**Q4. AlertManager → Lambda webhook 인증은?**
A. **현재 무인증** (학습 환경). 진짜 운영이면 API Gateway에 API key 또는 IAM 인증 추가 필요. → `security/06-burst-trigger-security.md`

**Q5. Phase B (R53 Health Check)와 burst trigger 차이?**
A. Burst = 온프레 살아있는데 부하 ↑ → 트래픽 일부 AWS로 (성능). Phase B = 온프레 자체 죽음 → 100% AWS로 (DR). 두 메커니즘이 보완.

**Q6. 강의장 NAT 환경에서 Phase B는 어떻게? R53 checker가 못 들어오는데**
A. 강의장에선 health check 영구적 unhealthy → 100% AWS로 라우팅됨 (사실상 강제 burst). 그래서 강의장에선 cloudflared로 외부 시연용 URL 따로 운영. 실 운영 환경 가면 정상 fallback 동작.
