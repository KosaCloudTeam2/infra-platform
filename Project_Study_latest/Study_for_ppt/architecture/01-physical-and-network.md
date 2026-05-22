# 01. 물리 인프라 + 네트워크 설계

> ⭐ **한 줄 요약**: Proxmox 4 + Ceph 6 **분리** 클러스터, **10G Spine-Leaf** 패브릭, **pfSense HA**가 VLAN 4개 게이트웨이. 스토리지 장애를 컴퓨트로 cascade되지 않게 격리.

---

## 🎯 우리가 한 선택

### 물리 장비
| 장비 | 수량 | 사양 | 역할 |
|---|---|---|---|
| **Proxmox 노드** | 4 | LG B80LV (i7-13700, 16C/24T, 32GB RAM, 476GB NVMe + 931GB HDD) | VM 호스트 (K8s, pfSense, bastion, lb 등) |
| **Ceph 노드** | 6 | 별도 어플라이언스 (1TB HDD × 1, BlueStore) | 분산 스토리지 (RBD/RGW) |
| **JT-S508CL-8S Spine** | 2 | 10G 8포트 | Leaf 간 백본 |
| **JT-S508CL-8S Leaf** | 5 | 10G 8포트 | 노드 직접 연결 |
| **관리 스위치** | 1 | 1GbE | Proxmox 4 + 노트북 4 |
| **비관리 스위치** | 2 | 1GbE | 보조 |
| **라우터** | 1 | 192.168.21.1 | 인터넷 게이트웨이 |

### 가상 네트워크
| 컴포넌트 | 구성 |
|---|---|
| **pfSense HA** | CARP (VIP 공유) + pfsync (state) + XMLRPC (설정 동기) |
| **VLAN 10** | 172.16.21.0/24 — 용도 확인 필요 |
| **VLAN 20** | 172.16.22.0/24 — DMZ (Edge HAProxy VIP 172.16.22.5) |
| **VLAN 30** | 172.16.23.0/24 DHCP — Internal (K8s 노드, K8s API VIP 172.16.23.5, MetalLB 172.16.23.50) |
| **VLAN 40** | 172.16.24.0/24 DHCP — 관리 (bastion 172.16.24.10) |

```
[Internet]
    │
[라우터 192.168.21.1]
    │
[pfSense HA (Proxmox 위)] ─ CARP ─ [pfSense Backup]
    │ │ │ │
    ▼ ▼ ▼ ▼
  V10 V20 V30 V40
       │   │
       │   ▼ K8s 노드들 + lb-1/lb-2 + MetalLB 172.16.23.50
       │
       ▼ Edge VIP 172.16.22.5 → Edge HAProxy × 2 → K8s Ingress
```

---

## 🔍 고려한 대안들

### Q1. Proxmox vs 베어메탈 K8s vs VMware vs OpenStack

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **베어메탈 K8s** | 가상화 오버헤드 0, 최고 성능 | OS 격리 X, multi-tenant 불가, snapshot/migration 어려움 | ★★ |
| **Proxmox (선택)** | KVM 기반 무료, cloud-init 지원, Web UI, snapshot/migration 쉬움 | 가상화 오버헤드 (5~10%) | ★★★★★ |
| **VMware vSphere** | 엔터프라이즈 검증, vMotion 등 강력 | 라이선스 비쌈 (학습 환경 부적합) | ★ |
| **OpenStack** | 진짜 클라우드 (multi-tenant, API) | 복잡도 ★★★★★, 4명 팀엔 과함 | ★★ |

### Q2. Ceph 별도 클러스터 vs K8s 내장 (Rook-Ceph) vs NFS

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Ceph 별도 (선택)** | 컴퓨트/스토리지 장애 격리, 독립 확장, Ceph 노드 OS 최적화 | 노드 6대 추가 비용, 별도 운영 부담 | ★★★★★ |
| **Rook-Ceph (K8s 내)** | helm install 한 줄, 동일 cluster 관리 | K8s 장애가 storage로 cascade, Pod scheduling 종속 | ★★★ |
| **NFS** | 단순, 학습 곡선 낮음 | 단일 서버 SPoF, 성능 한계, RWO 부적합 | ★★ |
| **GlusterFS** | 분산, 무료 | 2022년 Red Hat EOL 선언, 미래 불투명 | ★ |

### Q3. Spine-Leaf 10G vs 단일 1G 스위치

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Spine-Leaf 10G (선택)** | Ceph replication 빠름, K8s pod-pod 5+ Gbps, 확장 시 ECMP | 스위치 7대 비용, 설정 복잡 | ★★★★★ |
| **단일 1G 스위치** | 단순, 저렴 | Ceph replication 병목 (1Gbps), Pod-Pod 느림, K8s API + 데이터 같은 link | ★ |
| **단일 10G 스위치** | 단순 + 빠름 | 스위치 죽으면 전체 down, 확장 한계 | ★★★ |

---

## 💡 왜 이걸 선택했나 (4가지 이유)

