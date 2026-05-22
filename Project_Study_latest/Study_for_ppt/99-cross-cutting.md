# 99. 파트 경계 넘는 토픽들 (Cross-cutting)

> ⭐ **이 문서의 정체**: 우리 분담(아키텍처/데이터/CI/CD/보안)은 깔끔하지만, 실제 시스템은 **여러 파트에 걸친 컴포넌트**가 많음. 면접/발표에서 "그건 누가 담당?" 같은 질문이 들어오면 이 문서로 답.

---

## 🧩 Cross-cutting 토픽 매핑

| 토픽 | 관련 파트들 | 각 파트가 보는 관점 |
|---|---|---|
| 🏰 **Harbor** | CI/CD + 데이터 + 보안 | CI/CD: 이미지 push/pull. 데이터: Ceph RGW S3 backend. 보안: Trivy 스캔 + RBAC |
| 🛡️ **pfSense** | 아키텍처 + 보안 | 아키텍처: 라우팅/VLAN GW. 보안: 방화벽 정책 + DNS |
| 🔁 **ArgoCD** | CI/CD + 보안 | CI/CD: 자동 배포. 보안: K8s RBAC + git access |
| 📊 **Observability 스택** | 아키텍처 + 데이터 + 보안 | 아키텍처: 배치/topology. 데이터: TSDB/Trace/Log 저장. 보안: 인증/접근 |
| 🚀 **Burst Trigger** | 아키텍처 + CI/CD + 보안 | 아키텍처: 전체 흐름. CI/CD: Lambda 배포. 보안: webhook 인증 |
| 🔐 **자체 CA + cert-manager** | 보안 + 아키텍처 + CI/CD | 보안: 정책. 아키텍처: 배치. CI/CD: Harbor cert 신뢰 |
| 🌐 **NetworkPolicy** | 보안 + 아키텍처 | 보안: zero-trust 정책. 아키텍처: Calico CNI 의존 |
| 💽 **PXC ↔ RDS Replication** | 데이터 + 아키텍처 + 보안 | 데이터: binlog 복제. 아키텍처: VPN 위. 보안: replication user |
| 🔄 **Backup/DR** | 보안 + 데이터 + 아키텍처 | 보안: 정책. 데이터: Ceph/PXC 백업. 아키텍처: DR 전체 흐름 |

---

## 🔍 핵심 cross-cutting 토픽 5개 깊이 분석

### 1. 🏰 Harbor — CI/CD + 데이터 + 보안 동시 만족

**역할 분담**:
```
[CI/CD 파트가 관리]
  - Jenkins가 push할 credential (harbor-creds-dockerconfigjson)
  - 이미지 tag 정책 (semver vs build number)
  - 보관 정책 (latest + N개 retain)

[데이터 파트가 관리]
  - Ceph RGW endpoint (10.10.10.11:7480)
  - bucket: harbor-registry (수동 생성 필요)
  - Storage class: team2-rbd-block (metadata DB는 RBD)

[보안 파트가 관리]
  - admin 비밀번호 (kosa1004 → 운영 시 vault)
  - Trivy 이미지 취약점 스캔
  - imagePullSecret 분배 (각 namespace에)
  - 자체 CA로 Harbor cert 발급
```

**한 곳이 망가지면**:
- Ceph RGW 죽음 → 이미지 push 실패 (메타데이터 DB는 살아있어서 UI는 동작)
- Trivy 스캐너 죽음 → 새 이미지 무방비 (push는 가능)
- Harbor core DB 죽음 → UI/API 다운

**연관 문서**:
- `cicd/04-harbor-registry.md`
- `data-storage/04-s3-comparison.md` (왜 Ceph RGW backend)
- `security/05-secrets-rbac.md`

---

### 2. 🛡️ pfSense — 아키텍처 + 보안 이중 역할

**아키텍처적 역할**:
- VLAN 10/20/30/40 게이트웨이
- DNS Resolver (Host Overrides로 *.kosa.team2 → 172.16.23.50)
- WAN ↔ Internal 라우팅
- Outbound NAT (인터넷 접속) + bypass (VPN용)

