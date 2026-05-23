# 06. 전체 비용 + SPoF + Trade-off 종합

> ⭐ **한 줄 요약**: 월 TCO 약 **₩47만 (온프레 ₩30만 + AWS $130)**, 100% AWS 대비 **약 70% 절감**. 가장 큰 SPoF는 **sys1 단일 노드**고 Phase 6에서 sys2 추가로 해소 예정. 그 다음은 모든 게 K8s 위에 있는 **Bootstrap 의존성 문제**.

---

## 💰 전체 TCO (Total Cost of Ownership)

우리 인프라의 진짜 비용을 따져보면 온프레미스가 약 ₩30만/월, AWS가 약 ₩30만/월로 합치면 월 ₩60만 수준이다. 인건비 (운영 0.1 FTE)까지 포함하면 ₩100만 수준이다. 같은 워크로드를 100% AWS로 가져가면 ₩200만+이 들어, 우리 하이브리드 패턴이 약 50~70% 절감 효과가 있다.

### 온프레미스 (월간)

| 항목 | 계산 | 월 비용 |
|---|---|---|
| **전기** | 880W × 24h × 30d × ₩125/kWh | ₩79,000 |
| **하드웨어 감가** | CapEx ₩1,660만 ÷ 60개월 | ₩277,000 |
| **인터넷 회선** | 사무실 공유 | ₩0 (분담시 ~₩30,000) |
| **인건비 (운영)** | 0.1 FTE × ₩400만 | ₩400,000 |
| **소계** | | **~₩756,000** |
| (인건비 제외) | | **~₩356,000** |

전기료가 의외로 작다 (월 ₩8만). 가장 큰 건 하드웨어 감가상각인데, ₩1660만을 5년 정액 감가하면 월 ₩28만이다. 인건비를 제외하고 운영비만 보면 월 ₩36만 정도다.

### AWS (월간, Phase 1-5)

| 자원 | 비용 |
|---|---|
| VPN | $36 |
| NAT GW × 2 | $66 |
| EC2 t3.micro × 2 | $15 |
| NLB | $16 |
| EKS 제어 평면 | $72 |
| RDS db.t3.micro replica | $12 |
| CloudFront | ~$1 |
| AWS WAF | ~$10 |
| Lambda + API GW | ~$1 |
| Route 53 | ~$1 |
| 데이터 전송 | ~$2 |
| **소계** | **~$232/월 = ₩30만/월** |

AWS 비용에서 가장 큰 비중은 EKS 제어 평면 ($72/월)과 NAT GW ($66/월 = $33 × 2)다. EKS 제어 평면은 클러스터 1개당 무조건 부과되는 base cost라 회피 어렵고, NAT GW는 VPC Endpoint 도입으로 데이터비를 줄일 수 있다.

### 전체 합계

- 인건비 포함: **약 ₩105만/월**
- 인건비 제외: **약 ₩65만/월**

---

## 💸 100% AWS로 했을 때 — 비교

같은 워크로드를 AWS만으로 운영한다고 가정해보자.

| 자원 | 단가 | 월 비용 |
|---|---|---|
| EC2 m5.xlarge × 4 (Worker 대체) | $0.192/h × 4 × 720h | $553 |
| EC2 m5.large × 3 (CP 대체) | $0.096/h × 3 × 720h | $207 |
| EBS gp3 6TB (Ceph 대체) | $0.08/GB × 6000GB | $480 |
| RDS db.t3.medium HA | $0.068/h × 720h × 2 | $98 |
| NAT GW × 2 | $66 | $66 |
| NLB × 2 (Edge + Ingress) | $32 | $32 |
| Route 53 + CloudFront + WAF | ~$15 | $15 |
| 데이터 전송 | $0.126 × 100 | $12 |
| 인건비 (SaaS 가정 0.05 FTE) | ₩200,000 | $150 |
| **소계** | | **~$1,613/월 = ₩212만/월** |

→ **하이브리드가 약 50~70% 절감** (인건비 제외 비교 시).