### 1. 🔧 **장애 격리 (Failure Isolation)**
> 🔥 **핵심**: Ceph 죽어도 K8s 살아있고, K8s 죽어도 Ceph 살아있다.

- Rook-Ceph 통합이면 K8s API 죽으면 storage도 같이 → 진단 불가능
- 별도 클러스터면 각자 독립 → 한쪽 문제 추적 쉬움

### 2. 💰 **비용 효율 (학습/소규모)**
- VMware 라이선스 노드당 ~$1000/년 회피
- OpenStack 운영 인건비 회피
- Ceph는 무료 (Red Hat support는 옵션)

### 3. 📚 **학습 가치**
- Proxmox = KVM 기초 + cloud-init = AWS/GCP에서도 통용
- Ceph = 분산 스토리지 표준 (S3 호환 RGW)
- Spine-Leaf = DC 표준 토폴로지

### 4. ⚡ **성능 + 확장성**
- 10G 패브릭 = Ceph 3-replica write도 충분 (실측 5.34 Gbps Pod-Pod)
- Spine-Leaf = 노드 추가 시 ECMP로 자동 분산

---

## 💰 비용 분석

### CapEx (초기 투자)
| 항목 | 수량 | 단가 | 합계 |
|---|---|---|---|
| LG B80LV Proxmox 노드 | 4 | ₩2,000,000 | ₩8,000,000 |
| Ceph 노드 (1TB HDD) | 6 | ₩500,000 | ₩3,000,000 |
| JT-S508CL-8S 10G 스위치 | 7 | ₩600,000 | ₩4,200,000 |
| SFP+ 광케이블/모듈 | ~30 | ₩30,000 | ₩900,000 |
| 관리 스위치 1G | 1 | ₩200,000 | ₩200,000 |
| 라우터 + 비관리 스위치 × 2 | 3 | ₩100,000 | ₩300,000 |
| **합계** | | | **₩16,600,000** |

### OpEx (월간 운영)
| 항목 | 계산 | 월 비용 |
|---|---|---|
| 전기 (Proxmox 4 × 100W + Ceph 6 × 60W + 스위치 10W × 7 + 기타 50W) | 약 880W × 24h × 30d × ₩125/kWh | **~₩79,000** |
| 인터넷 회선 | 사무실 공유 가정 | ₩0 (분담 시 ~₩30,000) |
| 5년 감가 (CapEx ÷ 60개월) | | **~₩277,000** |
| **월 TCO 합계** | | **약 ₩356,000** |

### 같은 워크로드 100% AWS 했을 때
- EC2 16C/24T VM × 4 (Proxmox 대체) → m5.4xlarge × 4 = ~$1,400/월
- EBS 6TB (Ceph 대체) gp3 = ~$480/월
- 합계 약 **$1,880/월 = ₩2,500,000+/월**

**→ 온프레가 약 85% 절감** (단, 초기 투자금 회수 ~5년 가정)

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 데이터 주권 (자체 호스팅) | 클라우드 elastic scale 불가 (하드웨어 한계) |
| 학습 가치 (전체 stack 이해) | 설치/운영 시간 비용 |
| 비용 ↓ (장기) | 초기 투자금 ↑ (₩1,600만) |
| 장애 격리 (Ceph ↔ K8s) | 노드 추가 (Ceph 6대) |
| 10G 고성능 | 스위치 7대 관리 부담 |

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 절차 |
|---|---|---|
| **pfSense MASTER VM 호스트 다운** | CARP로 자동 failover (수 초) | 자동 (BACKUP이 MASTER 승격) |
| **Spine 스위치 1대 죽음** | ECMP로 다른 Spine 우회 (자동) | 자동 |
| **Leaf 스위치 1대 죽음** | 그 Leaf에 연결된 노드만 down | 노드 수동 reboot 또는 ceph healing |
| **Ceph mon 1대 죽음** | quorum 유지 (3 중 2) | 노드 회복 또는 mon 재배포 |
| **Ceph mon 2대 죽음** | quorum loss → write 차단 | 긴급 — mon 1대 살리기 우선 |
| **Proxmox 호스트 4대 중 1대** | VM 4~5대 down → 다른 호스트로 HA migration (Ceph 백엔드면 자동, local disk면 수동) | 자동 또는 수동 |
| **관리 1G 스위치** | Proxmox UI 접근 불가, 노트북 ↔ 노드 SSH 불가 | 콘솔 직접 접근 |

---

## 🚀 확장 가능성

### Option A: Ceph 노드 추가 (6 → 9 또는 12)
- ✅ **장점**: Raw 용량 ↑, IO 분산, EC 풀 가능 (현재 6대는 EC 최소 권장)
- ❌ **단점**: 노드당 약 ₩50만 + 전기 추가
- 💰 **비용**: 3대 추가 = ₩150만 CapEx + 월 ₩6,000 전기
- 📈 **효율**: Raw 6TB → 9TB, IOPS 1.5배 (수평 확장)
- ⏱️ **작업**: 1~2일 (HW 조립 + Ceph 추가)
- 🎯 **추천 시점**: 사용 가능 용량 70% 도달 (현재 ~2TB 중 1.4TB 사용 시)

