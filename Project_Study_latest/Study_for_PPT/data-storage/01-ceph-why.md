# 01. 왜 Ceph인가?

> ⭐ **한 줄 요약**: Ceph = **분산 + 자가치유 + S3/Block/File 통합** 스토리지. NFS는 SPoF, GlusterFS는 EOL, MinIO는 S3만, raw NVMe는 분산 X. Ceph가 유일한 종합 해답.

---

## 🎯 우리가 한 선택

- **Ceph 6 노드 클러스터** (Proxmox와 별도)
- **BlueStore** OSD 백엔드 (XFS+FileStore 대체)
- **3-replica** (replicated pool, 1TB × 6 → 2TB 가용)
- **RBD** (K8s PV용 ceph-csi-rbd)
- **RGW** (S3 호환 객체 스토리지, Harbor 백엔드)
- **CephFS** (POSIX 호환, 현재 미사용)
- **10G Spine-Leaf** 패브릭 (public + cluster network)

---

## 🔍 고려한 대안들

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Ceph (선택)** | 분산, 자가치유, RBD+CephFS+S3 통합, 무료 | 노드 6대+ 운영 부담, BlueStore 학습 | ★★★★★ |
| **NFS** | 단순, 학습 곡선 ↓ | SPoF (단일 서버), HA 어려움, 성능 한계, RWO 불일치 | ★★ |
| **GlusterFS** | 분산, 무료 | 2022년 Red Hat EOL 선언, 미래 불투명 | ★ |
| **MinIO** | S3 호환, 가볍고 빠름 | S3만 (Block X, File X), K8s PV로는 부적합 | ★★★ (S3만 필요시) |
| **Longhorn** | K8s native, 쉬움 | 클러스터 내 (장애 격리 X), 성능 보통 | ★★★ |
| **OpenEBS Mayastor** | K8s native, NVMe-oF | 신규, production 사례 적음 | ★★ |
| **raw NVMe (local-path)** | 가장 빠름, 무료 | 분산 X (노드 죽으면 데이터 손실), HA X | ★ |
| **vSAN/EMC** | enterprise | 매우 비쌈, vendor lock | ★ |
| **AWS EBS** | 관리 ↓ | 온프레 환경엔 부적합 | ★ |

---

## 💡 왜 Ceph인가? (6가지 이유)

### 1. 🔧 **자가치유 (Self-healing)**
> 🔥 **핵심**: OSD 1개 죽으면 Ceph가 자동으로 다른 OSD에 replica 재생성. 사람 개입 0.

- NFS는 디스크 죽으면 백업에서 복구 (수시간)
- Ceph는 OSD 죽으면 백그라운드 rebalance (자동, 보통 수십분)

### 2. 🌐 **세 가지 access 통합 (RBD + CephFS + RGW)**
- **RBD** (Block): K8s PVC, Proxmox VM 디스크
- **CephFS** (File): POSIX 공유 (현재 미사용, 미래 옵션)
- **RGW** (Object/S3): Harbor 이미지, 향후 Loki/Tempo S3 백엔드

→ NFS는 File만, MinIO는 Object만. **Ceph가 유일하게 셋 다**.

### 3. 💰 **무료 + production-ready**
- Red Hat Ceph Storage (commercial) 옵션 있지만 community Ceph로 충분
- 운영 사례: CERN (수십 PB), 야후 (수십 PB)

### 4. ⚡ **수평 확장**
- 노드 추가만으로 용량 + IOPS 동시 ↑
- ECMP/CRUSH로 데이터 자동 분산
- 1000+ 노드 가능

### 5. 📊 **K8s CSI 표준 통합**
- ceph-csi-rbd가 공식 CSI driver
- StorageClass 정의만으로 dynamic provisioning
- VolumeSnapshot API 지원

### 6. 📚 **학습 + 포트폴리오 가치**
- 분산 시스템 깊이 학습 (CRUSH, RAFT)
- 대기업/스타트업 production에서 자주 사용
- S3 호환 = AWS와 같은 SDK 코드

---

## 💰 비용 분석

