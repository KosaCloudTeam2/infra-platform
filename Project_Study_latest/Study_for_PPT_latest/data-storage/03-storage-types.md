# 03. Ceph Storage 종류 — RBD vs CephFS vs RGW

> ⭐ **한 줄 요약**: Ceph가 제공하는 세 가지 access pattern 중 우리는 **RBD (Block)와 RGW (Object/S3) 두 가지를 사용**한다. RBD는 K8s PVC와 VM 디스크 백엔드로, RGW는 Harbor 이미지 저장소로. CephFS (File)는 현재 미사용이지만 향후 필요시 같은 클러스터에서 즉시 활용 가능하다.

---

## 🎯 우리가 사용 중인 것

같은 Ceph 6 노드 클러스터가 두 가지 access pattern을 동시에 제공한다. 이게 **Ceph만 가진 통합의 매력**이다. NFS면 File access만, MinIO면 Object access만 가능한데, Ceph는 같은 데이터를 Block/File/Object로 다 노출할 수 있다.

| 종류 | 사용처 | StorageClass / Endpoint |
|---|---|---|
| **RBD (Block)** | K8s PVC (Prometheus, Grafana, Harbor DB, PXC, Jenkins, Loki, Tempo) | `team2-rbd-block` |
| **RGW (Object/S3)** | Harbor 이미지 blob | http://10.10.10.11:7480 |
| **CephFS (File)** | 현재 미사용 (옵션) | - |

---

## 📊 3종 비교

각 종류의 성격 차이를 보면 어떤 워크로드에 무엇이 맞는지 명확해진다.

| 차원 | RBD | CephFS | RGW |
|---|---|---|---|
| 인터페이스 | Block device | POSIX filesystem | S3/Swift HTTP API |
| 접근 모드 | RWO (단일 노드 mount) | RWX (다중 노드 mount) | HTTP (어디서나) |
| 성능 | ★★★★★ (가장 빠름) | ★★★★ | ★★★ (HTTP 오버헤드) |
| Latency | 1~5ms | 5~10ms | 10~50ms |
| K8s PV | ✅ ceph-csi-rbd | ✅ ceph-csi-cephfs | ⚠️ 어색 |
| 사용 사례 | DB, Prometheus TSDB | 다중 Pod 공유 (모델 파일 등) | 이미지, 로그 chunk, 백업 |
| 일관성 | strong | strong | eventual |
| 수평 확장 | 노드 단위 | 노드 단위 | 수평 확장 ↑↑ |

RBD가 가장 빠른 이유는 **Block device로 노출**되어 K8s가 Pod에 직접 mount하기 때문이다. Linux 커널의 block layer가 직접 다루니 오버헤드가 거의 없다. CephFS는 POSIX filesystem이라 metadata server (MDS)를 거치고, RGW는 HTTP API라 HTTP parsing 오버헤드가 추가된다.

대신 **확장성은 RGW가 압도적**이다. RGW는 stateless HTTP server라 여러 daemon을 두고 load balancer 뒤에 둘 수 있어 수평 확장이 쉽다. RBD는 노드 단위 mount라 한 PV의 throughput은 한 노드의 IO 능력에 묶인다.

---

## 💡 각각 언제 쓰나?

### RBD (Block) — 우리 default 선택

> 🔥 **단일 Pod stateful 워크로드는 무조건 RBD**.

K8s에서 stateful 워크로드 (DB, 시계열 DB, 메시지 큐 등)는 대부분 RWO 모드라 RBD가 맞다. 우리는 다음 워크로드에 RBD를 쓴다:

- **Prometheus** — 시계열 DB (TSDB), 빠른 IO 필요
- **Grafana** — SQLite DB + dashboard PVC
- **Harbor** — 메타데이터 PostgreSQL, Redis cache
- **PXC** — MySQL 데이터 (Galera 동기 복제)
- **Jenkins** — job history, workspace
- **Loki / Tempo** — 현재 RBD, 향후 S3 backend 전환 검토

RBD의 한계는 **RWO (한 노드만 mount)**라는 점이다. 여러 Pod이 같은 데이터를 동시에 보려면 (예: AI 모델 파일 공유) CephFS가 필요하다.

### CephFS (File) — 현재 미사용

CephFS는 POSIX filesystem이라 여러 Pod이 동시에 read/write 가능하다 (RWX). 우리는 현재 RWX가 필요한 워크로드가 없어서 안 쓰고 있지만, 미래 옵션으로 같은 클러스터에 깔려있다.

적합한 use case:
- **AI 모델 파일 공유** (training job들이 같은 모델 파일 read)
- **정적 파일 공유** (이미지 CDN 백엔드 등)
- **Jenkins workspace 공유** (병렬 빌드)

DB에는 부적합하다. POSIX filesystem 위에 DB를 두면 lock overhead가 크고 일관성 위험이 있다.

### RGW (Object/S3) — Harbor backend