### Option B: Ceph 노드에 SSD WAL/DB 분리
- ✅ **장점**: BlueStore WAL/DB SSD 분리하면 **seq write 4~8배, randwrite 5~15배**
- ❌ **단점**: 노드당 SSD 100GB 추가 (~₩5만)
- 💰 **비용**: 6대 × ₩5만 = ₩30만 CapEx
- 📈 **효율**: 현재 35 MB/s seq write → ~150 MB/s 기대
- ⏱️ **작업**: 노드별 1~2시간 (offline migration)
- 🎯 **추천 시점**: PVC IO가 병목으로 측정될 때 (`docs/onprem/13-validation.md §3`)

### Option C: Proxmox 노드 추가 (4 → 6 또는 8)
- ✅ **장점**: VM 더 띄울 수 있음 (sys2 추가 등), pfSense 진짜 분리 가능
- ❌ **단점**: 노드당 ₩200만+
- 💰 **비용**: 2대 추가 = ₩400만 CapEx + 월 ₩10,000 전기
- 📈 **효율**: 총 RAM 128GB → 192GB
- 🎯 **추천 시점**: sys1 메모리 압박 + sys2 추가 결정 시

### Option D: 10G → 25G/40G 업그레이드
- ✅ **장점**: Ceph + K8s + 일반 트래픽 분리 가능
- ❌ **단점**: 스위치 + NIC 교체 비용 ₩1500만+
- 💰 **비용**: 큼 (학습 환경 비추천)
- 🎯 **추천 시점**: 진짜 운영 + 대용량 워크로드 시

### Option E: 다른 사이트로 DR cluster (Ceph multi-site)
- ✅ **장점**: 지리적 DR
- ❌ **단점**: 별도 사이트 비용
- 🎯 **추천 시점**: PCI/HIPAA 컴플라이언스 요구 시

### 📊 확장 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| Ceph 용량 70%+ | A (노드 추가) |
| PVC IO 병목 | B (SSD WAL/DB) |
| sys1 OOM 잦음 | C (Proxmox 추가) |
| 네트워크 10G 포화 (현재 5G 사용) | D 보류, 모니터링 |
| 진짜 DR 필요 | E + Ceph multi-site |

---

## 🔗 다른 파트와의 연결

| 파트 | 이 문서가 영향 주는 부분 |
|---|---|
| 💾 데이터/스토리지 | Ceph 네트워크 결정 (10G) → `data-storage/02-network-10g-decision.md`. Ceph 토폴로지 (별도 클러스터) → `data-storage/01-ceph-why.md` |
| 🔧 CI/CD | Jenkins/Harbor가 sys1에 배치되는 이유, MetalLB가 외부 노출 매커니즘 |
| 🔒 보안 | VLAN 분리 = security boundary, pfSense는 방화벽 역할도 → `security/01-pfsense-firewall.md` |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 왜 베어메탈에 K8s 안 깔고 굳이 Proxmox 위에?**
A. (1) cloud-init으로 노드 추가/교체 자동화, (2) VM snapshot으로 안전한 실험, (3) pfSense 같은 어플라이언스 VM 같은 호스트에 격리 가능, (4) 학습 가치 (가상화 + K8s 동시). 트레이드오프는 5~10% 가상화 오버헤드인데 우리 워크로드 규모엔 무시 가능.

**Q2. Ceph 별도가 아니라 K8s 안에 Rook으로 했으면?**
A. 단순함은 ↑이지만 storage 장애와 K8s 장애가 cascade. 예) K8s API 죽으면 Rook도 못 봄 → 진단 불가. 별도 클러스터면 ceph-csi-rbd가 K8s ↔ Ceph 사이 통신만 끊기지 데이터는 살아있음.

**Q3. Spine-Leaf 7대 스위치는 과하지 않나?**
A. 학습 환경엔 약간 과하지만 (1) Ceph replication 트래픽 격리 필요, (2) ECMP로 확장 시 단순, (3) DC 표준 토폴로지 학습. 작게 시작하려면 Spine 2 Leaf 2도 가능.

**Q4. pfSense를 어플라이언스 대신 VM으로 한 위험?**
A. Proxmox 죽으면 pfSense도 죽음 → CARP HA 효과 반감. 그래서 pfSense VM 2개를 **다른 Proxmox 호스트**에 분산 배치 + Proxmox 자동 시작 보장. 진짜 운영이면 별도 어플라이언스 권장.

**Q5. VLAN을 10/20/30/40으로 나눈 이유?**
A. (10) 관리/예비, (20) DMZ (외부 노출 영역), (30) Internal (K8s+lb), (40) 관리(bastion). DMZ ↔ Internal 분리로 보안 경계 명확. K8s 노드는 외부 직접 안 보이고 반드시 Edge HAProxy 통과해야.
