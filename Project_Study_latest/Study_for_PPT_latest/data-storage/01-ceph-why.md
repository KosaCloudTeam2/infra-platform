# 01. 왜 Ceph인가?

> ⭐ **한 줄 요약**: Ceph는 **분산 + 자가치유 + S3/Block/File 통합** 스토리지다. NFS는 단일 서버 SPoF, GlusterFS는 2022년 EOL, MinIO는 S3만, raw NVMe는 분산이 없다. **Ceph가 우리 환경에서 유일한 종합 해답**이었다.

---

## 🎯 우리가 한 선택

Ceph 6 노드 클러스터를 Proxmox와 **물리적으로 분리**해 운영한다. BlueStore라는 차세대 OSD 백엔드를 쓰고, 3-replica로 데이터를 보호한다. K8s에는 RBD (Block)을 제공해 PVC 백엔드로 쓰고, Harbor에는 RGW (S3 호환)를 제공한다. 두 access pattern이 같은 Ceph 클러스터의 데이터에 다른 방식으로 접근한다.

| 항목 | 값 |
|---|---|
| 노드 수 | 6 (Proxmox 4와 별도) |
| OSD 백엔드 | **BlueStore** (XFS+FileStore 대체) |
| Replication | **3-replica** (1TB × 6 → 2TB 가용) |
| RBD | K8s PV용 ceph-csi-rbd, StorageClass: team2-rbd-block |
| RGW | S3 호환, Harbor 백엔드 (http://10.10.10.11:7480) |
| CephFS | 미사용 (옵션) |
| 네트워크 | 10G Spine-Leaf 패브릭 |

---

## 🔍 고려한 대안들

스토리지 결정은 인프라의 가장 큰 결정 중 하나라 7가지 옵션을 비교했다.

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Ceph (선택)** | 분산, 자가치유, RBD+CephFS+S3 통합, 무료 | 노드 6대+ 운영 부담, BlueStore 학습 | ★★★★★ |
| **NFS** | 단순, 학습 곡선 ↓ | 단일 서버 SPoF, HA 어려움, RWO 불일치 | ★★ |
| **GlusterFS** | 분산, 무료 | 2022년 Red Hat EOL 선언 | ★ |
| **MinIO** | S3 호환, 가볍고 빠름 | S3만 (Block X, File X) | ★★★ |
| **Longhorn** | K8s native, 쉬움 | 클러스터 내 (장애 격리 X) | ★★★ |
| **OpenEBS Mayastor** | K8s native, NVMe-oF | 신규, production 사례 적음 | ★★ |
| **raw NVMe (local-path)** | 가장 빠름, 무료 | 분산 X (노드 죽으면 데이터 손실) | ★ |

### NFS — 가장 단순한 옵션

NFS는 가장 단순해 보이는 옵션이라 매력적이다. Linux 서버 1대에 NFS 서버 설치하고 K8s에서 nfs-subdir-external-provisioner로 PVC 자동 생성. 한 시간이면 셋업 끝난다.

하지만 자세히 보면 두 가지 큰 약점이 있다. **첫째, 단일 서버 SPoF**다. NFS 서버 한 대 죽으면 모든 PVC mount가 끊긴다. HA를 만들려면 DRBD + keepalived + corosync 같은 추가 구성이 필요한데, 이게 결국 Ceph 복잡도와 비슷해진다. **둘째, RWO 요구사항 불일치**다. K8s의 stateful 워크로드 (DB, Prometheus 등)는 대부분 RWO (한 노드만 mount)인데, NFS는 RWX 친화적이라 conflict가 자주 발생한다.

### GlusterFS — 미래 불투명

GlusterFS는 Ceph와 비슷한 분산 파일시스템이고 무료다. 한때 Red Hat이 적극 투자했지만, **2022년 commercial support 종료를 선언**했다. 커뮤니티는 살아있지만 enterprise 수준의 미래 보장이 없어, 신규 도입은 사실상 안 하는 추세다.

### MinIO — S3만 필요하면 좋음

MinIO는 S3 호환 API만 제공하는 가벼운 솔루션이다. 메모리 사용량이 적고 setup이 단순하다. **단점은 S3만 한다는 점**이다. K8s PV로 쓰려면 csi-s3 같은 어색한 wrapper가 필요하고, Block (RBD) 같은 strong consistency 워크로드엔 부적합하다. Harbor만 운영하면 MinIO도 좋은 선택이지만, 우리는 K8s PVC도 필요해서 Ceph (Block + Object 둘 다)가 맞다.

### Longhorn — K8s native

Longhorn은 Rancher가 만든 K8s native 분산 스토리지다. helm install 한 줄로 깔린다. **단점은 K8s 클러스터 안에 있어 K8s 장애와 cascade**된다는 점이다. K8s API 죽으면 Longhorn도 못 보고, 결국 우리가 Rook-Ceph를 안 쓴 이유와 같은 약점이다.

### raw NVMe (local-path)

가장 빠르고 무료지만 분산이 전혀 없다. 노드 1대 죽으면 그 위의 데이터는 영구 손실. 학습용 임시 워크로드면 모를까, stateful 워크로드엔 부적합하다.

---

## 💡 왜 Ceph인가?

여섯 가지 이유로 정리할 수 있다.

**첫째, 자가치유 (Self-healing)가 자동이다.** OSD 1개 (디스크 1개)가 죽으면 Ceph가 자동으로 다른 OSD에 replica를 재생성한다. 사람이 개입할 필요가 없다. NFS면 디스크 죽었을 때 백업에서 복구하는 데 수 시간 걸리는 반면, Ceph는 background rebalance가 보통 수십 분 내 끝난다.

**둘째, 세 가지 access pattern을 통합한다.** **RBD**는 K8s PVC와 Proxmox VM 디스크로, **CephFS**는 POSIX 공유 (현재 미사용), **RGW**는 Harbor 이미지의 S3 호환 백엔드로 활용한다. 우리는 같은 6 노드 Ceph 클러스터에 세 가지 access를 모두 두고 있다. NFS는 File만, MinIO는 Object만 가능한 반면, **Ceph만 셋 다 통합 제공**한다.

**셋째, 무료고 production-ready다.** Red Hat Ceph Storage라는 commercial 옵션도 있지만 community Ceph로 충분하다. 운영 사례를 보면 **CERN이 수십 PB, Yahoo가 수십 PB** 규모로 사용 중이다. 우리 수 TB 규모는 한참 작은 부담이다.

**넷째, 수평 확장이 단순하다.** 노드 추가만으로 용량과 IOPS가 동시에 올라간다. CRUSH 알고리즘이 데이터를 자동으로 재분산한다. 1000+ 노드까지 검증된 확장성이라 우리 규모에선 여유가 무한하다.

**다섯째, K8s CSI 표준과 통합된다.** ceph-csi-rbd가 공식 CSI driver고, StorageClass 정의만으로 dynamic provisioning이 동작한다. VolumeSnapshot API도 지원해서 backup도 표준 K8s API로 가능하다.

**여섯째, 학습/포트폴리오 가치가 크다.** 분산 시스템의 깊은 개념 (CRUSH, RAFT)을 직접 운영해보는 경험은 어디서 사기 어렵다. S3 호환 RGW는 그대로 AWS와 같은 SDK 코드라 multi-cloud 학습에도 직결된다.

---

## 💰 비용 분석

### CapEx (초기 투자)

| 항목 | 수량 | 단가 | 합계 |
|---|---|---|---|
| Ceph 노드 어플라이언스 | 6 | ₩500,000 | ₩3,000,000 |
| 광케이블/SFP+ | 12 | ₩30,000 | ₩360,000 |
| **합계** | | | **₩3,360,000** |

### OpEx (월간 운영)

| 항목 | 계산 | 월 비용 |
|---|---|---|
| 전기 | 60W × 6 × 24h × 30d × ₩125/kWh | ₩32,400 |
| 감가 (5년) | ₩3,360,000 ÷ 60 | ₩56,000 |
| 운영 (0.05 FTE) | 0.05 × ₩400만 | ₩200,000 |
| **합계** | | **약 ₩288,400/월** |

### Storage 단가 (Ceph TCO 기반)

Raw 6TB / 3-replica = 2TB 가용. 월 ₩88,400 (인건비 제외) ÷ 2000 GB = **₩44/GB/월** (인건비 제외) 또는 **₩144/GB/월** (인건비 포함).

### 다른 옵션과 비교

| 옵션 | GB당 월 비용 | 비고 |
|---|---|---|
| **Ceph (우리)** | ₩44 (인건비 제외) | 통합 (RBD+RGW+CephFS) |
| NFS (Synology DS220+) | ₩20 | File만, SPoF |
| AWS EBS gp3 | ₩100 ($0.08/GB) | Block만, HA |
| AWS S3 Standard | ₩30 ($0.025/GB) | Object만, ★★★★ availability |
| MinIO (자체) | ₩30 | Object만 |

순수 GB 단가만 비교하면 NFS가 가장 싸 보이지만, **NFS는 File access만 가능하고 단일 서버 SPoF**라 동일 평가가 어렵다. Ceph는 RBD + CephFS + RGW 세 가지 access를 통합 제공하는 **유일한 옵션**이라 GB 단가만으로 비교하는 게 불공정하다. **기능 ÷ 비용** 기준이면 Ceph가 명백히 최강이다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 분산 + 자가치유 | 노드 6대 운영 부담 |
| 통합 (RBD+CephFS+RGW) | BlueStore/CRUSH 학습 곡선 |
| 무료 | Red Hat Support 없음 |
| 수평 확장 | 초기 노드 6대 권장 (최소) |
| K8s CSI 표준 | 클러스터 외부 배치 → 네트워크 의존 |

가장 큰 trade-off는 **운영 부담**이다. 6 노드를 별도로 관리해야 하고, BlueStore 튜닝, CRUSH 룰 이해, monitor quorum 관리 같은 Ceph-specific 지식이 필요하다. 다만 ceph-ansible 또는 cephadm 같은 자동화 도구로 많이 줄어들고, Prometheus exporter로 모니터링도 표준화됐다. 운영 인건비를 0.05 FTE 정도로 잡으면 합리적이다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **OSD 1개 (디스크) 죽음** | 자동 rebalance | 자동, 디스크 교체만 |
| **노드 1대 죽음** | mon 2/3 quorum 유지, OSD 1/6 손실 → rebalance | 노드 회복 또는 새 노드 |
| **노드 2대 죽음 (mon)** | mon 1/3 → quorum loss → write 차단 | 긴급 — mon 1대 살리기 |
| **OSD 3대 죽음 (같은 PG)** | 그 PG 데이터 손실 (drastic) | backup에서 복구 |
| **MGR 죽음** | 메트릭/대시보드 안 보임 (데이터는 안전) | MGR 재시작 |
| **RGW 죽음 (현재 ceph1 단일)** | S3 API 다운 (Harbor push/pull 실패) | RGW 재시작 또는 추가 |
| **클러스터 네트워크 분할** | split-brain 위험 | 네트워크 회복 |

가장 우려되는 시나리오는 **노드 2대가 동시에 죽으면서 mon 2개를 같이 잃는 경우**다. mon quorum (2/3)이 깨지면 write가 차단된다. 다행히 우리 6 노드 중 mon은 3대만 동작하고 (보통 ceph1/2/3), 이 3대는 다른 물리 위치에 분산돼 있어 동시 사고 확률이 낮다.

**현재 가장 큰 약점은 RGW가 ceph1 노드 1개 daemon만 동작 중**이라는 점이다. ceph1 죽으면 즉시 Harbor가 push/pull 못한다. Phase 6에서 ceph2에도 RGW를 추가해 HA를 확보할 계획이다.

---

## 🚀 확장 가능성

### Option A: Ceph 노드 추가 (6 → 9 또는 12)

수평 확장의 정석이다. Raw 용량 ↑, IOPS 분산 ↑, EC (Erasure Coding) 풀 가능. 노드당 ₩50만 정도라 ROI가 좋다. EC 4+2는 노드 최소 8대 권장이라, 8대로 늘리면서 EC pool을 추가하면 같은 raw 디스크로 사용 가능 용량이 33% (3-replica)에서 67% (EC)로 두 배 늘어난다.

- 🎯 **추천 시점**: 사용 가능 용량 70% 도달

### Option B: ⭐ SSD WAL/DB 분리 (가성비 최고)

BlueStore의 WAL (Write-Ahead Log)와 DB (메타데이터)를 별도 SSD로 분리하는 옵션이다. 노드당 100GB SSD (~₩5만) × 6대 = ₩30만 투자로 **seq write 4~8배, randwrite 5~15배** 성능 개선이 가능하다. 우리 현재 35 MB/s seq write가 ~150 MB/s까지 올라간다.

투자 대비 효율이 가장 좋아서, PVC IO 병목이 측정되는 시점에 즉시 검토할 옵션이다.

- 💰 **비용**: ₩30만 CapEx
- ⏱️ **작업**: 노드별 1~2시간 offline migration
- 🎯 **추천 시점**: PVC IO 병목 측정 시

### Option C: Cache Tier (SSD pool 앞단)

hot data는 SSD에, cold data는 HDD에 자동 배치하는 패턴. 단점은 복잡도 ↑이고 최근 Ceph N+에서 deprecated 검토 중이라 신규 도입은 비추다.

### Option D: Erasure Coding 도입 (replicated → EC)

공간 효율을 위해 3-replica 대신 EC 4+2를 쓰는 옵션. 같은 raw 6TB에서 사용 가능 용량이 2TB → 4TB로 2배 늘어난다. 단점은 CPU/latency ↑고, 노드 최소 6대 권장이다 (8대면 안정). 우리는 6대라 EC 도입 가능하지만 노드 1대 죽으면 여유가 빡빡해진다.

- 🎯 **추천 시점**: cold storage (RGW for backup) + 노드 8대+ 확장 후

### Option E: Ceph multi-site (DR)

다른 지리적 사이트에 Ceph cluster를 두고 multi-site replication을 구성하는 옵션. 진짜 PCI/HIPAA 같은 컴플라이언스 요구가 있을 때나 검토할 만한 큰 작업이다.

### Option F: Rook-Ceph로 K8s 통합

Ceph를 K8s 안으로 옮겨 helm chart로 관리하는 옵션이지만, **우리가 이미 별도 클러스터로 결정한 이유 (cascade 위험)**를 다시 떠올리면 비추다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 용량 70%+ | A (노드 추가) |
| PVC IO 병목 측정 | B (SSD WAL/DB) ⭐ |
| 공간 효율 필요 (cold storage) | D (노드 추가 후 EC) |
| 지리적 DR | E (multi-site) |

---

## 🔗 다른 파트와의 연결

이 Ceph 결정은 우리 인프라의 가장 기초 layer다. 아키텍처의 `architecture/01-physical-and-network.md`는 Ceph 별도 클러스터 결정을 다른 관점에서 다루고, `02-network-10g-decision.md`는 Ceph가 왜 10G 네트워크가 필요한지 설명한다. CI/CD에선 Harbor가 Ceph RGW backend를 사용한다 (`cicd/04-harbor-registry.md`). 보안 측면에선 Ceph 데이터 암호화와 backup 정책이 관련된다 (`security/08-backup-dr-policy.md`).

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. NFS도 단순하고 충분하지 않나요?**

A. NFS는 **단일 서버 SPoF**라는 명확한 약점이 있습니다. HA를 만들려면 DRBD/keepalived 같은 추가 구성이 필요한데, 그러면 결국 Ceph 복잡도와 비슷해집니다. 게다가 **NFS는 File만 가능**합니다 — Block (RBD)이나 S3 (Object) 같은 access pattern은 못 합니다. 우리는 K8s PVC (Block) + Harbor (S3) + 향후 공유 파일 (CephFS) 셋 다 필요해서, NFS만으로는 부족합니다.

**Q2. GlusterFS도 분산이고 무료인데요?**

A. **Red Hat이 2022년 GlusterFS commercial support 종료를 선언**했습니다. 커뮤니티는 살아있지만 enterprise 수준의 미래 보장이 없어 신규 도입은 안 합니다. Ceph는 Red Hat이 적극 투자 중이고 CERN/Yahoo 대규모 운영 사례가 있어 안전한 선택입니다.

**Q3. MinIO가 가볍고 빠른데 왜 안 썼나요?**

A. **MinIO는 S3만 합니다**. Object storage만 필요하면 좋은 선택이지만, 우리는 K8s PVC (Block)도 필요하고 향후 CephFS도 옵션으로 두고 싶었습니다. MinIO를 쓰려면 K8s PV는 별도 솔루션 (Longhorn 등) 필요 → 결국 두 가지 스토리지 운영 = 부담 ↑입니다. Ceph 하나로 셋 다 통합이 합리적이었습니다.

**Q4. 6 노드 운영 부담이 클 텐데요?**

A. 사실입니다. 하지만 세 가지로 완화합니다. **자동화** (ceph-ansible 또는 cephadm), **메트릭 모니터링** (Prometheus exporter), **자가치유** (사람 개입 최소). 운영 인건비를 0.05 FTE (전체 시간의 5%) 정도로 잡으면 합리적인 수준입니다.

**Q5. 3-replica는 공간 1/3인데 비효율 아닌가요?**

A. Raw 6TB → 가용 2TB. 데모/소규모엔 단순함을 우선했습니다. **공간 효율이 진짜 필요하면 EC (Erasure Coding) 4+2로 가면 67% 효율** (가용 4TB)이 가능합니다. 단 EC는 노드 최소 8대 권장이라 우리 현재 6대론 빠듯하고, 노드 확장과 함께 검토하는 게 안전합니다.

**Q6. BlueStore vs FileStore 차이는요?**

A. **FileStore는 XFS 위에 object를 저장**해서 더블 write penalty (XFS 메타데이터 + object 데이터)가 있었습니다. **BlueStore는 raw 디바이스에 직접 쓰기**라 더 빠르고 일관성도 ↑입니다. 2017년부터 default고, 2020년부터 FileStore가 공식 deprecated 됐습니다. 현재는 모든 신규 cluster가 BlueStore입니다.
