# "kosa-day 한정 세일" — 회원제 e-Commerce 하이브리드 클라우드 시나리오

> **최종 확정 시나리오** — Cloud Bursting + 현업 깊이가 결합된 회원제 e-Commerce
> 작성: 2026-05-12

---

## 목차

1. [핵심 스토리](#1-핵심-스토리)
2. [두 관점이 섞인 방식](#2-두-관점이-섞인-방식)
3. [시스템 아키텍처](#3-시스템-아키텍처)
4. [컴포넌트 매핑](#4-컴포넌트-매핑)
5. [데모 시나리오 (10개)](#5-데모-시나리오-10개)
6. [4인 역할 분담](#6-4인-역할-분담)
7. [15일 일정](#7-15일-일정)
8. [AWS 예산 견적](#8-aws-예산-견적)
9. [위험 관리](#9-위험-관리)
10. [발표 메시지](#10-발표-메시지)
11. [다음 단계 산출물](#11-다음-단계-산출물)

---

## 1. 핵심 스토리

> **"평상시는 1000명 충성회원이 조용히 쓰는 회원제 쇼핑몰. 분기마다 24시간 한정 'kosa-day 세일' 이벤트를 열면 회원이 폭증해 10,000 동접까지 치솟음. 회원 개인정보는 절대 클라우드로 안 보내면서, 컴퓨팅 부하만 AWS로 burst."**

### 발표 한 줄 메시지
> "평상시 비용 0원, 이벤트 시 자동 확장, 끝나면 자동 복귀. 그리고 회원 개인정보는 절대 클라우드로 안 갑니다."

### 왜 이 시나리오인가
- **Cloud Bursting**: 이벤트 시 AWS로 트래픽/컴퓨팅 자동 확장 → 진짜 하이브리드 클라우드 가치
- **현업 깊이**: PII 분리, Read-Replica, Spot 비용 최적화 → 실제 기업이 하는 방식
- **출발점 활용**: 기존 FastAPI 회원 데모를 그대로 base로 → 앱 개발 시간 절약
- **발표 임팩트**: 평시→이벤트→복귀의 명확한 시각적 흐름

---

## 2. 두 관점이 섞인 방식

| 요소 | Cloud Bursting 관점 | 현업 관점 | 출처 패턴 |
|---|---|---|---|
| **이벤트 Active-Active** | 트래픽 자동 분산 burst | "광군제 11.11" 같은 실제 이벤트 | H |
| **Karpenter + Spot** | 노드 자동 생성/회수 | 비용 70% 절감 (현업 최대 관심사) | B + E |
| **Route 53 Weighted** | DNS 기반 트래픽 weight 조정 | 실무 표준 라우팅 방식 | A |
| **AWS RDS Read Replica** | Read 워크로드 분산 | DB 계층 확장 (이커머스 표준) | F |
| **PII 분리 (NetworkPolicy)** | (해당 없음) | 개인정보보호법 / GDPR 준수 | G |

5가지가 자연스럽게 한 시나리오 안에 녹아들어 억지 끼워 맞춤 없음.

---

## 3. 시스템 아키텍처

### 평상시 모드 (95% 시간)

```
[사용자]
   │
   ▼
[Route 53]  ── 100% ──▶ [HAProxy + Keepalived]
                              │
                              ▼
                        [Onprem K8s]
                              │
                  ┌───────────┼────────────┐
                  ▼           ▼            ▼
              [Redis]    [ProxySQL]   [Ceph RGW]
              Sentinel        │       (이미지)
                              ▼
                    [Percona XtraDB Cluster × 3]
                              │
                              │ binlog (실시간 복제)
                              ▼
                    [AWS RDS Read Replica]
                    ◀── 평시에도 살아있음 (분석 쿼리용)
```

### 이벤트 모드 (kosa-day, 5% 시간)

```
                                T-1시간:
                                EventBridge cron
                                → Lambda → Karpenter 발동
                                → Spot EC2 5대 미리 생성 (warm-up)

[사용자]                           T-0:
   │                              CloudWatch 임계치 도달
   ▼                              Lambda → Route 53 weight 변경
[Route 53]
   ├── 70% ──▶ [Onprem K8s]
   │
   └── 30% ──▶ [AWS EKS]
                   │
                   ▼
            [Pods on Spot EC2]
                   │
                   ▼
            [AWS RDS Read Replica]  ← Read 트래픽 여기로
                                       (Write는 여전히 Onprem)
```

### 이벤트 종료 (T+30분)

```
EventBridge → Lambda → Route 53 weight 100/0 복귀
Karpenter → Spot 노드 자동 종료 (비용 절감)
다시 평상시 상태
```

### PII 분리 (NetworkPolicy)

```
[Onprem K8s]
  ├─ Namespace: pii-protected
  │  ├─ FastAPI 회원 서비스 (이름/이메일/주소)
  │  └─ Percona PXC (회원 테이블)
  │  
  │  NetworkPolicy:
  │  egress:
  │    to:
  │      - cidrSelector: 0.0.0.0/0
  │        except:
  │          - cidr: <AWS EKS VPC CIDR>   ← AWS로 가는 트래픽 차단
  │
  └─ Namespace: non-pii
     ├─ 상품 카탈로그
     ├─ 주문 처리
     └─ 리뷰/이미지 → AWS EKS와 통신 OK
```

---

## 4. 컴포넌트 매핑

### 온프레미스 K8s

| 컴포넌트 | 비고 |
|---|---|
| FastAPI 앱 (기존 확장) | 회원 + 상품 + 주문 |
| Percona XtraDB Cluster × 3 | 메인 DB (Write + Read) |
| **ProxySQL × 2 (HA)** | **Read 쿼리 분기 핵심** |
| Redis Sentinel | 세션 |
| Ceph RBD (CSI) | DB PV |
| Ceph RGW (S3) | 프로필 이미지 |
| Harbor | 컨테이너 레지스트리 |
| HAProxy + Keepalived | 외부 진입 |
| NGINX/Cilium Ingress | K8s Ingress |
| Prometheus + Grafana | 메트릭 |
| ArgoCD | GitOps (멀티 클러스터) |
| Velero | 백업 → AWS S3 |
| Cilium NetworkPolicy | PII 분리 |

### AWS (이벤트 모드 + 평시 Replica)

| 컴포넌트 | 평시 | 이벤트 시 | 비고 |
|---|---|---|---|
| EKS Control Plane | ✓ (켜둠) | ✓ | 노드 0대 |
| EKS + Karpenter | (대기) | Spot 노드 5~10대 | 자동 생성/종료 |
| RDS for MySQL (Read Replica) | ✓ (켜둠) | ✓ | Percona binlog 복제 대상 |
| Route 53 (weighted) | 100/0 | 70/30 | Lambda가 조정 |
| CloudFront + S3 | ✓ | ✓ | 정적 자산 |
| EventBridge | cron 대기 | 발동 | burst 트리거 |
| Lambda | - | weight 조정 | 자동화 핵심 |
| CloudWatch | 모니터링 | 임계치 감지 | 메트릭 기반 발동 |
| S3 (Velero) | ✓ | ✓ | K8s 백업 |
| SNS | - | 알림 | optional |

---

## 5. 데모 시나리오 (10개)

발표 영상 시간순 흐름. 5~7분 영상에 핵심 6~8개 압축.

```
═══════════════════════════════════════════════════════
[평상시 모드 — 첫 2분]
═══════════════════════════════════════════════════════

1️⃣  E2E 정상 동작
    회원가입 → 로그인 → 상품조회 → 주문
    온프레만 사용, AWS 트래픽 0

2️⃣  ProxySQL Read 쿼리 분기 (평시)
    kubectl logs proxysql → "SELECT routed to: percona-svc"
    아직 AWS Replica로 안 감 (평시엔 온프레로 충분)

3️⃣  PII 쿼리 차단 데모
    kubectl exec → 회원 서비스 Pod에서 AWS로 ping → 차단 확인
    "회원 개인정보는 절대 클라우드 안 갑니다" 

═══════════════════════════════════════════════════════
[kosa-day 이벤트 발동 — 중간 2분]
═══════════════════════════════════════════════════════

4️⃣  EventBridge cron 발동 (T-1시간)
    Lambda 로그 확인: "kosa-day prep started"
    Karpenter가 Spot EC2 5대 spawn 시작

5️⃣  Spot 노드 자동 생성 라이브
    kubectl get nodes -w
    1~3분 안에 EC2 노드 5대가 Ready로 변하는 모습

6️⃣  JMeter 부하 시뮬레이션
    1000 → 5000 → 10000 RPS 점진 ramp-up
    Grafana 그래프: 트래픽 우상향

7️⃣  Route 53 Weight 자동 조정
    CloudWatch alarm → Lambda → weight 100/0 → 70/30
    nslookup으로 30% 쿼리는 AWS ALB로 가는 것 확인

8️⃣  ProxySQL Read 쿼리 → AWS Replica로 분기
    kubectl logs proxysql:
    "Heavy SELECT routed to: rds-replica.aws"
    응답 시간 안정 유지 (HPA + Spot 노드 덕분)

═══════════════════════════════════════════════════════
[이벤트 종료 + 복귀 — 마지막 1분]
═══════════════════════════════════════════════════════

9️⃣  CloudWatch 임계치 하강 감지
    Lambda → Route 53 weight 100/0 복귀
    Karpenter → Spot 노드 자동 종료

🔟  비용 분석
    AWS Cost Explorer: "이벤트 1회 비용 ~$10"
    "월 평균 13만원으로 burst 인프라 확보"
```

### Tier별 우선순위 (시간 짧으면 Tier 1만)

**Tier 1 (필수, 5분 영상)**
- 1, 3, 5, 6, 7, 8 (E2E, PII 차단, 노드 자동 생성, JMeter 부하, weight 조정, Read 분기)

**Tier 2 (시간 있으면)**
- 2, 4, 9, 10

---

## 6. 4인 역할 분담

| 담당 | 메인 영역 | 산출물 |
|---|---|---|
| **A — 인프라/네트워크** | pfSense (완료 ✓), Terraform/Ansible IaC, iperf, **AWS VPC + Route 53** | VM 자동 생성, AWS 네트워크 |
| **B — K8s 플랫폼** | Onprem K8s, Ceph CSI, **AWS EKS + Karpenter**, ArgoCD multi-cluster, MetalLB, Cilium NetworkPolicy | 클러스터 양쪽 + 플랫폼 + PII 차단 정책 |
| **C — 데이터 계층** | Percona PXC + ProxySQL, Redis, **AWS RDS Replica + binlog**, ProxySQL 라우팅 룰 | DB 계층 + Read 분기 |
| **D — 앱/관측/Burst** | FastAPI 확장, GitHub Actions, **EventBridge + Lambda burst**, JMeter, Grafana, AWS 비용 분석 | 앱 + CI/CD + 모니터링 + 자동화 |

### 의존성 흐름
```
Day 1-3:  A 작업이 끝나야 B/C/D 시작 가능 (VM, AWS 네트워크)
Day 4-6:  B 작업이 끝나야 C 시작 가능 (K8s 위에 DB 배포)
Day 7-9:  C/D 병렬 작업 가능
Day 10:   B가 EKS + Karpenter 셋업 후 D가 burst 자동화
Day 11+:  전원 통합 리허설
```

---

## 7. 15일 일정

### Week 1 — 인프라 기반

| Day | 담당별 작업 |
|---|---|
| **1 (월)** | 전원: 아키텍처 확정, Git repo 3개 생성 (app/manifests/infra)<br>A: Proxmox Ubuntu cloud-init 템플릿 (VMID 9000)<br>B: K8s 설치 방식 결정, Cilium 버전 확정<br>C: Percona Operator vs Helm chart 결정<br>D: 기존 FastAPI 코드 분석, 확장 계획 |
| **2 (화)** | A: Terraform → VM 6대 (CP3, W2, Bastion)<br>A: AWS VPC 셋업, IAM 사용자 발급<br>B: Ansible 환경 + inventory 자동 생성<br>D: FastAPI에 MySQL 연동 (aiomysql) |
| **3 (수)** | A: iperf3로 10G 망 측정 (베이스라인 문서)<br>B: Ansible 플레이북 → kubeadm 클러스터 + Cilium<br>C: Ceph 클러스터 동작 확인, CSI 사전 점검<br>D: FastAPI 컨테이너화 (Dockerfile, 로컬 빌드) |
| **4 (목)** | A: HAProxy+Keepalived VM 2대 추가, DNS 설정<br>B: Ceph RBD CSI 설치, test PVC 확인<br>C: Ceph RGW S3 endpoint, bucket 생성<br>D: FastAPI 프로필 이미지 업로드 (boto3 → RGW) |
| **5 (금)** | A: pfSense NAT 룰 (외부 진입 VIP)<br>B: ArgoCD + Harbor 설치<br>C: **Percona XtraDB Cluster × 3** 배포<br>D: FastAPI 인증(JWT), 상품 모델 |

### Week 2 — 데이터/AWS/앱

| Day | 담당별 작업 |
|---|---|
| **6 (토 또는 월)** | C: **ProxySQL × 2** 배포, R/W 분리 룰<br>C: Redis Sentinel<br>D: FastAPI에 ProxySQL endpoint 연결<br>B: Harbor에 첫 이미지 push 테스트 |
| **7 (월/화)** | D: **GitHub Actions workflow** (lint→test→build→push→manifest bump)<br>B: **ArgoCD Application** 정의<br>B: Sealed-secrets 설치<br>C: Percona/ProxySQL ArgoCD 등록 |
| **8 (화/수)** | B: **AWS EKS + Karpenter 셋업** (가장 무거운 작업)<br>B: ArgoCD multi-cluster 등록 (온프레 + EKS)<br>D: FastAPI 상품/주문 API 추가<br>D: 더미 데이터 시드 |
| **9 (수/목)** | C: **AWS RDS for MySQL 생성**<br>C: **Percona binlog → RDS 복제 설정**<br>C: ProxySQL 라우팅 룰에 RDS Replica 추가<br>B: Ingress + cert 설정 |
| **10 (목/금)** | A: **Route 53 hosted zone**, weighted routing 정책<br>D: **EventBridge + Lambda** (weight 조정 코드)<br>D: CloudWatch alarm 설정 |

### Week 3 — 통합 / 데모 / 발표

| Day | 담당별 작업 |
|---|---|
| **11** | B: **Cilium NetworkPolicy로 PII 분리** 룰<br>C: Velero + S3 백업 자동화<br>D: Prometheus + Grafana 대시보드<br>D: HPA 설정 (CPU 50% target) |
| **12** | D: **JMeter 시나리오 작성** (.jmx)<br>D: 부하 테스트 실행 → burst 동작 확인<br>전원: 통합 테스트 (E2E + 장애 시나리오) |
| **13** | 전원: **데모 시나리오 10개 리허설**<br>각 데모 명령어/예상결과/트러블슈팅 메모<br>발표 슬라이드 (15~20장) 작성 시작 |
| **14** | 전원: 발표 슬라이드 완성<br>데모 영상 1차 촬영 (OBS Studio)<br>발표 리허설 1회 |
| **15** | 데모 영상 최종 촬영<br>본 발표<br>회고 + 운영 매뉴얼 정리 |

> ⚠️ **위험 구간**: Day 8~10 (AWS 통합)
> 막히면 cut 항목:
> - RDS Replica 못 띄움 → ProxySQL 라우팅 시뮬레이션만 (실제 분기 X)
> - Karpenter 안 됨 → EKS 노드 1대 수동 켜둠
> - Lambda burst 자동화 못 함 → 수동 weight 변경 (라이브 데모는 그대로)

---

## 8. AWS 예산 견적

### 월 운영 비용 (50만원 안)

| 항목 | 평시 비용 | 이벤트 시 추가 | 월 추정 |
|---|---|---|---|
| EKS Control Plane | $73/월 | - | ~10만원 |
| RDS db.t3.micro (Replica) | $15/월 | - | ~2만원 |
| EC2 Spot (이벤트 6시간 × 5대) | $0 | ~$3/회 | ~1만원 (월 1~2회) |
| Route 53 hosted zone | $0.5/월 | - | 거의 0 |
| CloudFront / S3 / Lambda | - | - | free tier |
| EventBridge / CloudWatch | - | - | free tier |
| **합계** | | | **~13만원/월** |

**50만원이면 3~4개월 운영 가능.** 발표 후 종료하면 1개월만 사용 → ~13만원.

### 비용 절감 옵션
- EKS Control Plane만 발표 1주 전에 켜기 → ~3만원/주
- RDS도 발표 직전에 생성 → 며칠치만
- Spot 가격은 변동 (보통 온디맨드의 30%)

---

## 9. 위험 관리

### 시나리오별 백업 플랜

| 막힌 단계 | 백업 플랜 | 발표 영향 |
|---|---|---|
| Day 5 Percona PXC 못 띄움 | MySQL 1+1 (Master-Slave)로 축소 | "확장 시 PXC로" 멘트 |
| Day 7 GitHub Actions 안 됨 | 손으로 commit 후 ArgoCD sync | 라이브 데모는 manual |
| Day 8 EKS 셋업 실패 | EC2 단일 인스턴스 + Docker Compose | "K8s로 확장 가능" 멘트 |
| Day 9 RDS Replica 안 됨 | ProxySQL 라우팅 시뮬레이션만 | 데모 분기 로직만 |
| Day 10 Lambda burst 못 함 | 수동 `aws route53 change-resource-record-sets` | 라이브 데모 그대로 |
| Day 11 NetworkPolicy 안 됨 | iptables 룰로 차단 데모 | 동일 효과 |
| Day 12 JMeter 안 됨 | `hey` 또는 `wrk` 같은 단순 도구 | 시각화는 Grafana로 |

### 절대 원칙
- **Day 13 이후 절대 새 기능 X**. 디버깅/리허설/발표 준비만.
- **Day 12 끝나기 전 동작 확인**. 안 되는 거 잘라낼 결정 시점.
- **라이브 데모는 무조건 사전 리허설 성공한 것만**. 한 번이라도 실패한 데모는 영상으로 대체.

---

## 10. 발표 메시지

### 슬라이드 1장으로 압축

```
┌─────────────────────────────────────────────────┐
│  kosa-day                                       │
│  회원제 e-Commerce 하이브리드 클라우드 플랫폼     │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  평상시 비용 0원                         │  │
│  │  이벤트 시 자동 확장                     │  │
│  │  끝나면 자동 복귀                        │  │
│  │  회원 개인정보는 절대 클라우드로 안 감   │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  Onprem K8s + AWS EKS + Karpenter + Route 53   │
│  Percona PXC + ProxySQL + RDS Replica          │
│  Ceph + pfSense HA + ArgoCD + GitHub Actions   │
└─────────────────────────────────────────────────┘
```

### 30초 엘리베이터 피치
> "저희 시스템은 평상시 온프레미스로 충분히 운영되다가, 분기마다 한정 세일 이벤트가 시작되면 AWS로 자동 확장됩니다. Spot 인스턴스를 활용해 비용을 70% 절감하고, 회원 개인정보는 NetworkPolicy로 절대 클라우드를 못 가게 막아 개인정보보호법까지 준수합니다. 이벤트가 끝나면 자동으로 모든 게 종료되어 다시 평상시 모드로 돌아갑니다. 이것이 바로 진짜 하이브리드 클라우드입니다."

### 면접 강조 포인트
- **운영 경험**: ProxySQL 라우팅 룰, Percona binlog 복제, Karpenter Spot 정책
- **비용 최적화**: Spot + 자동 종료 + Read Replica 만 분산
- **컴플라이언스**: NetworkPolicy로 PII 차단 (개인정보보호법 / GDPR)
- **자동화**: EventBridge → Lambda → Route 53 weight 자동 조정
- **GitOps**: GitHub Actions(CI) + ArgoCD(CD) + ApplicationSet (멀티 클러스터)
- **HA**: pfSense CARP, Percona PXC, ProxySQL HA, HAProxy+Keepalived

---

## 11. 다음 단계 산출물

시나리오 확정됐으니 다음 단계 만들 산출물 우선순위:

### 🔴 필수 (Day 1~2 내)
1. **상세 아키텍처 다이어그램** (Excalidraw/Draw.io)
   - 평시/이벤트 두 모드
   - 네트워크 흐름 (VLAN, IP, AWS VPC)
   - 데이터 흐름 (binlog, 트래픽)
2. **DB 스키마** (회원/상품/주문 + PII 컬럼 식별)
3. **API 명세** (FastAPI 확장 가이드)
4. **Git repo 구조** (3개 repo: app / manifests / infra)

### 🟡 중요 (Day 3~7 내)
5. **Terraform AWS 모듈** (VPC, EKS, RDS, Route 53)
6. **ProxySQL 라우팅 룰** (`query_rules` 테이블 SQL)
7. **GitHub Actions workflow .yml**
8. **ArgoCD ApplicationSet** (멀티 클러스터)

### 🟢 발표 직전 (Day 12~14)
9. **EventBridge + Lambda 코드** (Python burst 자동화)
10. **JMeter `.jmx` 부하 시나리오**
11. **데모 시나리오 10개 명령어 치트시트**
12. **Grafana 대시보드 JSON**
13. **발표 슬라이드 outline**
14. **시연 영상 스크립트**

### 작성 우선순위 (요청 시 차례로)
가장 급한 순서:
1. 상세 아키텍처 다이어그램 (Excalidraw 텍스트)
2. DB 스키마 + API 명세
3. Terraform AWS 모듈 골격
4. 데모 시나리오 명령어 치트시트

---

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-05-12 | 초안 — Cloud Bursting + 현업 깊이 결합 시나리오 확정 |

---

## 참고 자료

- AWS EKS + Karpenter: https://karpenter.sh/
- ProxySQL R/W 분기: https://proxysql.com/documentation/configuring-proxysql/
- Cilium NetworkPolicy: https://docs.cilium.io/en/stable/security/policy/
- Route 53 Weighted Routing: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-weighted.html
- Percona PXC + ProxySQL: https://www.percona.com/blog/proxysql-percona-xtradb-cluster/
- Velero: https://velero.io/
