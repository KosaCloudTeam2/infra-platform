# "kosa-tickets" — 한정 티켓팅 시스템 (최종 시나리오)

> **AWS Edge + VPN + Onprem K8s + 시점 Burst**
> 작성: 2026-05-12
> 이전 시나리오들(`Scenario_kosa-day.md` 등)은 legacy 참조용

---

## 목차

1. [핵심 스토리](#1-핵심-스토리)
2. [왜 이 시나리오인가](#2-왜-이-시나리오인가)
3. [시스템 아키텍처](#3-시스템-아키텍처)
4. [컴포넌트 매핑](#4-컴포넌트-매핑)
5. [티켓팅 비즈니스 로직](#5-티켓팅-비즈니스-로직)
6. [데모 시나리오 12개](#6-데모-시나리오-12개)
7. [4인 역할 분담](#7-4인-역할-분담)
8. [15일 일정](#8-15일-일정)
9. [AWS 예산](#9-aws-예산)
10. [위험 관리](#10-위험-관리)
11. [발표 메시지](#11-발표-메시지)

---

## 1. 핵심 스토리

> **"콘서트, 스포츠 경기, 한정판 굿즈 등의 티켓팅 시스템. 평상시엔 사내 IDC만으로 충분하지만, 티켓 오픈 시점에 동시 접속 10,000명 폭증. AWS EKS Karpenter Spot 노드로 자동 burst하여 처리하고, 매진 후 자동 복귀."**

### 한 줄 발표 메시지
> "인터파크 티켓처럼 시점 폭증을 다루는 하이브리드 클라우드 — 평상시 비용 거의 0, 티켓 오픈 1시간 burst 비용 단 $3."

### 가상 사용 사례
- BTS 콘서트 티켓 오픈 (19:00 오픈, 19:15 매진)
- 봉준호 감독 신작 시사회 티켓
- 한정판 굿즈 드롭 (무신사 스타일)
- 인기 스포츠 경기 (월드컵 결승, 한국 시리즈)

---

## 2. 왜 이 시나리오인가

### Cloud Burst가 "진짜 쓰이는" 케이스

이전에 "Cloud Bursting은 현업에서 잘 안 쓴다" 라고 했는데, **티켓팅은 예외**:

| 일반 e-commerce | 티켓팅 시스템 |
|---|---|
| 트래픽 변동 2-3배 | **트래픽 변동 100배** |
| 점진적 증가 | **순간 폭증** (분 단위) |
| 종일 부하 | **15~30분 burst 후 진정** |
| 자체 인프라로 처리 가능 | **자체 인프라 한계 명확** |
| Burst 안 씀 | **Burst 필수** |

### 현업 사례 (한국)
- **인터파크 티켓** — BTS 콘서트 시 동접 수십만
- **멜론 티켓** — 인기 콘서트 폭주
- **티켓링크** — 스포츠 경기
- **무신사** — 한정 드롭 (Burst 사용 검증됨)
- **백신 예약** (코로나) — 정부 시스템 다운 사태
- **수능 점수 조회** — 발표 직후 폭주

= **시점 예측 가능 + 짧고 강한 burst** 패턴.
이런 시스템들은 평시 비용 효율 + 이벤트 시 폭발적 확장이 핵심.

### 다이어그램과의 일치
다이어그램 패턴 (AWS NLB + EC2 HAProxy + VPN + Onprem) + **티켓 오픈 시 EKS 추가 가동** = 현업 표준 그대로.

---

## 3. 시스템 아키텍처

### 평상시 (95% 시간)

```
[User]
   │ HTTPS TCP 443
   ▼
┌─────────────────────────────────────────────┐
│ AWS Cloud (VPC)                             │
│                                             │
│  [AWS NLB]   Static IP, L4, 고가용성         │
│  + AWS WAF   (SQLi, XSS, 봇 차단)           │
│      │                                      │
│      ├──→ [EC2 #1 HAProxy] Reverse Proxy    │
│      └──→ [EC2 #2 HAProxy] Active/Active    │
│                 (Keepalived)                │
└──────────────────┼──────────────────────────┘
                   │
                   ▼ VPN (IPsec Tunnel) — 암호화
                   │
┌──────────────────┼──────────────────────────┐
│ On-Premise       ▼                          │
│                                             │
│  [pfSense HA] (CARP MASTER/BACKUP)          │
│      │                                      │
│      ▼                                      │
│  [Onprem HAProxy + Keepalived] (Edge)       │
│  - TLS 종료                                 │
│  - 보안 필터링                              │
│      │                                      │
│      ▼                                      │
│  [K8s Cluster: kosa-onprem]                 │
│  ┌─────────────────────────────────────┐   │
│  │ HAProxy Ingress (L7 라우팅)          │   │
│  │      │                               │   │
│  │      ▼                               │   │
│  │ Service (MetalLB IP)                │   │
│  │      │                               │   │
│  │      ▼                               │   │
│  │ Pods (FastAPI 티켓팅)                │   │
│  │                                      │   │
│  │ Calico CNI + NetworkPolicy + BGP    │   │
│  └─────────────────────────────────────┘   │
│         │                                   │
│         ├─→ [ProxySQL × 2 → Percona PXC × 3]│
│         ├─→ [Redis Sentinel] (잔여 티켓)    │
│         └─→ [Ceph (RBD PV + RGW 이미지)]    │
└─────────────────────────────────────────────┘

평상시 RPS: ~100
AWS 비용: NLB + EC2 + VPN = 월 ~$75
EKS 노드: 0대 (Control Plane만 켜둠)
```

### 티켓 오픈 burst (5% 시간)

```
T-30분: Pre-warm 단계
   ─────────────────────────────────────────
   [EventBridge cron 19:30] ── 트리거
              │
              ▼
   [Lambda: warmup-eks]
              │
              ▼
   AWS EKS Karpenter
   Spot EC2 5대 spawn 시작
   ArgoCD가 ApplicationSet으로 동일 매니페스트 배포

T-0 (19:55~20:00): 트래픽 폭증
   ─────────────────────────────────────────
   [User 10,000명 동시 접속]
                │
                ▼
         [AWS NLB]
                │
        ┌───────┴────────┐
        │                │
   50% 트래픽         50% 트래픽
        │                │
        ▼                ▼
   [EC2 HAProxy]    [EKS Karpenter Spot 노드]
        │                │
        ▼                ▼
   VPN → Onprem      [EKS Pods] (Burst)
        │                │
        ▼                │
   [Onprem K8s]          │
   ┌─────────────────────┴──┐
   │                        │
   ▼                        ▼
   [Onprem Pods]      [AWS RDS Read Replica]
   Write 트랜잭션      Read 트래픽 (잔여 조회)
   결제 처리           ProxySQL이 분기
                            │
                            ▼ binlog
                       [Onprem Percona PXC]
                       (실시간 동기화)

T+15분 (티켓 매진):
   ─────────────────────────────────────────
   CloudWatch alarm: 부하 정상화 감지
                │
                ▼
   [Lambda: cooldown-eks]
                │
                ▼
   Karpenter consolidation
   Spot 노드 자동 종료 (15분 후 모두 종료)

T+30분: 평상시 모드 복귀
```

### 트래픽 분기 방식 (Route 53 vs NLB)

두 가지 옵션:
1. **Route 53 Weighted Routing** — DNS 단에서 분기 (TTL 30초)
2. **AWS NLB Target Group 동적 추가** — NLB가 EKS Pod도 backend로

추천: **Route 53** (다이어그램에 NLB가 평시 항상 있으므로, 추가 분기는 DNS로)

---

## 4. 컴포넌트 매핑

### 다이어그램 요소 → 우리 구현

| 다이어그램 | 우리 구현 | 비고 |
|---|---|---|
| User HTTPS | TLS 1.3 강제 | ACM 인증서 |
| AWS NLB | AWS NLB | Layer 4, Static IP |
| EC2 × 2 HAProxy | EC2 t3.micro × 2 + Keepalived | Active/Active |
| VPN IPsec Tunnel | AWS Site-to-Site VPN (또는 WireGuard) | 암호화 |
| On-Premise Edge HAProxy | HAProxy + Keepalived VM 2대 (DMZ) | TLS 종료 |
| HAProxy Ingress | helm install haproxy-ingress | L7 라우팅 |
| Service (LoadBalancer) | MetalLB IP 자동 할당 | 172.16.22.50~ |
| Pods | K8s Pods (FastAPI) | replicaCount 3 |
| Calico CNI | Tigera Operator | NetworkPolicy + BGP 선택 |

### 데이터 계층 — Percona Operator로 자동화 ⭐

매뉴얼 StatefulSet 작성 ❌. **Percona Operator for MySQL** 사용:

| 컴포넌트 | Operator가 자동 관리 |
|---|---|
| **Percona Operator** | Kubernetes Operator (한 번 설치) |
| **PerconaXtraDBCluster CR** | `spec.pxc.size: 3` 로 클러스터 생성 |
| **ProxySQL** | `spec.proxysql.size: 2` 로 같이 배포 |
| **백업** | `spec.backup.schedule` 로 자동 cron |
| **TLS 인증서** | cert-manager 연동 자동 발급 |
| **노드 장애 복구** | Operator가 감지/자동 복구 |
| **노드 추가/제거** | `size` 숫자만 변경 → 자동 처리 |

```bash
# 설치 (1번만)
kubectl apply -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/v1.14.0/deploy/bundle.yaml

# 클러스터 생성 (CR 1번)
kubectl apply -f pxc-cluster.yaml
```

→ 10분 안에 3노드 PXC + 2 ProxySQL + 자동 백업 + TLS 완성.

### Burst 추가 컴포넌트

| 컴포넌트 | 역할 | 비용 |
|---|---|---|
| AWS EKS Control Plane | K8s API server | $73/월 (항상) |
| Karpenter | Spot 노드 자동 관리 | 무료 |
| AWS RDS Read Replica | Burst 시 Read 분산 | $15/월 |
| EventBridge | cron 트리거 | 무료 |
| Lambda | warmup/cooldown 자동화 | 무료 (free tier) |
| AWS WAF | 매크로/봇 차단 | $5/월 |
| Route 53 | weighted DNS | $0.5/월 |
| CloudWatch | 메트릭 + alarm | 무료 |
| ArgoCD ApplicationSet | 멀티 클러스터 매니페스트 sync | (K8s 내) |

---

## 5. 티켓팅 비즈니스 로직

### 도메인

- **Event**: 콘서트, 스포츠, 굿즈 드롭 등 (총 티켓 수, 오픈 시간, 가격)
- **Member**: 회원 (인증된 사용자만 예약 가능)
- **Reservation**: 회원-이벤트 예약 (1인 N매)

### 핵심 흐름

```
1. 회원 가입 / 로그인 (FastAPI 기존 데모 활용)
2. 이벤트 목록 조회 (오픈 예정 + 진행 중)
3. 이벤트 상세 + 잔여 티켓 확인 (Redis atomic counter)
4. 티켓 예약 시도:
   a. Rate limit 체크 (Redis, 회원당 분당 5회)
   b. Redis에서 잔여 티켓 1 감소 (atomic DECR)
   c. 성공 시 Percona에 reservation INSERT
   d. 실패 시 Redis 다시 INCR (롤백)
5. 결제 (mock — 본 프로젝트는 인프라가 핵심)
6. 예약 완료 → 회원에게 알림 (선택: SNS)
```

### 매크로 / 봇 방어

- AWS WAF: 알려진 봇 IP 차단
- Rate limit: 회원당 분당 5회 (Redis counter)
- CAPTCHA: 5회 실패 시 (선택)

이 부분이 발표에서 강력한 데모.

---

## 6. 데모 시나리오 12개

발표 영상 15분 시나리오:

```
[0:00 - 3:00] 인프라 자동 구축 시연
─────────────────────────────────────
1️⃣  terraform apply → AWS VPC + EC2 + VPN + Proxmox VM 자동 생성 (10분 →
    영상에선 압축)
2️⃣  ansible-playbook site.yml → K8s 부트스트랩 (Calico + HAProxy Ingress + MetalLB)

[3:00 - 6:00] 평상시 정상 동작
─────────────────────────────────────
3️⃣  회원가입 + 로그인 + 이벤트 목록 + 예약 (E2E)
4️⃣  traceroute로 다이어그램 1~10 흐름 확인

[6:00 - 8:00] 보안 데모
─────────────────────────────────────
5️⃣  SQL Injection 시도 → AWS WAF 차단 (' OR 1=1--)
6️⃣  매크로 봇 시도 → Rate limit + Redis 카운터 차단

[8:00 - 10:00] HA 데모
─────────────────────────────────────
7️⃣  EC2 HAProxy #1 강제 종료 → Keepalived 자동 페일오버
8️⃣  Percona 1대 강제 종료 → ProxySQL 자동 우회 (Read는 무중단)
9️⃣  pfSense kosa1 다운 → CARP 페일오버

[10:00 - 14:00] 🌟 티켓 오픈 시뮬레이션 (하이라이트)
─────────────────────────────────────
🔟  T-30분: Lambda 발동 → Karpenter EKS Spot 5대 spawn
   - kubectl get nodes -w 라이브 (5대 EC2 등장)
   - ArgoCD가 FastAPI 매니페스트 EKS에 sync
1️⃣1️⃣ T-0: JMeter 10,000 동접 부하 시작
   - Route 53 weight 50/50 자동 전환
   - ProxySQL이 Read를 AWS RDS Replica로 분기
   - Grafana: 트래픽 + latency + Pod 개수 라이브
   - "사용자 입장에선 응답 시간 안정 유지" 데모
1️⃣2️⃣ T+15분: 매진 후 자동 복귀
   - Route 53 weight 100/0
   - Karpenter consolidation → EKS 노드 자동 종료
   - 비용 카운터: "1시간 burst $3" 표시
```

### Tier별 우선순위

**Tier 1 (필수, 5분 압축 가능)**
- 5, 6, 8, 10, 11, 12 (보안 + DB HA + Burst 핵심)

**Tier 2 (시간 되면)**
- 1, 2, 3, 4, 7, 9 (인프라 / E2E)

---

## 7. 4인 역할 분담

| 담당 | 메인 영역 | 책임 데모 |
|---|---|---|
| **A — 네트워크/IaC** | pfSense (완료), Terraform 온프레/AWS, Ansible, VPN IPsec | 1, 2, 9 |
| **B — K8s 플랫폼** | K8s, Calico, HAProxy Ingress, MetalLB, ArgoCD, **EKS + Karpenter** | 10, 11, 12 |
| **C — 데이터/스토리지** | Ceph 연동, **Percona PXC + ProxySQL**, Redis (잔여 티켓), Velero, **AWS RDS Replica** | 8 |
| **D — 앱 + 보안 + 모니터링** | FastAPI 티켓 API 확장, **AWS NLB + WAF + EC2 HAProxy**, Prometheus/Grafana, JMeter 10K 시나리오 | 3, 4, 5, 6, 7 |

---

## 8. 15일 일정

| Day | 주요 작업 |
|---|---|
| **1** | 환경 준비: Proxmox 템플릿 + Git repo (3개) + AWS 계정 |
| **2** | Terraform 온프레: VM 7대 생성 (CP3 + W3 + Bastion) |
| **3** | Ansible: K8s 부트스트랩 (Calico + HAProxy Ingress + MetalLB) |
| **4** | Ceph CSI 연동, 기본 PVC 검증 |
| **5** | **Percona Operator 설치 → PXC CR 적용 → 3노드 + ProxySQL 자동 생성** + Redis Sentinel 배포 |
| **6** | FastAPI 회원 + 티켓 API 확장 (events, reservations) |
| **7** | GitHub Actions + ArgoCD + Harbor (CI/CD 완성) |
| **8** | **AWS 측 Terraform**: VPC + EC2 HAProxy + NLB + ACM |
| **9** | **VPN IPsec 셋업** (AWS Site-to-Site 또는 WireGuard) |
| **10** | **AWS EKS + Karpenter 셋업**, RDS Read Replica |
| **11** | **EventBridge + Lambda** (warmup/cooldown 자동화), AWS WAF |
| **12** | Prometheus/Grafana 대시보드, JMeter 10K 시나리오 |
| **13** | 12개 데모 시나리오 통합 리허설 |
| **14** | 발표자료, 데모 영상 촬영 |
| **15** | 본 발표, Q&A |

> ⚠️ 위험 구간: Day 9~11 (AWS 통합이 가장 무거움). 막히면 cut 항목:
> - VPN 못 띄움 → Public IP + WAF로 우회
> - Karpenter 안 됨 → EKS 노드 1대 수동 켜둠
> - Lambda 자동화 못 함 → 수동 weight 변경 (라이브 데모는 그대로)

---

## 9. AWS 예산

### 월 운영 비용

| 항목 | 평시 | 이벤트 시 추가 | 월 추정 |
|---|---|---|---|
| AWS NLB | $20 | - | 20 |
| EC2 t3.micro × 2 (HAProxy) | $8 (free tier 가능) | - | 8 |
| Site-to-Site VPN | $36 | - | 36 |
| AWS WAF | $5 | - | 5 |
| ACM 인증서 | 무료 | - | 0 |
| Route 53 | $0.5 | - | 0.5 |
| EKS Control Plane | $73 | - | 73 |
| RDS db.t3.micro (Replica) | $15 | - | 15 |
| EC2 Spot (이벤트 1회 × 1시간) | $0 | ~$3 | 3 (월 1회 가정) |
| **합계** | | | **~$160/월** |

50만원 한도 안에서 **약 3개월 운영 가능**. 발표 후 종료하면 1개월만 사용 → ~$160.

### 비용 절감 옵션

- VPN 대신 Public IP + 보안그룹: 월 -$36
- EKS Control Plane만 발표 1주 전 활성화: 월 -$50
- → 최저 ~$70/월 가능

---

## 10. 위험 관리

| 막힌 단계 | 백업 플랜 |
|---|---|
| Day 5 Percona PXC 못 띄움 | MySQL 1+1 (Master-Slave)로 축소 |
| Day 7 GitHub Actions 안 됨 | 손으로 commit 후 ArgoCD sync |
| Day 8 EC2 HAProxy 설정 빡셈 | NLB만 두고 직접 EKS로 |
| Day 9 VPN 셋업 실패 | Public IP + WAF로 우회 |
| Day 10 Karpenter 못 띄움 | EKS 수동 노드 1대 켜둠 |
| Day 11 Lambda 자동화 실패 | 수동 weight 변경 (라이브 데모 그대로) |
| Day 12 JMeter 10K 부하 부족 | k6 또는 Locust로 변경 |
| Day 13 데모 실패 1개 | 그 데모 빼고 발표 (라이브 실패 금지) |

**원칙**: Day 13 이후 새 기능 X. 디버깅 / 리허설 / 발표 준비만.

---

## 11. 발표 메시지

### 슬라이드 1장 압축

```
┌────────────────────────────────────────────────┐
│  kosa-tickets                                  │
│  한정 티켓팅 시스템 — 시점 폭증 대응 인프라      │
│                                                │
│  ┌──────────────────────────────────────────┐ │
│  │  평상시 비용 거의 0                       │ │
│  │  티켓 오픈 1시간 burst 비용 $3            │ │
│  │  사용자 입장에선 모두 같은 사이트          │ │
│  │  진짜 운영 가능한 하이브리드 클라우드      │ │
│  └──────────────────────────────────────────┘ │
│                                                │
│  AWS NLB + EC2 HAProxy + IPsec VPN + Onprem K8s│
│  + EKS Karpenter Spot (이벤트 시만 가동)       │
│  + Percona PXC + ProxySQL + RDS Replica       │
│  + AWS WAF + Calico + MetalLB + HAProxy Ingress│
│  + ArgoCD GitOps + Velero 백업                │
└────────────────────────────────────────────────┘
```

### 30초 엘리베이터 피치

> "kosa-tickets는 인터파크 티켓이나 멜론티켓 같은 한정 티켓팅 시스템입니다.
> 
> 평상시엔 100 RPS의 평이한 트래픽이라 사내 IDC만으로 충분합니다. AWS NLB + WAF가 외부 위협을 차단하고 IPsec VPN으로 사내망과 안전하게 통신합니다.
> 
> 그런데 인기 콘서트 티켓 오픈 시점이 되면 동접이 100배인 10,000으로 폭증합니다. 이때 EventBridge가 자동으로 AWS EKS Karpenter Spot 노드를 미리 데워서 트래픽을 분산 처리하고, 매진 후 자동으로 종료시켜 비용을 최소화합니다.
> 
> 보안은 WAF + Rate limit으로 매크로/봇을 차단하고, 데이터는 Percona PXC 3중 복제 + ProxySQL R/W 분기로 무중단을 보장합니다.
> 
> 비용은 평상시 거의 0, 1시간 burst에 $3. 진짜 효율적인 하이브리드 클라우드입니다."

### 면접 강조 포인트

- **시점 예측 가능한 burst** — 실제 cloud burst 적용 사례
- **운영 자동화** — EventBridge + Lambda + Karpenter
- **DB HA + 분산** — Percona PXC + ProxySQL + RDS Replica
- **보안** — AWS WAF + Rate limit + VPN
- **GitOps** — GitHub Actions + ArgoCD + Helm
- **모니터링** — Prometheus + Grafana + iperf 정량 검증
- **IaC** — Terraform (온프레 + AWS) + Ansible

---

## 다음 단계 산출물

확정됐으니 만들 우선순위:

### 🔴 필수 (Day 1~2 내)
1. ✅ `Scenario_kosa-tickets.md` (이 문서)
2. `DB_Schema.md` 갱신 — members + events + reservations
3. `API_Specification.md` 갱신 — 회원 + 티켓 API 4개
4. `Architecture_Design.md` 갱신 (티켓 시나리오 반영)

### 🟡 중요 (Day 3~10 내)
5. `terraform/aws/` 작성 — VPC + EC2 HAProxy + NLB + VPN + EKS + RDS + Lambda
6. `ansible/` 보강 — HAProxy Ingress, Calico 이미 반영됨 ✓
7. `EventBridge + Lambda 코드` (Python burst 자동화)
8. `JMeter .jmx` 10K 동접 시나리오

### 🟢 발표 직전 (Day 12~14)
9. 데모 시나리오 12개 명령어 치트시트
10. Grafana 대시보드 JSON
11. 발표 슬라이드 outline
12. 시연 영상 스크립트

---

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-05-12 | 초안 — kosa-day 세일 → kosa-tickets 티켓팅으로 컨셉 변경 (시점 burst 명확화) |
