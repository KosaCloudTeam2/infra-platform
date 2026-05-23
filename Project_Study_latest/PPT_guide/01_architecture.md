# Part 1. 아키텍처 — 발표자 A

- 슬라이드: 01~08 (총 8장)
- 발표 시간: 약 7분 (슬라이드당 약 50초)
- 톤: 다크 메인
- 역할: 큰 그림 + 핵심 시나리오 + 기술 deep dive 3종

## 파트 전체 흐름

```
표지 → 배경(WHY) → 정답(3옵션) → 시나리오(타임라인) → 원칙(4)
  → 한 장 아키텍처 → deep dive (K8s 플랫폼) → deep dive (HA + AWS 로드맵)
```

## 핵심 메시지 1줄

"평소엔 온프레, 피크엔 클라우드 — 비용 최소화하면서 100배 트래픽 대응"

---

## 01. 표지 [다크]

### 한 메시지
KOSA Team 2의 하이브리드 인프라 프로젝트 시작

### 들어갈 내용
- 큰 영문 타이틀: `HYBRID INFRASTRUCTURE`
- 한국어 부제: 예매 트래픽 burst를 견디는 온프레-AWS 하이브리드 K8s
- 짧은 영문 한 줄: On-Premise baseline · AWS burst window via Site-to-Site VPN
- 팀원 4인 + 담당 파트 표시
- KOSA TEAM 2 (상단 작은 라벨)
- 발표 일자

### 발표 멘트 가이드
"안녕하세요 KOSA Team 2입니다. 오늘 발표할 주제는 예매 트래픽 burst를 견디는 온프레-AWS 하이브리드 쿠버네티스 인프라입니다. 평소엔 자체 인프라로 운영하다가 예매 오픈 시점에만 AWS로 확장하는 구조입니다."

---

## 02. 프로젝트 배경 — WHY HYBRID BURST [다크]

### 한 메시지
예매 사이트는 평시 50 req/s, 오픈 시점 5,000 req/s로 100배 spike

### 들어갈 내용
- 메인 시각: 트래픽 spike 그래프 (좌측 70% 영역 크게)
  - X축: T-10m / T-0 (오픈) / T+10m / T+30m
  - Y축: 0 / 1K / 3K / 5K (req/s)
  - 곡선: T-0 직전까지 평평 → 급격 spike → 점진 감소
- 강조 라벨: "↑ 5,000 req/s · 100배 spike"
- 좌하단 메시지: "평시 ~50 req/s"
- 우하단 한 줄 결론: "피크 5분을 위해 1년 인프라?"
- 참조 1줄: 인터파크 / 예스24 티켓

### 강조 수치
- 평시: 50 req/s
- 피크: 5,000 req/s
- 배수: 100×

### 발표 멘트
"인터파크나 예스24 같은 예매 사이트의 트래픽 패턴을 보면, 평소엔 초당 50건 정도지만 인기 공연 오픈 시점에는 5,000건까지 폭증합니다. 100배 차이입니다. 이 5분을 위해 1년 365일 비싼 인프라를 가지고 있는 게 합리적일까요?"

---

## 03. 하이브리드의 정답 — 3옵션 비교 [다크]

### 한 메시지
평시 온프레 + 피크 클라우드만이 유일한 합리적 답

### 들어갈 내용
- 3개 큰 카드 (가로 배열, 균등 분할)
  - **옵션 1 — 평시 기준 인프라** / 결과: 99% 자원 낭비
  - **옵션 2 — 피크 기준 인프라** / 결과: 비용 100배, 비현실적
  - **옵션 3 — 하이브리드 (정답)** / 결과: 평소 절약 + 피크 대응 / 강조 표시 (밝은 블루 외곽선)
- 각 카드: 번호 (01/02/03) + 제목 + 결과 1줄
- 옵션 3만 액센트 색 (BLUE)

### 발표 멘트
"3가지 선택지가 있습니다. 평시 기준으로 인프라를 깔면 99% 시간이 자원 낭비, 피크 기준으로 깔면 비용이 100배 들어 비현실적입니다. 답은 평소엔 온프레, 피크 시에만 클라우드를 빌리는 하이브리드 모델이고, 우리 프로젝트가 이 모델을 구현했습니다."