RGW는 S3 호환 HTTP API다. 우리는 Harbor의 이미지 blob 저장소로 쓰고 있다. **향후 Loki와 Tempo의 S3 backend도 RGW로 전환할 계획**이다.

적합한 use case:
- **컨테이너 이미지 blob** (Harbor)
- **로그 chunk** (Loki S3 backend)
- **trace** (Tempo S3 backend)
- **백업** (xtrabackup → S3)
- **정적 자산** (사진, 동영상 등)

K8s PVC로 직접 쓰기엔 어색하다. csi-s3 같은 wrapper가 있지만 RBD 대비 안 좋다. **K8s는 RBD, 객체 저장은 RGW**로 역할을 분리하는 게 깔끔하다.

---

## 🔍 고려한 대안

### K8s PVC — RBD vs CephFS vs Longhorn vs OpenEBS

| 대안 | 장점 | 단점 |
|---|---|---|
| **RBD (선택)** | 빠름, K8s 표준 | RWO만 (다중 mount X) |
| CephFS | RWX 가능 | 약간 느림 |
| Longhorn | K8s native | 클러스터 내 (장애 격리 X) |
| OpenEBS Mayastor | NVMe-oF | 신규 |

K8s PV backend로는 RBD가 가장 보편적이다. CephFS는 RWX가 필요한 특수 워크로드용. Longhorn은 K8s 안에서 동작하는 분산 스토리지지만 K8s 장애와 cascade되는 약점이 있고, OpenEBS Mayastor는 신규라 production 사례가 적다.

### 이미지 저장소 backend — RGW vs MinIO vs filesystem

| 대안 | 장점 | 단점 |
|---|---|---|
| **RGW (선택)** | 같은 Ceph 클러스터, 통합 관리 | RGW daemon SPoF (현재 1개) |
| MinIO | 가볍고 빠름 | 별도 클러스터 |
| filesystem (Harbor 기본) | 단순 | 단일 노드 SPoF |

Harbor는 filesystem (PVC), S3 (RGW/MinIO/AWS), GCS, Azure 등 여러 backend를 지원한다. **filesystem은 단일 노드 SPoF + 확장 X**라 부적합. MinIO도 좋은 옵션이지만 별도 클러스터를 운영해야 하는 부담이 있다. **RGW는 우리가 이미 Ceph를 운영 중이라 추가 자원 거의 없이 활용 가능**해서 합리적이었다.

---

## 💰 비용 (storage 단가)

| 종류 | 단가 | 비고 |
|---|---|---|
| **RBD** | ₩44/GB/월 (TCO 기준) | 3-replica이라 raw의 1/3 |
| **CephFS** | ₩44/GB/월 | 동일 |
| **RGW (replicated pool)** | ₩44/GB/월 | 동일 |
| **RGW EC 4+2 pool** | ₩30/GB/월 (33% 절감) | 노드 8대+ 권장 |

같은 Ceph 클러스터의 디스크를 공유하니 모든 종류가 동일한 GB 단가다. RGW를 **Erasure Coding pool**로 만들면 공간 효율이 33%에서 67%로 두 배 늘어 GB 단가가 ₩30 수준으로 떨어진다. 단 EC는 노드 8대+ 권장이라 우리 6대론 아직 부담이다.

---

## ⚖️ Trade-off

### RBD 선택 trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 빠른 성능 | RWO (다중 mount X) |
| K8s 표준 | 다른 노드 reschedule 시 Multi-Attach 에러 가능 |

RBD의 가장 큰 약점은 RWO 제약이다. Pod이 다른 노드로 reschedule되면 stale VolumeAttachment 때문에 Multi-Attach 에러가 발생할 수 있다. 이를 회피하려고 stateful 워크로드 (Prometheus, Jenkins 등)는 nodeSelector로 단일 노드 (sys1)에 고정한다.

### RGW 선택 trade-off (Harbor)

| 얻은 것 | 잃은 것 |
|---|---|
| 같은 Ceph 통합 | RGW daemon SPoF (현재 1개) |
| S3 SDK 호환 | redirect 설정 (`disableredirect: true`) 함정 |

RGW의 가장 큰 함정은 **redirect 설정**이었다. RGW 기본 동작이 "이 URL로 다시 받으세요" redirect를 보내는데, 그 URL이 내부 IP (10.10.10.11)라 외부 client (Harbor에서 외부 push)는 도달 불가. helm values에 `disableredirect: true`를 명시해야 정상 동작한다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **RBD watcher stale** (이전 노드에 묶임) | 다른 노드에서 Pod start 안 됨 | VolumeAttachment 강제 삭제 + watcher blocklist |
| **RGW daemon 죽음** | S3 API down → Harbor push/pull 실패 | Pod 재시작 또는 다른 노드 RGW 추가 |
| **CSI driver 죽음** | PVC mount 실패 | `kubectl rollout restart ds csi-rbdplugin` |
| **Ceph 클러스터 HEALTH_ERR** | write 차단 가능 | `ceph health detail` 확인 |

