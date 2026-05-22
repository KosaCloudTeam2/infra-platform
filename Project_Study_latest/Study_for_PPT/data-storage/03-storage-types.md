# 03. Ceph Storage 종류 — RBD vs CephFS vs RGW

> ⭐ **한 줄 요약**: **RBD (Block) = K8s PVC + VM 디스크**, **CephFS (File) = 다중 mount 공유** (현재 미사용), **RGW (Object/S3) = Harbor 이미지 + 향후 Loki/Tempo**. 셋 다 같은 RADOS 클러스터 사용.

---

## 🎯 우리가 사용 중인 것

| 종류 | 사용처 | StorageClass / Endpoint |
|---|---|---|
| **RBD (Block)** | K8s PVC (Prometheus, Grafana, Harbor DB, PXC, Jenkins, Loki, Tempo) | `team2-rbd-block` |
| **RGW (Object/S3)** | Harbor 이미지 blob | http://10.10.10.11:7480 |
| **CephFS (File)** | 현재 미사용 (옵션) | - |

---

## 📊 3종 비교

| 차원 | RBD | CephFS | RGW |
|---|---|---|---|
| 인터페이스 | Block device | POSIX filesystem | S3/Swift HTTP API |
| 접근 모드 | RWO (단일 노드 mount) | RWX (다중 노드 mount) | HTTP (어디서나) |
| 성능 | ★★★★★ (가장 빠름) | ★★★★ | ★★★ (HTTP 오버헤드) |
| Latency | 1~5ms | 5~10ms | 10~50ms |
| K8s PV | ✅ ceph-csi-rbd | ✅ ceph-csi-cephfs | ⚠️ S3 PVC 어색 |
| 사용 사례 | DB, Prometheus TSDB | 다중 Pod 공유 (모델 파일 등) | 이미지, 로그 chunk, 백업 |
| 일관성 | strong | strong | eventual |
| 수평 확장 | 노드 단위 | 노드 단위 | 수평 확장 ↑↑ |

---

## 💡 각각 언제 쓰나?

### RBD (Block) — 우리 default
> 🔥 단일 Pod stateful 워크로드는 **무조건 RBD**.

**적합**:
- DB (PXC, Redis, PostgreSQL)
- 시계열 (Prometheus, InfluxDB)
- 메시지 큐 (Kafka)
- VM 디스크 (Proxmox 통합 시)

**부적합**:
- 다중 Pod 공유 필요 (RWX 못 함)

### CephFS (File) — 현재 미사용
**적합**:
- AI 모델 파일 공유 (training job들이 같은 파일 read)
- 정적 파일 (이미지 CDN 백엔드)
- 코드 공유 (Jenkins workspace 등)

**부적합**:
- DB (성능 ↓ + 일관성 위험)

### RGW (Object/S3)
**적합**:
- 이미지/blob 저장 (Harbor)
- 로그 chunk (Loki S3 backend)
- 트레이스 (Tempo S3 backend)
- 백업 (xtrabackup → S3)

**부적합**:
- 직접 K8s PVC (S3 PVC는 어색, csi-s3 같은 거 있지만 어색)
- 저지연 요구 워크로드

---

## 🔍 고려한 대안

각 사용처별로:

### K8s PVC: RBD vs CephFS vs Longhorn vs OpenEBS

| 대안 | 장점 | 단점 |
|---|---|---|
| **RBD (선택)** | 빠름, 표준 | RWO만 (다중 mount X) |
| CephFS | RWX 가능 | 약간 느림 |
| Longhorn | K8s native | 클러스터 내 (격리 X) |
| OpenEBS Mayastor | NVMe-oF | 신규 |

### 이미지 저장소 백엔드: RGW vs MinIO vs filesystem

| 대안 | 장점 | 단점 |
|---|---|---|
| **RGW (선택)** | 같은 Ceph 클러스터, 통합 관리 | RGW daemon SPoF (현재 1개) |
| MinIO | 가볍고 빠름 | 별도 클러스터 |
| filesystem (Harbor 기본) | 단순 | 단일 노드 SPoF |

---

## 💰 비용 (storage 단가)