### CapEx (초기)
| 항목 | 수량 | 단가 | 합계 |
|---|---|---|---|
| Ceph 노드 어플라이언스 | 6 | ₩500,000 | ₩3,000,000 |
| 1TB HDD (이미 포함) | (6) | - | - |
| 10G NIC (이미 포함) | (6) | - | - |
| 광케이블/SFP+ | 12 | ₩30,000 | ₩360,000 |
| **합계** | | | **₩3,360,000** |

### OpEx (월간)
| 항목 | 계산 | 월 비용 |
|---|---|---|
| 전기 | 60W × 6 × 24h × 30d × ₩125/kWh | ₩32,400 |
| 감가 (5년) | ₩3,360,000 ÷ 60 | ₩56,000 |
| 운영 (0.05 FTE) | 0.05 × ₩400만 | ₩200,000 |
| **합계** | | **약 ₩288,400/월** |

### Storage 단가 (Ceph TCO 기반)
- Raw 6TB / 3-replica = 2TB 가용
- 월 ₩88,400 (인건비 제외) ÷ 2000 GB = **₩44/GB/월** (인건비 제외)
- 인건비 포함 → ₩144/GB/월

### 비교 (다른 옵션 GB당 월 비용)
| 옵션 | GB당 월 비용 | 비고 |
|---|---|---|
| **Ceph (우리)** | ₩44 (인건비 제외) | 통합 (RBD+RGW+CephFS) |
| NFS (Synology DS220+ 등) | ₩20 | File만, SPoF |
| AWS EBS gp3 | ₩100 ($0.08/GB) | Block만, HA |
| AWS S3 Standard | ₩30 ($0.025/GB) | Object만, ★★★★ availability |
| MinIO (자체) | ₩30 | Object만 |

→ Ceph는 **유일한 통합 솔루션**이라 GB 단가만으로 비교 불공정. **기능 ÷ 비용** 기준 최강.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 분산 + 자가치유 | 노드 6대 운영 부담 |
| 통합 (RBD+CephFS+RGW) | BlueStore/CRUSH 학습 곡선 |
| 무료 | Red Hat Support 없음 |
| 수평 확장 | 초기 노드 6대 권장 (최소) |
| K8s CSI 표준 | 클러스터 외부에 배치 → 네트워크 의존 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **OSD 1개 (디스크) 죽음** | 자동 rebalance (다른 OSD가 흡수) | 자동, 디스크 교체만 |
| **노드 1대 죽음 (OSD + MON + MGR 같이)** | mon 2/3 quorum 유지, OSD 1/6 손실 → rebalance | 노드 회복 또는 새 노드 추가 |
| **노드 2대 죽음 (mon)** | mon 1/3 → quorum loss → write 차단 | 긴급 — mon 1대 살리거나 강제 quorum |
| **OSD 3대 죽음 (같은 PG의 3-replica 모두)** | 그 PG 데이터 손실 (drastic) | backup에서 복구 |
| **MGR 죽음** | 메트릭/대시보드 안 보임 (데이터는 안전) | MGR 재시작 |
| **RGW 죽음 (현재 ceph1 단일)** | S3 API 다운 (Harbor push/pull 실패) | RGW 재시작 또는 다른 노드에 RGW 추가 |
| **클러스터 네트워크 분할** | split-brain 위험, monitor 협상 | 네트워크 회복 |

---

## 🚀 확장 가능성

### Option A: ⭐ Ceph 노드 추가 (6 → 9 또는 12)
- ✅ **장점**: Raw 용량 ↑, IOPS 분산, EC 풀 가능
- ❌ **단점**: 노드당 ₩50만 + 전기/공간
- 💰 **비용**: 3대 추가 = ₩150만 CapEx + ₩6,000 전기/월
- 📈 **효율**: Raw 6 → 9TB, IOPS 1.5배
- 🎯 **추천 시점**: 사용 가능 용량 70% 도달