**보안적 역할**:
- 방화벽 정책 (외부 → 내부 허용 규칙)
- IPsec VPN (AWS와 site-to-site)
- Port Forward (외부 노출 정확히 명시)
- HA (CARP) → 단일 노드 죽어도 정책 유지

**왜 같은 장비가 둘 다 하나?**:
- pfSense는 통합 FW/router/VPN 어플라이언스
- 별도로 분리하려면 라우터 + 방화벽 장비 2대 + 정책 동기화 부담
- 데모/소규모엔 통합이 합리적

**연관 문서**:
- `architecture/01-physical-and-network.md`
- `security/01-pfsense-firewall.md`

---

### 3. 📊 Observability — 3개 파트 다 참여

```
[아키텍처가 결정]
  - Prometheus/Grafana/Tempo/Loki를 sys1에 배치
  - kube-prometheus-stack 통합 helm chart 선택
  - AlertManager → email + AWS Lambda webhook 2개 routing
  - OpenTelemetry Operator로 auto-instrumentation

[데이터가 결정]
  - Prometheus TSDB: RBD PVC 10Gi (7일 retention)
  - Loki: RBD PVC 20Gi (7일) — 운영시 Ceph RGW S3로 전환 권장
  - Tempo: RBD PVC 10Gi
  - 백업 정책 (Prometheus 메트릭은 휘발 OK, Loki는 보존 정책 필요)

[보안이 결정]
  - Grafana 외부 노출 (Edge HAProxy → grafana.kosa.team2)
  - admin 비밀번호 + OAuth 통합 (미래)
  - Loki/Tempo는 내부만 (외부 노출 X)
  - AlertManager webhook은 인증 (현재 무인증 — 개선 필요)
```

**연관 문서**:
- `architecture/05-observability-design.md`
- `data-storage/04-s3-comparison.md` (Loki S3 전환)
- `security/05-secrets-rbac.md` (Grafana 인증)

---

### 4. 🚀 Burst Trigger — 4파트 모두

**흐름**:
```
[관측/아키텍처]: Prometheus alert 조건 정의
   ↓
[CI/CD]: AlertManager가 webhook 호출 (Lambda)
   ↓
[아키텍처/AWS]: Lambda → Route 53 weight 변경
   ↓
[아키텍처/AWS]: 트래픽 NLB로 이동
   ↓
[아키텍처/EKS]: EKS HPA scale up → Karpenter Spot 노드 생성
   ↓
[데이터]: EKS Pod이 RDS (replica)에서 읽기
   ↓
[보안]: webhook 인증 (현재 무인증 — Phase 6 개선 필요)
```

**왜 4파트 모두?**:
- 한 컴포넌트만 봐선 안 됨, 전체 흐름 이해해야
- "burst 안 되면 어디부터 보나?" 같은 질문은 4파트 다 알아야 답

**연관 문서**:
- `architecture/04-burst-architecture.md` (메인)
- `security/06-burst-trigger-security.md`
- `data-storage/06-rds-replication.md`

---

### 5. 🔐 자체 CA + cert-manager — 보안 + 아키텍처 + CI/CD

**누가 뭘 관리?**:

| 파트 | 관리 항목 |
|---|---|
| 🔒 보안 | CA 정책 (10년 만료, key 보관, 회전 계획), service별 cert 발급 룰 |
| 🏛️ 아키텍처 | cert-manager 배치 (sys1), ClusterIssuer 설정, 이중 TLS 설계 |
| 🔧 CI/CD | Harbor cert (containerd 신뢰 등록), Jenkins-Harbor 통신 |

**왜 이중 TLS인가?**:
- DMZ(Edge) ↔ Internal(K8s) 신뢰 경계마다 종료
- 내부 트래픽도 wire에서 평문 X
- 외부 cert ↔ 내부 cert 독립 회전 가능