---

## 04. WARMUP TIMELINE [다크]

### 한 메시지
T-30분에 Karpenter가 EKS 사전 워밍업 → T-0 즉시 운영 → T+1h 자동 종료

### 들어갈 내용
- 메인: 큰 가로 타임라인 (슬라이드 중앙)
- 키포인트 3개 (큰 원 + 큰 라벨):
  - `T-30m` Karpenter 트리거
  - `T-0` 예매 오픈
  - `T+1h` scale-down → 0
- 보조점 5개 (작은 회색 원):
  - EC2 join (T-25m)
  - 이미지 pull (T-23m)
  - App warmup (T-20m)
  - peak (T+10m)
  - 안정화 (T+30m)
- T-0 세로 점선 (강조)
- 하단 1줄 takeaway: "평소 EKS = 0 노드 · T-30분 워밍업 · T+1h 자동 종료"

### 발표 멘트
"메인 시나리오는 이렇습니다. 예매 오픈 30분 전, CloudWatch나 스케줄 트리거로 Karpenter가 EC2를 미리 띄웁니다. EKS join까지 5분, 이미지 pull 2분, 애플리케이션 워밍업 20분 거쳐서 T-0 예매 오픈 시점엔 이미 서버가 준비된 상태입니다. 피크 한 시간 후 트래픽이 안정되면 다시 0 노드로 돌아갑니다."

---

## 05. 설계 원칙 4가지 [다크]

### 한 메시지
시나리오를 풀기 위한 4가지 설계 원칙

### 들어갈 내용
- 4개 카드 (세로 또는 2x2)
- 각 카드:
  - 번호 (01~04)
  - 원칙 이름
  - 1줄 설명

**원칙 4종**:
1. **HA** — 예매 중 1분 다운 = 환불 폭탄
2. **계층 분리** — DMZ / Internal / Management 경계 명확
3. **GitOps** — 선언적 운영 + burst 시에도 동일 배포
4. **하이브리드** — 평시 비용 최소 + 피크 확장 보장

### 발표 멘트
"이 시나리오를 풀기 위해 4가지 원칙을 세웠습니다. 첫째 HA — 예매 중 1분이라도 다운되면 환불 사태입니다. 둘째 계층 분리 — DMZ와 내부망의 신뢰 경계를 명확히 했습니다. 셋째 GitOps — 모든 배포가 Git에서 선언되고, 같은 코드로 온프레와 EKS 양쪽에 배포됩니다. 넷째 하이브리드 — 평시 비용을 최소화하면서 피크 시 확장을 보장합니다."

---

## 06. 한 장 아키텍처 [다크] · 직접 그리실 슬라이드

### 한 메시지
전체 토폴로지 — 온프레 ↔ VPN ↔ AWS

### 들어갈 내용
- 발표자 A가 직접 그릴 빈 영역 (점선 외곽)
- 가이드 라벨: "On-Prem ↔ VPN ↔ AWS"
- 4 파트 영역 색 구분 (A 회색 / B 초록 / C 파랑 / D 빨강 — 또는 단일 톤)
- 다음 3명에게 화살표로 패스

### 그릴 요소 (참고)
- 좌측 ON-PREMISE
  - pfSense HA (DMZ)
  - Proxmox 4 노드
  - K8s 클러스터 (CP×3 + Worker×4 + sys×1)
  - Ceph 6 노드 (RBD + RGW)
- 중앙 VPN 터널 (점선)
- 우측 AWS Cloud
  - VPC 10.20.0.0/16
  - AZ A / AZ C (2 AZ)
  - NAT GW · NLB · EC2 HAProxy
  - EKS (Karpenter) · RDS Read Replica

### 발표 멘트
"전체 그림입니다. 좌측은 우리 자체 인프라 — Proxmox 4대 위에 K8s 클러스터, Ceph 6대 별도 클러스터로 스토리지를 만들었습니다. 우측은 AWS VPC인데 평소엔 거의 비어있고, 트래픽 burst 시에만 EKS 노드가 떠서 트래픽을 받습니다. 두 환경은 IPsec VPN으로 연결돼서 같은 LAN처럼 동작합니다."

---

## 07. K8s 플랫폼 설계 [다크] · DEEP DIVE 1