RBD watcher stale 이슈가 가장 자주 만나는 함정이다. Pod이 노드 A에서 동작하다가 어떤 이유로 노드 B로 reschedule되면, 노드 A의 watcher가 stale 상태로 남아 노드 B에서 mount가 안 된다. 회복 절차는 (1) VolumeAttachment finalizer 강제 제거 + 삭제, (2) 필요시 stale watcher IP를 ceph osd blocklist에 추가.

---

## 🚀 확장 가능성

### Option A: ⭐ RGW 2개로 (현재 1개 SPoF)

가장 시급한 개선이다. ceph2 노드에 추가 RGW daemon을 띄우고, Harbor regionendpoint를 HAProxy 통해 round-robin시킨다. SPoF 해소 + throughput 2배. 작업 2~4시간.

- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option B: ⭐ Loki/Tempo S3 backend로 전환

현재 Loki와 Tempo는 RBD PVC를 쓰고 있는데, S3 backend로 전환하면 수평 확장 + 장기 보관 효율이 ↑된다. Ceph RGW를 backend로 쓰면 비용 0이고, **같은 패턴 (Harbor가 RGW 쓰듯)이 적용**되어 일관성도 좋다.

- 🎯 **추천 시점**: 로그/trace 양 ↑ 또는 retention 30일+ 필요

### Option C: CephFS 활성화

RWX 워크로드 (AI 모델 공유, Jenkins workspace 공유)가 발생하면 CephFS를 활용한다. Ceph 클러스터에 MDS (Metadata Server)를 추가해야 한다.

- 🎯 **추천 시점**: 다중 Pod 공유 필요

### Option D: Erasure Coding pool

cold storage (백업, archive 등)는 EC 4+2 pool로 만들면 공간 효율이 두 배. 단 노드 8대+ 권장이라 노드 확장이 선행돼야 한다.

- 🎯 **추천 시점**: 대용량 cold storage 필요 + 노드 8대+

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| Harbor push 실패 잦음 | A (RGW HA) ⭐ |
| Loki 디스크 부족 | B (S3 backend) |
| RWX 워크로드 발생 | C (CephFS) |

---

## 🔗 다른 파트와의 연결

이 storage 종류 결정은 여러 파트와 직결된다. `04-s3-comparison.md`는 RGW vs AWS S3 비교를 깊이 다룬다. CI/CD 측면에선 Harbor가 RGW backend를 쓴다 (`cicd/04-harbor-registry.md`). 아키텍처 측면에선 StorageClass 정의가 모든 워크로드에 영향을 준다 (`architecture/02-kubernetes-design.md`).

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. CephFS를 안 쓰는데 깔려있나요?**

A. **Ceph cluster 자체엔 MDS (Metadata Server)가 활성**돼 있습니다. 우리가 K8s에서 CephFS PVC를 안 만들었을 뿐이고, 향후 RWX 필요시 즉시 활용 가능합니다. ceph-csi-cephfs CSI driver만 추가하면 됩니다.

**Q2. RBD RWO 한계를 어떻게 회피하나요?**

A. 세 가지 방법입니다. **첫째, workload-type=system 라벨로 단일 노드 고정** — PVC 재 mount 발생을 원천 차단합니다. **둘째, StatefulSet ordered scaling** — Pod이 순서대로 뜨면서 PVC도 안정적으로 attach됩니다. **셋째, 진짜 RWX 필요시 CephFS로 전환**합니다.

**Q3. RGW가 1개라 SPoF인데 왜 미뤘나요?**

A. 학습/데모엔 1개로 충분했고, 실제 Harbor push 실패 사례가 발생했을 때 위험을 인지했습니다. **Phase 6 우선 작업** 중 하나로, ceph2에 RGW 추가 + HAProxy load balancing으로 2시간 내 해결 가능합니다.

**Q4. Ceph PVC 데이터 백업은 어떻게요?**

A. 세 가지 옵션이 있습니다. (1) **Ceph snapshot** (RBD snap, 빠르고 효율적), (2) **VolumeSnapshot K8s API** (cluster-native), (3) **앱 레벨 백업** (PXC xtrabackup 등 앱별 적절한 도구). Prometheus 같은 휘발성 OK 워크로드는 백업 안 합니다. 자세한 내용은 `security/08-backup-dr-policy.md`에 있습니다.

**Q5. CSI driver 죽으면 데이터 손실인가요?**

A. **NO**. 데이터는 Ceph cluster에 안전합니다. **CSI는 mount만 하는 매개체**라 죽어도 Ceph 자체엔 영향 없습니다. csi-rbdplugin 재시작이면 즉시 회복됩니다. K8s 측 PVC 매핑이 일시적으로 끊기는 것뿐입니다.