이 비교에서 흥미로운 점은 **EBS가 가장 큰 비중**이라는 거다 (월 $480). Ceph를 자체 호스팅하니 같은 6TB가 우리 환경에선 거의 무료다. 또 EC2도 큰 비중인데, Proxmox 위 VM이 우리한텐 호스트 자원만 쓰는 셈이라 사실상 무료다.

> 🔥 **핵심**: 초기 투자금 ₩1,660만 회수 ~5년. **학습/실습 환경엔 매몰 비용 활용이 합리적**.

---

## 🚨 SPoF 분석 — 위험 점수 ★ 1~5

### 정량적 평가

각 SPoF를 영향, 발생 확률, 회복 시간을 종합해 위험 점수 ★1~5로 평가했다.

| # | SPoF | 영향 | 발생 확률 | 회복 시간 | 위험 | Phase 6 해소 |
|---|---|---|---|---|---|---|
| 1 | **sys1 단일 노드** | 모니터링/Harbor/Jenkins/ArgoCD 전부 down | 중 | 30분~수시간 | **★★★★★** | sys2 추가 |
| 2 | **Ceph RGW 단일 daemon** | Harbor push/pull 불가 | 중 | 1시간 | **★★★★** | RGW 2개 |
| 3 | **etcd quorum loss (CP 2대 죽음)** | K8s API write 차단 | 낮 | 수시간 | **★★★** | external etcd 5-node |
| 4 | **MetalLB speaker** | LB IP ARP 응답 멈춤 | 중 | 5분 | **★★★** | BGP 모드 전환 |
| 5 | **Edge HAProxy split-brain** | 외부 트래픽 disrupted | 낮 | 10분 | **★★★** | GARP 강화 (적용됨) |
| 6 | **K8s API VIP** | kubectl 멈춤 | 낮 | 수초 (자동) | **★★** | 적용됨 |
| 7 | **pfSense MASTER 죽음** | 자동 failover | 낮 | 수초 | **★** | 적용됨 |
| 8 | **NAT GW AZ별** | 그 AZ outbound 끊김 | 낮 | 수동 RT 전환 | **★★** | 이미 2 AZ |
| 9 | **자체 CA 만료 (10년)** | 모든 cert 망가짐 | 매우 낮 | 1주+ | **★** (장기) | 9년 catalog |
| 10 | **PXC quorum loss** | DB write 차단 | 낮 | 1시간+ | **★★★** | PXC 5-node 또는 외부 backup |
| 11 | **Redis Sentinel quorum** | Redis read/write fail | 낮 | 수초 (자동) | **★** | 적용됨 (3 sentinel) |
| 12 | **RDS replica down** | EKS Pod read 불가 | 낮 | RDS reboot | **★** | Multi-AZ RDS |
| 13 | **모든 서비스가 K8s 위에 (Circular Dependency)** | K8s 죽으면 K8s 살릴 도구(Jenkins/ArgoCD)도 죽음 | 낮 | 수동 etcd restore + manual rebuild | **★★★★** | CI/CD VM 분리 (Phase 6) — `07-bootstrap-resilience.md` |
| 14 | **워커노드 자동 프로비저닝 없음** | 워커 자원 부족시 Pod Pending 무한 대기 → 사람 수동 개입 | 중 | 사람 수동 (Proxmox UI + kubeadm join 30분+) | **★★★** | Terraform + Ansible 자동화 (Phase 7) — `08-onprem-autoscaling.md` |

### 가장 시급한 SPoF — 시나리오 + 해소 계획

#### #1 sys1 단일 노드 (★★★★★)

**현황**: 모든 system 워크로드 (Prometheus, Grafana, Harbor, Jenkins, ArgoCD, Tempo, Loki)가 sys1에 집중돼 있다. sys1이 죽으면 모니터링 + CI/CD + 레지스트리 전부 down된다.

