# 02. 왜 10G 광케이블인가?

> ⭐ **한 줄 요약**: Ceph 3-replica는 모든 write를 3 디스크에 → 네트워크 트래픽 ★★★. 1G는 즉시 병목. 10G로 Pod-Pod 5+ Gbps 실측. Spine-Leaf로 ECMP 확장 가능.

---

## 🎯 우리가 한 선택

- **10GbE Spine-Leaf** 패브릭 (Spine 2 + Leaf 5)
- **광 SFP+** (구리 10G도 가능하지만 거리/노이즈)
- **Ceph public network + cluster network**: 같은 10G fabric에 공존
- **Proxmox vmbr1**: 10G로 K8s/Ceph 트래픽
- **vmbr0**: 1G 관리망 (분리)

---

## 🔍 고려한 대안들

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **10G Spine-Leaf 광 (선택)** | 미래 확장, 빠름, ECMP, 광은 노이즈 ↓ | 스위치 7대 + 광케이블 비용 | ★★★★★ |
| 단일 10G 스위치 | 단순, 저렴 | 스위치 죽으면 전체 down, 확장 한계 | ★★★ |
| 1G 단일 스위치 | 가장 저렴 | Ceph replication 1Gbps 병목 | ★ |
| 25/40G | 미래 대비, 더 빠름 | 비용 ★★★★ (학습 환경엔 과함) | ★★ |
| InfiniBand | HPC 표준, 초고속 | 학습 가치 적음, 일반 환경 호환 X | ★ |
| 구리 10G (RJ45) | 케이블 저렴 | 노이즈, 거리 한계 (10G는 30m), 전력 ↑ | ★★★ |

---

## 💡 왜 10G + Spine-Leaf? (5가지 이유)

### 1. ⚡ **Ceph replication 트래픽 ★★★**
> 🔥 **핵심**: Ceph 3-replica → 1 write = 3 디스크. 네트워크가 1G면 즉시 병목.

**계산**:
- 1G NIC 실효 속도 약 100 MB/s
- Ceph는 client write를 primary OSD로 보내고, primary가 secondary 2개로 복제 → write 1번에 네트워크 트래픽 약 2~3배
- 1G면 client write throughput ~30 MB/s로 제한
- 10G면 100~150 MB/s 가능

**실측 데이터** (`docs/onprem/13-validation.md`):
- iperf3 Pod-Pod: **5.34 Gbps** (10G 사용 중 검증)
- 1G 환경이었으면 940 Mbps 한계 → 5배 차이

### 2. 🌐 **Spine-Leaf = 미래 확장 + ECMP**
- 단일 스위치: 노드 추가 시 포트 한계 도달
- Spine-Leaf: Leaf 추가 → 자동 ECMP 분산
- DC 표준 토폴로지 (학습 가치)

### 3. 📊 **K8s Pod-Pod 통신**
- Pod 수 늘면 inter-pod 트래픽 ↑ (microservice)
- HAProxy Ingress → Pod, Pod → Pod (gRPC), Pod → DB
- 1G면 100 MB/s 공유 → 빠르게 포화
- 10G면 여유

### 4. 💰 **장기 비용 효율**
- 1G 깔고 나중에 10G 교체 = 2배 비용 + 다운타임
- 처음부터 10G = 5~10년 유효
- 10G NIC + SFP+ 모듈 가격 떨어짐 (3년 전 대비 70%)

### 5. 📚 **학습/포트폴리오 가치**
- 광 SFP+ 핸드링 = DC 실무
- Spine-Leaf 토폴로지 = AWS/대기업 표준
- 면접 어필 ("10G fabric 직접 구축")

---

## 💰 비용 분석

### CapEx (네트워크 부분만)
| 항목 | 수량 | 단가 | 합계 |
|---|---|---|---|
| JT-S508CL-8S 10G 스위치 | 7 (Spine 2 + Leaf 5) | ₩600,000 | ₩4,200,000 |
| SFP+ 광 모듈 | ~30 | ₩30,000 | ₩900,000 |
| 광 케이블 (다양한 길이) | 15 | ₩15,000 | ₩225,000 |
| **합계** | | | **₩5,325,000** |

### 1G로 했을 때 비교
| 항목 | 수량 | 단가 | 합계 |
|---|---|---|---|
| 1G 24포트 매니지드 스위치 | 2 (코어/확장) | ₩300,000 | ₩600,000 |
| 1G UTP 케이블 | 30 | ₩5,000 | ₩150,000 |
| **합계** | | | **₩750,000** |

→ **10G가 ₩4,575,000 더 비쌈** (CapEx 차이)

### Break-even 분석
- 1G로 갔다가 나중에 10G 업그레이드 시:
  - 1G 폐기 ₩750,000 (sunk)
  - 10G 신규 ₩5,325,000
  - 다운타임/마이그레이션 노력 ★★★★
  - **총 ₩6,075,000 + 노력** → 처음 10G보다 비쌈

- **결론**: 처음부터 10G가 합리적 (장기 비용 + 효율)