### Option B: ⭐ SSD WAL/DB 분리
- ✅ **장점**: BlueStore WAL/DB SSD 분리하면 **seq write 4~8배, randwrite 5~15배**
- 💰 **비용**: 노드당 100GB SSD ~₩5만 × 6 = ₩30만 CapEx
- 📈 **효율**: 현재 35 MB/s seq write → ~150 MB/s 예상
- ⏱️ **작업**: 노드별 1~2시간 (offline migration)
- 🎯 **추천 시점**: PVC IO 병목 측정 시 (`docs/onprem/13-validation.md §3`)

### Option C: Cache Tier (SSD pool 앞단)
- ✅ **장점**: hot data SSD, cold data HDD
- ❌ **단점**: 복잡, Ceph N+에서 deprecated 검토 중
- 🎯 **추천 시점**: read-heavy + 캐시 효과 클 때 (현재 워크로드엔 비추)

### Option D: Erasure Coding 도입 (3-replica → EC 4+2)
- ✅ **장점**: 공간 효율 (3-replica는 1/3, EC 4+2는 2/3)
- ❌ **단점**: CPU/latency ↑, 노드 최소 6대 (현재 한계)
- 💰 **비용**: 노드 추가 권장 (EC 4+2면 최소 8대)
- 📈 **효율**: 같은 RAW 6TB → 사용 가능 4TB (3-replica 2TB의 2배)
- 🎯 **추천 시점**: cold storage (RGW for backup) + 노드 8대+

### Option E: Ceph multi-site (DR)
- ✅ **장점**: 지리적 DR
- ❌ **단점**: 다른 사이트 인프라 필요
- 🎯 **추천 시점**: 진짜 DR 요구

### Option F: Rook-Ceph로 K8s 통합 (관리 자동화)
- ❌ **단점**: 현재 별도 클러스터 패턴 깨짐, cascade 위험 ↑
- 🎯 **추천 시점**: K8s + Ceph 같이 운영하는 진짜 cloud-native 환경 (우리 비추)

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 용량 70%+ | A |
| PVC IO 병목 측정 | B |
| 공간 효율 필요 (cold storage) | D (노드 추가 후) |
| 지리적 DR | E |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 | Ceph 별도 클러스터 결정 → `architecture/01-physical-and-network.md`. 네트워크 10G 결정도. |
| 🔧 CI/CD | Harbor가 Ceph RGW 백엔드 사용 → `cicd/03-harbor-registry.md` |
| 🔒 보안 | Ceph 데이터 암호화, 백업 정책 → `security/08-backup-dr-policy.md` |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. NFS도 단순하고 충분하지 않나?**
A. NFS는 단일 서버 SPoF. HA 하려면 DRBD/keepalived 등 추가 구성 필요 → Ceph 복잡도와 비슷해짐. 게다가 NFS는 File만 (Block, S3 X). Ceph는 셋 다 통합.

**Q2. GlusterFS도 분산인데?**
A. Red Hat이 2022년 GlusterFS commercial support 종료 발표. 커뮤니티는 살아있지만 미래 불확실. Ceph는 Red Hat이 적극 투자 + CERN/Yahoo 대규모 운영.

**Q3. MinIO가 가볍고 빠른데?**
A. MinIO는 S3만. RBD/CephFS 같은 Block/File 없음. Harbor는 S3로 백엔드 가능하지만 K8s PV는 별도 솔루션 필요 → 결국 Ceph + MinIO 2개 운영 = 부담.

**Q4. 6 노드 운영 부담 클 텐데?**
A. 사실. 그래서 (1) 자동화 (ceph-ansible 또는 cephadm), (2) 메트릭 모니터링 (Prometheus exporter), (3) 자가치유 (사람 개입 최소). 운영 인건비 0.05 FTE 가정.

**Q5. 3-replica는 공간 1/3인데 비효율 아닌가?**
A. RAW 6TB → 가용 2TB. 데모/소규모엔 단순함 우선. 공간 효율 필요시 EC 4+2 (노드 8대+ 권장).

**Q6. BlueStore vs FileStore?**
A. FileStore는 XFS 위에 object 저장 → 더블 write penalty. BlueStore는 raw 디바이스에 직접 → 빠르고 일관성 ↑. 2017년부터 default, 2020년부터 FileStore deprecated.