**계획**: Phase 6에서 sys2 추가. 작업은 (1) Proxmox에 VM 생성 (16GB RAM, 4 vCPU), (2) K8s join (kubeadm token), (3) label `workload-type=system` 추가, (4) helm values 업데이트로 Prometheus replicas 2 등 적용, (5) anti-affinity로 sys1/sys2 분산 배치. 총 4~6시간.

#### #2 Ceph RGW 단일 daemon (★★★★)

**현황**: ceph1 노드에만 RGW 데몬이 실행 중. 이 노드가 죽으면 Harbor의 S3 backend가 끊겨 image push/pull 불가.

**계획**: ceph2 노드에 RGW 추가 (총 2 instance). Harbor regionendpoint를 HAProxy 통해 round-robin. 작업 2시간.

#### #4 MetalLB speaker (★★★)

**현황**: L2 모드는 단일 노드가 ARP 응답을 담당. 그 노드 죽으면 LB IP가 잠시 끊긴다.

**계획**: 외부 BGP 라우터가 있으면 BGP 모드로 전환이 정석이지만, 우리 환경엔 없다. L2 모드 유지 + speaker restart 모니터링이 현실적 대응.

---

## ⚖️ 트레이드오프 종합 (의식적 선택의 결과)

우리가 의식적으로 포기한 것들을 정리하면, **모두 학습/데모 우선순위와의 trade-off 결과**다.

| 포기 | 이유 | 결과 |
|---|---|---|
| 베어메탈 K8s 성능 | Proxmox로 격리/snapshot 얻음 | 5~10% 가상화 오버헤드 |
| Rook-Ceph 단순함 | 별도 클러스터로 장애 격리 | 6 노드 추가 비용 |
| Let's Encrypt 신뢰성 | 자체 CA로 내부망 도메인 사용 | 외부 신뢰 X (내부 cert 신뢰 등록 필요) |
| GHA self-hosted runner | Jenkins로 즉시 동작 | YAML 워크플로 편의 X |
| 진짜 zero-trust | ticket-app만 NetworkPolicy 적용 | 다른 ns default permit |
| 진짜 HA (sys1 → sys2) | Phase 6로 미룸 | sys1 SPoF 1개 남음 |
| Sealed Secrets | Phase 6로 미룸 | Secret 평문 base64 (Git commit 불가) |
| 진짜 backup 자동화 | Phase 6로 미룸 | 수동 백업 의존 |

이 표가 중요한 이유는, **모두 의식적 선택**이라는 점이다. 약점을 모르고 한 게 아니라 우선순위와 자원 한계를 고려해 일부러 미룬 것들이다. 면접에서 "이거 약점 아닌가요?"라고 물으면 "네, 알고 있고 Phase 6에서 해소 계획 있습니다"로 답할 수 있다.

---

## 🚀 미래 확장 — 우선순위 로드맵

### 🔴 Phase 6 (즉시 실행, 운영급 진입)

1. **sys2 추가** (sys1 SPoF 해소) — 4시간
2. **Ceph RGW 2개로** — 2시간
3. **etcd backup CronJob** — 2시간
4. **Sealed Secrets 도입** — 4시간
5. **AlertManager webhook 인증 추가** — 2시간
6. **CI/CD VM 분리** (Bootstrap 보호) — 1~2일 — `07-bootstrap-resilience.md`
7. **DR Runbook 작성 + 분기 훈련 일정** — 1주 — `07-bootstrap-resilience.md`

### 🟡 Phase 7 (중기, 안정성 강화)

1. **PXC backup 자동화 (xtrabackup → S3)** — 1일
2. **Ceph snapshot 정책** — 1일
3. **monitoring HA (Prometheus replicas 2 + Thanos)** — 3일
4. **Multi-cluster ArgoCD (온프레 + EKS)** — 2일
5. **온프레 워커 자동 프로비저닝 (Terraform + Ansible)** — 2주 — `08-onprem-autoscaling.md`

### 🟢 Phase 8 (장기, 진짜 운영)

1. **Service mesh (Linkerd)** — 1주
2. **APM Pyroscope** — 2일
3. **OPA/Gatekeeper** — 3일
4. **Cilium 전환** — 1주
5. **Multi-region AWS** — 1개월

