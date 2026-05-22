# 06. 전체 비용 + SPoF + Trade-off 종합

> ⭐ **한 줄 요약**: 월 TCO 약 **₩47만 (온프레 ₩30만 + AWS $130)**. 100% AWS 대비 **약 70% 절감**. 가장 큰 SPoF는 **sys1 단일 노드**, Phase 6에서 sys2 추가로 해소.

---

## 💰 전체 TCO (Total Cost of Ownership)

### 온프레미스 (월간)
| 항목 | 계산 | 월 비용 |
|---|---|---|
| **전기** | 880W × 24h × 30d × ₩125/kWh | ₩79,000 |
| **하드웨어 감가** | CapEx ₩1,660만 ÷ 60개월 | ₩277,000 |
| **인터넷 회선** | 사무실 공유 | ₩0 (분담시 ~₩30,000) |
| **인건비 (운영)** | 0.1 FTE × ₩400만 | ₩400,000 |
| **소계** | | **~₩756,000** |
| (인건비 제외) | | **~₩356,000** |

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

### 전체 합계
- 인건비 포함: **약 ₩105만/월**
- 인건비 제외: **약 ₩65만/월**

---

## 💸 100% AWS로 했을 때 (비교)

| 자원 | 단가 | 월 비용 |
|---|---|---|
| EC2 m5.xlarge × 4 (Worker 대체) | $0.192/h × 4 × 720h | $553 |
| EC2 m5.large × 3 (CP 대체) | $0.096/h × 3 × 720h | $207 |
| EBS gp3 6TB (Ceph 대체) | $0.08/GB × 6000GB | $480 |
| RDS db.t3.medium HA | $0.068/h × 720h × 2 | $98 |
| NAT GW × 2 | $66 | $66 |
| NLB × 2 (Edge + Ingress) | $32 | $32 |
| Route 53 + CloudFront + WAF | ~$15 | $15 |
| 데이터 전송 (outbound 100GB) | $0.126 × 100 | $12 |
| 인건비 (관리형 SaaS 가정 0.05 FTE) | ₩200,000 | $150 |
| **소계** | | **~$1,613/월 = ₩212만/월** |

→ **하이브리드가 약 50~70% 절감** (인건비 제외 비교 시)

> 🔥 **단**: 초기 투자금 ₩1,660만 회수 ~5년. 학습/실습 환경엔 매몰 비용 활용 합리적.

---

## 🚨 SPoF 분석 (위험 점수 ★ 1~5)

### 정량적 평가

| # | SPoF | 영향 | 발생 확률 | 회복 시간 | 위험 점수 | Phase 6 해소 |
|---|---|---|---|---|---|---|
| 1 | **sys1 단일 노드** | 모니터링/Harbor/Jenkins/ArgoCD 전부 down | 중 | 30분~수시간 | **★★★★★** | sys2 추가 |
| 2 | **Ceph RGW 단일 daemon** | Harbor push/pull 불가 | 중 | 1시간 | **★★★★** | RGW 2개 |
| 3 | **etcd quorum loss (CP 2대 죽음)** | K8s API write 차단 | 낮 | 수시간 | **★★★** | external etcd 5-node |
| 4 | **MetalLB speaker** | LB IP ARP 응답 멈춤 | 중 | 5분 | **★★★** | BGP 모드 전환 |
| 5 | **Edge HAProxy split-brain** | 외부 트래픽 disrupted (ARP 갈등) | 낮 | 10분 | **★★★** | GARP 강화 (적용됨) |
| 6 | **K8s API VIP (lb-1/lb-2)** | kubectl 멈춤 | 낮 | 수초 (Keepalived 자동) | **★★** | 적용됨 |
| 7 | **pfSense MASTER 죽음** | 자동 failover | 낮 | 수초 | **★** | 적용됨 |
| 8 | **NAT GW AZ별** | 그 AZ outbound 끊김 | 낮 | 수동 RT 전환 | **★★** | 이미 2 AZ |
| 9 | **자체 CA 만료 (10년)** | 모든 cert 망가짐 | 매우 낮 | 1주+ | **★** (장기) | 9년 catalog |
| 10 | **PXC quorum loss** | DB write 차단 | 낮 | 1시간+ | **★★★** | PXC 5-node 또는 외부 backup |
| 11 | **Redis Sentinel quorum** | Redis read/write fail | 낮 | 수초 (자동 failover) | **★** | 적용됨 (3 sentinel) |
| 12 | **RDS replica down** | EKS Pod read 불가 | 낮 | RDS reboot | **★** | Multi-AZ RDS |

### 가장 시급한 SPoF 3개 → 해소 계획

#### #1 sys1 단일 노드 (★★★★★)
- **현황**: 모든 system 워크로드가 sys1 하나에
- **계획**: Phase 6에서 sys2 추가
- **작업**:
  ```
  1. Proxmox에 VM 생성 (16GB RAM, 4vCPU)
  2. K8s join (kubeadm token)
  3. label: workload-type=system
  4. helm values 업데이트 (Prometheus replicas: 2 등)
  5. anti-affinity 설정 (sys1/sys2에 분산)
  ```