### 효율 차이 (월간)
| 워크로드 | 1G 환경 | 10G 환경 |
|---|---|---|
| Ceph rebalance (노드 교체) | 6시간+ | 1시간 |
| Harbor 이미지 push (500MB) | 50초 | 5초 |
| 백업 (Ceph snapshot) | 분 단위 | 초 단위 |
| Pod 간 통신 (microservice) | 자주 포화 | 여유 |

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 5+ Gbps Pod-Pod | 초기 ₩530만 |
| Ceph rebalance 빠름 | 스위치 7대 관리 부담 |
| 미래 확장 (ECMP) | 광 모듈 관리 (호환성 주의) |
| Spine-Leaf 학습 | 단일 스위치 단순함 ↑ |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Spine 1대 죽음** | ECMP가 다른 Spine 우회 | 자동 |
| **Leaf 1대 죽음** | 그 Leaf 연결된 노드만 (보통 1~2대) down | 노드 reboot 또는 케이블 다른 Leaf로 |
| **광 케이블 단선** | 그 link만 down (다른 path 자동) | 케이블 교체 |
| **SFP+ 모듈 죽음** | 그 포트 down | 모듈 교체 |
| **호환성 문제 (3rd party SFP+)** | link up 안 됨 | 검증된 모듈 사용 |

---

## 🚀 확장 가능성

### Option A: ⭐ Jumbo Frame 활성 (MTU 9000)
- ✅ **장점**: 패킷 오버헤드 ↓, throughput 7~8 Gbps 가능
- ❌ **단점**: 양쪽 (Proxmox + Ceph + 스위치) 모두 일치 필요. 미스매치면 단절
- 💰 **비용**: ₩0 (설정만)
- ⏱️ **작업**: 2~4시간 (테스트 + 검증)
- 🎯 **추천 시점**: 현재 5G 사용 → 더 짜내야 할 때

### Option B: Ceph public/cluster network 분리
- ✅ **장점**: client 트래픽과 replication 트래픽 격리
- 💰 **비용**: NIC 1개 더 (또는 VLAN 분리)
- 🎯 **추천 시점**: Ceph 부하 ↑ (현재 여유 있음)

### Option C: 25G/40G 업그레이드
- ✅ **장점**: 더 빠름, 미래 대비
- ❌ **단점**: 스위치 + NIC 교체 ₩1500만+
- 🎯 **추천 시점**: 진짜 운영 + 대용량 (학습 환경엔 비추)

### Option D: 광 → 구리 100GBASE-T (장거리 아닐 때)
- ✅ **장점**: 케이블 저렴
- ❌ **단점**: 전력 ↑, 거리 한계
- 🎯 **추천 시점**: 단거리 + 비용 최우선 (우리 광 이미 깔림, 비추)

### Option E: SmartNIC / DPU 도입
- ✅ **장점**: CPU offload (TLS, OVS)
- 🎯 **추천 시점**: 진짜 cloud 규모

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 현재 throughput 부족 (5G → 7G+) | A (Jumbo) |
| Ceph 부하 ↑ | B (network 분리) |
| 진짜 운영 진입 + 트래픽 ★★★ | C |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 자기 (`01-ceph-why.md`) | Ceph가 10G 필요한 이유 |
| 🏛️ 아키텍처 | Spine-Leaf 토폴로지 결정 → `architecture/01-physical-and-network.md` |
| 🔧 CI/CD | Harbor push/pull 속도 (대용량 이미지) |
| 🔒 보안 | 트래픽 격리 (VLAN), 향후 mTLS |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 1G로도 충분하지 않나? Ceph가 그렇게 트래픽 많이 쓰나?**
A. 1G 환경에서 Ceph rebalance 6시간 vs 10G 1시간 (실측 차이 6배). 일상 client write는 ~100MB/s 정도면 OK이지만, 노드 교체/디스크 교체 같은 rebalance 시점에 1G는 진짜 병목. 그리고 K8s Pod-Pod도 같은 NIC 공유.

**Q2. Spine-Leaf 7대는 학습 환경엔 과한 것 아닌가?**
A. 학습 가치 ★★★ + 향후 확장 대비 + 가격 떨어져서 ₩600,000/대로 합리적. 단일 스위치 ₩500,000과 큰 차이 없음. 운영급 토폴로지 학습 = 면접 어필.

**Q3. Jumbo frame 왜 안 켰나?**
A. 위 Option A. 양쪽 일치 필요한데 한 군데 빠뜨리면 단절 위험. 우선 default 1500 MTU로 안정 운영 후, 필요시 단계적 활성. 데모/학습 환경 우선순위.

**Q4. Ceph public network와 cluster network 분리 안 했나?**
A. 같은 10G fabric에 공존. 분리하면 격리 ↑ but NIC 1개 더 또는 VLAN 추가. 현재 부하 여유 있어 분리 안 함. 진짜 운영 진입 시 분리 권장.

**Q5. 광 vs 구리 10G?**
A. 구리 10GBASE-T는 30m 거리 한계 + 전력 5W (광은 1W). DC 환경엔 광이 표준. 우리는 학습 환경 + 거리 짧지만 광 선택 = 노이즈 ↓ + 학습 가치.

**Q6. Pod-Pod 5 Gbps인데 10G 광케이블 의미 있나? (5G만 써도)**
A. (1) 다른 트래픽 (Ceph replication, K8s API, 백업) 같이 사용. 합치면 8G+ 가능, (2) 노드 추가시 헤드룸 필요, (3) Jumbo frame + 튜닝으로 7~8G까지 짜낼 수 있음. 1G면 처음부터 한계.