---

## 📊 의사결정 매트릭스 (전체)

| 신호 / 상황 | 우선 액션 |
|---|---|
| sys1 OOM 잦음 | Phase 6 #1 sys2 |
| Harbor push 실패 | Phase 6 #2 RGW 2개 |
| K8s 사고 후 etcd 복구 어려움 | Phase 6 #3 etcd backup |
| Secret 관리 부담 | Phase 6 #4 Sealed Secrets |
| 보안 감사 | Phase 6 #5 webhook 인증 |
| K8s 죽으면 복구 어려움 | Phase 6 #6, #7 (CI/CD 분리 + Runbook) |
| 데이터 손실 사고 | Phase 7 #1, #2 |
| 새 마이크로서비스 자주 추가 | Phase 8 #1 service mesh |

---

## 🔗 다른 파트와의 연결

전체 비용/SPoF는 모든 파트에 영향을 준다. 데이터 측면에선 Ceph SPoF와 PXC SPoF (`data-storage/`), CI/CD에선 Jenkins/Harbor SPoF (`cicd/`), 보안에선 정책 + 백업/DR (`security/08-backup-dr-policy.md`)이 모두 관련된다. Bootstrap 의존성과 자동화 확장은 `07-bootstrap-resilience.md`와 `08-onprem-autoscaling.md`에서 깊이 다룬다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 비용 절감 70%를 어떻게 계산했나요?**

A. 동일 워크로드를 100% AWS로 가져가면 가설 비용 **₩212만/월**이고, 우리 하이브리드는 **₩65만/월** (인건비 제외)입니다. 단 초기 투자금 ₩1660만 회수 5년 가정입니다. 운영 인건비 포함하면 비교 다르고, 사실 SaaS는 인건비 ↓라 단순 비교는 조심해야 합니다.

**Q2. SPoF 분석에서 #1 sys1을 왜 미뤘나요?**

A. 세 가지 이유입니다. **첫째, 학습 환경 자원 빡빡** (Proxmox RAM 75% 사용). **둘째, 4명 팀이 진짜 운영 X**라 우선순위 ↓. **셋째, 발표 데모는 sys1 1대로 충분히 동작**. 운영 진입 시 Phase 6 첫 작업으로 명시하고 발표 문서에선 sys1+sys2 가정으로 HA 설계 보여줍니다.

**Q3. 진짜 운영이면 가장 먼저 뭐 고치겠어요?**

A. 순서대로 (1) **sys2 추가** (가장 critical SPoF 해소), (2) **backup 자동화** (DR 대비), (3) **Sealed Secrets** (GitOps 완성 + Secret 보안), (4) **CI/CD VM 분리** (bootstrap 보호), (5) **cert-manager에 Let's Encrypt 추가** (외부 cert). PCI/HIPAA 같은 컴플라이언스 필요하면 OPA/Gatekeeper도 추가합니다.

**Q4. AWS 비용을 더 줄이려면 어떻게 하나요?**

A. 다섯 가지 옵션이 있습니다. (1) **VPC Endpoint로 NAT GW 데이터비 절감** (가장 효과적), (2) **NAT GW 1개로 줄임** (HA 포기), (3) **RDS replica를 burst 시만 켜기**, (4) **Reserved Instance** (EC2 1년 약정으로 30~40% 절감), (5) **CloudFront cache hit 늘리면 origin 트래픽 ↓**. 우선순위는 VPC Endpoint입니다.

**Q5. 트레이드오프 중 가장 후회되는 건요?**

A. **Jenkins SCM Polling 선택**입니다. Webhook을 못 받는 NAT 환경 한계 때문에 polling으로 갔는데, 즉시성 (1~2분 지연)이 아쉽습니다. 정상 환경이면 webhook 권장이고, GHA 진짜 마이그레이션도 검토 가능합니다. 다만 ARC 함정 (PVC fsGroup)으로 후퇴한 경험은 학습 가치가 있었습니다.