- **소요**: 4~6시간

#### #2 Ceph RGW 단일 daemon (★★★★)
- **현황**: ceph1에만 RGW 실행
- **계획**: ceph2에 RGW 추가 (총 2 instance)
- **작업**:
  ```
  ceph2에서 radosgw 데몬 추가 + endpoint 2개로 등록
  Harbor regionendpoint를 HAProxy 통해 round-robin
  ```
- **소요**: 2시간

#### #4 MetalLB speaker (★★★)
- **현황**: L2 모드 (단일 노드 ARP 응답)
- **계획**: 가능하면 BGP 모드 전환 (외부 BGP 라우터 필요)
- **대안**: L2 모드 유지 + speaker 재시작 모니터링
- **소요**: BGP는 ★★★★ (라우터 설정 + 학습)

---

## ⚖️ 트레이드오프 종합 (의식적 선택의 결과)

### 우리가 일부러 포기한 것들 (의도적)

| 포기 | 이유 | 결과 |
|---|---|---|
| 베어메탈 K8s 성능 | Proxmox로 격리/snapshot 얻음 | 5~10% 가상화 오버헤드 |
| Rook-Ceph 단순함 | 별도 클러스터로 장애 격리 | 6 노드 추가 비용 |
| Let's Encrypt 신뢰성 | 자체 CA로 내부망 도메인 사용 | 외부 신뢰 X (내부 cert 신뢰 등록 필요) |
| GHA self-hosted runner 모던함 | Jenkins로 즉시 동작 | YAML 워크플로 편의 X |
| 진짜 zero-trust (모든 ns NetworkPolicy) | ticket-app만 적용 (학습/시간) | 다른 ns는 default permit |
| 진짜 HA (sys1 → sys2) | Phase 6로 미룸 | sys1 SPoF 1개 남음 |
| Sealed Secrets | Phase 6로 미룸 | Secret 평문 base64 (Git commit 불가) |
| 진짜 backup 자동화 | Phase 6로 미룸 | 수동 백업 의존 |

→ 모두 **의식적 선택**. 학습/데모 우선순위와 트레이드오프 분석 결과.

---

## 🚀 미래 확장 — 우선순위 로드맵

### 🔴 Phase 6 (즉시 실행 권장, 운영급 진입)
1. **sys2 추가** (sys1 SPoF 해소) — 4시간
2. **Ceph RGW 2개로** — 2시간
3. **etcd backup CronJob** — 2시간
4. **Sealed Secrets 도입** — 4시간
5. **AlertManager webhook 인증 추가** — 2시간

### 🟡 Phase 7 (중기, 안정성 강화)
1. **PXC backup 자동화 (Percona xtrabackup → S3)** — 1일
2. **Ceph snapshot 정책** — 1일
3. **monitoring HA (Prometheus replicas 2 + Thanos)** — 3일
4. **Multi-cluster ArgoCD (온프레 + EKS)** — 2일

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
| 데이터 손실 사고 | Phase 7 #1, #2 |
| 새 마이크로서비스 자주 추가 | Phase 8 #1 service mesh |

---

## 🔗 다른 파트와의 연결

전체 비용/SPoF는 모든 파트에 영향:
- 💾 데이터: Ceph SPoF, PXC SPoF → `data-storage/` 참고
- 🔧 CI/CD: Jenkins/Harbor SPoF → `cicd/` 참고
- 🔒 보안: 보안 정책에 영향, 백업도 보안 영역 → `security/08-backup-dr-policy.md`

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 비용 절감 70% 어떻게 계산?**
A. 동일 워크로드 100% AWS 가설 ₩212만/월 vs 우리 하이브리드 ₩65만/월 (인건비 제외). 단, 초기 투자금 ₩1660만 회수 5년 가정. 운영 인건비 포함하면 비교 다름.

**Q2. SPoF 분석에서 #1 sys1을 왜 미뤘나?**
A. (1) 학습 환경 자원 빡빡 (Proxmox RAM 75% 사용), (2) 4명 팀이 진짜 운영 X, (3) 발표 데모는 sys1 1대로 충분히 동작. 운영 진입 시 Phase 6 첫 작업으로 명시.

**Q3. 진짜 운영이면 가장 먼저 뭐 고치겠나?**
A. (1) sys2 추가, (2) backup 자동화, (3) Sealed Secrets, (4) cert-manager에 Let's Encrypt 추가 (외부 cert), (5) PCI/HIPAA면 OPA/Gatekeeper.

**Q4. AWS 비용을 더 줄이려면?**
A. (1) VPC Endpoint로 NAT GW 데이터비 절감, (2) NAT GW 1개로 줄임 (HA 포기), (3) RDS replica 끔 (burst 시만 켬), (4) Reserved Instance (EC2 1년 약정). (5) CloudFront cache hit 늘리면 origin 트래픽 ↓.

**Q5. 트레이드오프 가장 후회되는 거?**
A. Jenkins SCM Polling 선택 (Webhook 못 받는 NAT 환경 한계). 정상 환경이면 webhook 사용 권장. 또는 GHA 진짜 마이그레이션도 검토 가능.