**연관 문서**:
- `security/02-tls-self-ca-double.md` (메인)
- `architecture/02-kubernetes-design.md` (cert-manager 배치)
- `cicd/04-harbor-registry.md` (Harbor cert)

---

## 🤝 4명이 함께 봐야 하는 시나리오

### 시나리오 1: "외부에서 Harbor에 push가 안 됩니다"

| 파트 | 확인할 것 |
|---|---|
| CI/CD | Harbor Pod 상태, Jenkins credentials, image push 명령 정확한지 |
| 데이터 | Ceph RGW 살아있는지 (`radosgw-admin user list`), bucket 존재 |
| 보안 | containerd가 Harbor cert 신뢰하는지 (`/etc/containerd/certs.d/`), imagePullSecret |
| 아키텍처 | pfSense Host Override (DNS), Edge HAProxy ACL (`harbor` 있는지), K8s Ingress |

→ "어디서 막혔지?"는 4파트 다 봐야 풀림.

### 시나리오 2: "alert email 안 옵니다"

| 파트 | 확인할 것 |
|---|---|
| 아키텍처 | AlertManager Pod, helm values, GitOps sync |
| 데이터 | secret store에 SMTP password 정상 |
| 보안 | Gmail App password 유효, SMTP 외부 outbound 허용 |
| CI/CD | (해당 적음) |

### 시나리오 3: "burst trigger 동작 안 함"

| 파트 | 확인할 것 |
|---|---|
| 아키텍처 | Prometheus alert firing 여부, Lambda 로그, R53 weight 실제 변경 |
| CI/CD | Lambda 코드 배포 상태, SSM Send Command 권한 |
| 데이터 | RDS replica replication lag |
| 보안 | Lambda IAM role, webhook 인증 |

---

## 📋 4명이 같이 결정해야 할 일들

1. **secret 관리**: Sealed Secrets vs External Secrets Operator vs HashiCorp Vault
2. **백업 주기/보관**: PXC 매일, Ceph snapshot 주간, etcd 4시간 등
3. **모니터링 알림 수준**: 어떤 alert를 누구에게 (severity별 routing)
4. **DR 시나리오 정의**: RTO/RPO 목표 + 회복 절차
5. **GitOps 정책**: 자동 sync vs 수동 승인, prune 정책, drift 처리

→ 각 항목은 4명 회의 + decision log 남기는 게 좋음.

---

## 🔥 Cross-cutting 발표 질문 (예상)

**Q. "Harbor가 죽으면 무엇이 영향?"**
A. (CI/CD) 새 이미지 push 안 됨, 이미 노드에 cached 된 이미지로 동작은 가능. (데이터) Ceph RGW 자체는 살아있을 수 있음. (보안) 이미지 스캔 일시 중단.

**Q. "한 사람이 휴가가면 시스템이 멈추나?"**
A. 운영은 4명 다 기본 안 함. 각자 deep-dive 영역이 있을 뿐. 비상 상황엔 다른 파트 docs 보고 대응 가능 (이 cross-cutting 문서가 도와줌).

**Q. "왜 분담을 이렇게 나눴나?"**
A. K8s 표준 분리 패턴 (App = CI/CD, Infra = 아키텍처/데이터, Sec = 보안). 학습 효율 + 면접 준비 ↑.

**Q. "다른 파트 결정에 영향 받은 경험?"**
A. 예시 — CI/CD에서 Jenkins 선택 → 보안에서 Jenkins admin password 정책 + RBAC 설계, 데이터에서 Jenkins config PVC backup 정책 추가.

---

## 🗂️ 빠르게 찾는 reference

**"~를 알고 싶다"**:
- 전체 흐름: `00-overview.md` + 본 문서
- 특정 컴포넌트: 위 매핑표 → 해당 파트 문서로
- 비용 분석: `architecture/06-cost-spof-tradeoffs.md`
- 장애 대응: `docs/onprem/12-operations.md` + `docs/onprem/incident-*.md`