| 종류 | 단가 | 비고 |
|---|---|---|
| **RBD** | ₩44/GB/월 (TCO 기준) | 3-replica이라 raw의 1/3 |
| **CephFS** | ₩44/GB/월 | 동일 |
| **RGW (replicated pool)** | ₩44/GB/월 | 동일 |
| **RGW EC 4+2 pool** | ₩30/GB/월 (33% 절감) | 노드 8대+ 권장 |

---

## ⚖️ Trade-off

### RBD 선택 trade-off
| 얻은 것 | 잃은 것 |
|---|---|
| 빠른 성능 | RWO (다중 mount X) |
| K8s 표준 | 다른 노드 reschedule 시 Multi-Attach 에러 가능 |

### RGW 선택 trade-off (Harbor)
| 얻은 것 | 잃은 것 |
|---|---|
| 같은 Ceph 통합 | RGW daemon SPoF |
| S3 SDK 호환 | redirect 설정 (`disableredirect: true`) 함정 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **RBD watcher stale** (이전 노드에 묶임) | 다른 노드에서 Pod start 안 됨 (Multi-Attach 에러) | VolumeAttachment 강제 삭제 + watcher blocklist |
| **RGW daemon 죽음** | S3 API down → Harbor push/pull 실패 | Pod 재시작 또는 다른 노드 RGW |
| **CSI driver 죽음** | PVC mount 실패 | `kubectl rollout restart ds csi-rbdplugin` |
| **Ceph 클러스터 HEALTH_ERR** | write 차단 가능 | `ceph health detail` 확인 |

---

## 🚀 확장 가능성

### Option A: ⭐ RGW 2개로 (현재 1개 SPoF)
- ✅ **장점**: RGW HA 확보
- 💰 **비용**: 0 (다른 Ceph 노드에 daemon 추가)
- ⏱️ **작업**: 2~4시간 (RGW 추가 + Harbor regionendpoint 변경)
- 🎯 **추천 시점**: 즉시 (Phase 6 우선)

### Option B: ⭐ Loki/Tempo S3 backend로 전환 (현재 RBD)
- ✅ **장점**: 수평 확장, 장기 보관 효율
- 💰 **비용**: 0
- 🎯 **추천 시점**: 로그/trace 양 ↑ 또는 retention 30일+

### Option C: CephFS 활성 (현재 미사용)
- ✅ **장점**: RWX 가능 → Jenkins workspace 공유, AI 모델 공유
- ❌ **단점**: MDS 추가 운영
- 🎯 **추천 시점**: 다중 Pod 공유 필요

### Option D: Erasure Coding 풀 (특정 use case)
- ✅ **장점**: 공간 1/2 (vs 3-replica 1/3)
- ❌ **단점**: CPU/latency ↑, 노드 최소 8대 권장
- 🎯 **추천 시점**: cold storage (RGW 백업용)

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| Harbor push 실패 잦음 | A (RGW HA) |
| Loki 디스크 부족 | B (S3 backend) |
| RWX 워크로드 발생 | C (CephFS) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 자기 (`04-s3-comparison.md`) | RGW = S3 호환, AWS S3와 비교 |
| 🔧 CI/CD | Harbor의 backend |
| 🏛️ 아키텍처 | StorageClass 정의 → 모든 워크로드 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. CephFS 안 쓰는데 깔려있다?**
A. Ceph cluster 자체엔 MDS 활성. 우리가 K8s에서 CephFS PVC를 안 만들었을 뿐. 향후 RWX 필요시 즉시 활용 가능.

**Q2. RBD RWO 한계 어떻게 회피?**
A. (1) workload-type=system 라벨로 단일 노드 고정 (PVC 재 mount 발생 X), (2) StatefulSet은 ordered scaling, (3) 진짜 RWX 필요시 CephFS 사용.

**Q3. RGW가 1개라 SPoF인데 왜 미뤘나?**
A. 학습/데모엔 1개로 충분. 실제 Harbor push 실패 사례 발생 시 위험 인지. Phase 6 우선 작업.

**Q4. Ceph PVC 데이터 백업은?**
A. (1) Ceph snapshot (RBD snap), (2) volumeSnapshot K8s API, (3) 앱 레벨 백업 (PXC xtrabackup, Prometheus는 휘발 OK). → `security/08-backup-dr-policy.md`

**Q5. CSI driver 죽으면 데이터 손실?**
A. NO. 데이터는 Ceph cluster에 안전. CSI는 mount만 하는 매개체. csi-rbdplugin 재시작이면 회복.