### 한 메시지
K8s 클러스터의 4가지 핵심 설계 선택 + 실측 5.34 Gbps Pod-to-Pod

### 들어갈 내용
- 4개 카드 (2x2 그리드)
- 각 카드: 영역 라벨 + 1 키워드 + 1~2줄 설명
- 1개 핵심 KPI: **5.34 Gbps**

**카드 4종**:
1. **CONTROL PLANE** · stacked etcd × 3
   - kubeadm 1.30 HA
   - etcd가 CP와 함께 (separate etcd 대비 단순)
2. **CNI** · Calico (IPIP mode)
   - BGP/IPIP/VXLAN 가능, IPIP 채택
   - 외부 BGP 라우터 불필요
3. **INGRESS** · HAProxy Ingress v0.16.1
   - jcmoraisjr/haproxy-ingress (nginx 아님)
   - HAProxy 일관성 (Edge L7과 동일 스택)
4. **LOAD BALANCER** · MetalLB L2 mode
   - 베어메탈 K8s LoadBalancer 구현
   - ARP/NDP로 VIP advertise (172.16.23.50)

### 강조 수치
- Pod ↔ Pod 5.34 Gbps (실측, iperf3로 검증)

### 발표 멘트
"K8s 클러스터를 어떻게 설계했는지 짚고 갑니다. 컨트롤 플레인은 3대로 stacked etcd 구성 — etcd 노드를 따로 두지 않고 컨트롤 플레인과 같이 둬서 단순합니다. CNI는 Calico IPIP 모드 — 외부 BGP 라우터가 없는 환경이라 IPIP를 선택했고, 실측 결과 Pod 간 5.34 Gbps 나옵니다. 10G NIC을 잘 사용 중이라는 증거입니다. Ingress는 HAProxy Ingress, Edge L7과 같은 스택으로 통일했습니다. LoadBalancer는 MetalLB L2 모드 — 베어메탈에서 LoadBalancer Service를 구현하는 표준 방식입니다."

---

## 08. 다층 HA 통합 + AWS 로드맵 [다크] · DEEP DIVE 2 (통합)

### 한 메시지
4 계층 HA 메커니즘 + AWS Phase 1~5 단계별 로드맵

### 들어갈 내용 (좌/우 2분할)

**좌측 — 다층 HA 다이어그램**
- 4 계층 표 또는 다이어그램:
  - L1 Perimeter — pfSense HA · CARP + pfsync
  - L2 K8s API — lb-1/lb-2 · Keepalived · VIP 172.16.23.5
  - L3 Edge L7 — edge-haproxy × 2 · Keepalived · VIP 172.16.22.5
  - L4 K8s Ingress — MetalLB L2 ARP · 172.16.23.50

**우측 — AWS Phase 로드맵**
- 5 Phase 세로 카드 (각 1 키워드 + 상태 뱃지)
  - Phase 1: VPC Foundation · DONE
  - Phase 2: Site-to-Site VPN · DONE
  - Phase 3: RDS Replication · PLAN
  - Phase 4: EKS Burst (Karpenter + multi-cluster ArgoCD) · PLAN
  - Phase 5: Prod Hardening (WAF, Terraform) · PLAN

### 강조 수치
- 3 VIP
- 4 HA 계층
- Phase 2/5 완료

### 발표 멘트
"HA는 4 계층으로 구성했습니다. 외부 경계는 pfSense HA, K8s API는 lb-1/2 Keepalived로 VIP 172.16.23.5, Edge L7도 같은 패턴으로 VIP 172.16.22.5, 마지막으로 K8s Ingress는 MetalLB L2 ARP로 172.16.23.50을 advertise합니다. 한 계층이 죽어도 다음 계층이 살아있는 구조입니다. AWS 쪽은 Phase 1~5 로드맵으로 진행 중인데, 현재 VPC와 VPN까지 완료, RDS·EKS·하드닝은 다음 단계입니다. 자세한 내용은 데이터 담당자가 RDS, 보안 담당자가 VPN 깊이 다룰 예정입니다."

### 다음 발표자에게 패스
"여기서부터 데이터·스토리지 담당 ○○님이 더 깊이 들어가겠습니다."
