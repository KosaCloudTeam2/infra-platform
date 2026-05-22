# 04. Ceph RGW vs AWS S3 — 비용/효율 비교

> ⭐ **한 줄 요약**: **S3는 프로토콜**이지 서비스가 아님. Ceph RGW는 우리 클러스터의 S3 호환 API (무료, 내부망). AWS S3는 Amazon의 클라우드 서비스 (GB 과금). 우리 환경 (~200GB)은 **Ceph RGW가 4~5배 저렴**.

---

## 🎯 핵심 개념: S3 = 프로토콜

```
S3 (Simple Storage Service) 프로토콜
  = HTTP REST API 스펙 (PUT/GET/LIST/DELETE/...)
  = AWS가 만든 표준이지만 공개됨
  ─ AWS S3 implementation (AWS 클라우드)
  ─ Ceph RGW implementation (우리 자체 호스팅)
  ─ MinIO implementation
  ─ OpenStack Swift implementation
  ─ ... (셀 수 없이 많음)
```

**같은 SDK 코드** (`boto3`, AWS CLI 등)로 endpoint만 바꾸면 어느 구현체든 동작.

---

## 🎯 우리 사용 현황

| 항목 | 값 |
|---|---|
| 사용 중인 구현체 | **Ceph RGW** (자체 호스팅) |
| Endpoint | http://10.10.10.11:7480 |
| 사용 워크로드 | Harbor 이미지 blob (bucket: `harbor-registry`) |
| Bucket 사용량 | 약 5~10 GB (현재) |
| AWS S3 사용 | ❌ 없음 |

**Harbor helm values 증거**:
```yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      region: default
      bucket: harbor-registry
      regionendpoint: http://10.10.10.11:7480  # ← Ceph RGW (AWS 아님)
      v4auth: true
      secure: false
```

---

## 🔍 정밀 비교

### 1. 단가 비교 (Seoul region 2026)

| 항목 | AWS S3 Standard | Ceph RGW (우리 TCO) |
|---|---|---|
| **Storage** | $0.025/GB/월 (= ₩33/GB) | ₩44/GB/월 (인건비 제외 TCO) |
| **PUT/POST/COPY** | $0.0047/1000 req | $0 (내부망) |
| **GET/SELECT** | $0.00037/1000 req | $0 |
| **데이터 OUT (internet)** | $0.126/GB | $0 (내부망) |
| **데이터 OUT (same region)** | $0 | $0 |
| **API 호출 단위 청구** | 있음 | 없음 |
| **버킷 무제한** | ✅ | ✅ |

### 2. 성능 비교

| 차원 | AWS S3 | Ceph RGW |
|---|---|---|
| Latency (PUT) | 30~100ms (인터넷 경유) | 1~5ms (LAN) |
| Throughput (PUT) | 1 Gbps+ (multi-part) | 10G NIC 한계 (~1 GB/s) |
| Durability | 11 nines (99.999999999%) | 3-replica = ~6 nines |
| Availability | 99.99% SLA | 단일 RGW = SPoF (현재) |
| 동시 connection | 사실상 무제한 | RGW daemon 한계 (~수만) |

### 3. 시나리오별 월 비용

| 워크로드 | 용량 | AWS S3 | Ceph RGW | 차이 |
|---|---|---|---|---|
| Harbor (현재) | 10 GB + 1000 PUT/일 | $0.25 + $0.14 = **$0.4** (₩540) | **~₩440** (10GB × ₩44) | 비슷 |
| Harbor (성장 후) | 150 GB + 100 PUT/일 | $3.75 + $0.014 = **$3.8** (₩5,100) | **~₩6,600** | AWS가 약간 저렴 |
| Loki 7일 retention | 70 GB + 자주 write/read | $1.75 + 무거운 PUT/GET = **$15** (₩20,000) | **~₩3,100** | RGW 6배 저렴 |
| 대규모 (1 TB) | 1 TB | $25 + 요청 = **$30** (₩40,000) | **~₩44,000** | 거의 동일 |
| 백업 (10 TB) | 10 TB | $250 또는 Glacier $40 | **Ceph 용량 부족** | AWS 압승 |
| Cold 백업 (Glacier Deep Archive) | 10 TB | $10 | 불가 | AWS 압승 |

### 4. Break-even 분석

```
Storage 양 (GB)
  ↓
~100 GB:    거의 동일 (둘 다 작아서 무시)
100~500GB:  요청량 적으면 AWS, 많으면 Ceph
500GB~2TB:  Ceph 유리 (요청 비용 적용 시 큰 차이)
2TB~5TB:    수렴 (Ceph 용량 한계 도달)
5TB+:       AWS 유리 (Ceph는 노드 추가 비용)
Cold/Archive: AWS Glacier 압승 ($0.004/GB)
```

→ **우리 환경 (200GB 이하) = Ceph RGW가 명확히 유리**

---

## 💡 우리가 Ceph RGW를 선택한 이유

### 1. 💰 **비용 절감**
- Harbor + 향후 Loki/Tempo → 합쳐도 500GB 이하 예상
- AWS S3로 같은 사용 시 월 ₩2~3만 vs Ceph 무료 (TCO에 흡수)

### 2. 🌐 **데이터 주권**
- 컨테이너 이미지에 회사 IP 들어있음
- 외부 클라우드에 보내기 부담

### 3. ⚡ **저지연 + 고대역폭**
- LAN 1~5ms vs 인터넷 30~100ms
- Harbor에 큰 이미지 (1GB+) push/pull 빠름

### 4. 🔒 **외부 의존성 0**
- AWS API down → 우리 빌드 멈춤 X
- 인터넷 끊김 → 우리 클러스터 정상 동작

### 5. 📚 **학습 + 일관성**
- Ceph 운영 학습
- 같은 S3 SDK 코드 → 향후 AWS로 마이그레이션 쉬움

---

## ⚖️ Trade-off

### Ceph RGW 선택의 trade-off
| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 저지연 | RGW SPoF (현재 1 daemon) |
| 데이터 주권 | AWS 11 nines durability 못 누림 |
| 외부 의존성 X | 자체 운영 부담 |
| 학습 가치 | AWS 관리 ↓ 편의 X |

---

## 🚀 확장 가능성

### Option A: ⭐ AWS S3로 일부 마이그레이션 (hybrid)
- ✅ **장점**: 백업/cold storage는 AWS Glacier로 (월 $0.004/GB), 저렴 + DR
- ❌ **단점**: 인터넷 outbound 비용, 운영 분산
- 💰 **비용**: 10TB 백업 → 월 ₩50,000 (Glacier)
- 🎯 **추천 시점**: 백업 데이터 ↑ 또는 진짜 DR 필요

### Option B: ⭐ RGW HA (현재 1 → 2 daemon)
- ✅ **장점**: SPoF 해소, throughput 2배
- 💰 **비용**: 0
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option C: Erasure Coding pool (RGW backend)
- ✅ **장점**: 공간 효율 (3-replica 33% → EC 67%)
- ❌ **단점**: 노드 8대+ 권장 (현재 6대)
- 🎯 **추천 시점**: 대용량 cold storage

### Option D: MinIO로 교체
- ✅ **장점**: 가볍고 빠름, K8s native
- ❌ **단점**: Ceph 클러스터에 별도 솔루션 추가
- 🎯 **추천 시점**: Ceph 운영 부담 ↑

### Option E: 진짜 multi-cloud (AWS + GCP + Azure 모두 S3)
- ✅ **장점**: 진짜 멀티 클라우드 학습
- 🎯 **추천 시점**: 학습 가치 ★★★ 시

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 백업 용량 ↑ | A (AWS Glacier) |
| Harbor push 실패 | B (RGW HA) |
| Ceph 운영 어려움 | D (MinIO 검토) |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 자기 (`03-storage-types.md`) | RGW가 Ceph storage 종류 중 하나 |
| 🔧 CI/CD (`cicd/03-harbor-registry.md`) | Harbor가 RGW 사용 |
| 🏛️ 아키텍처 | 향후 Loki/Tempo S3 backend 결정 (`architecture/05-observability-design.md`) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Ceph RGW에 데이터 보내는 거랑 AWS S3 보내는 거랑 코드 차이?**
A. **endpoint만 바꿈**.
```python
# AWS S3
s3 = boto3.client('s3', endpoint_url='https://s3.ap-northeast-2.amazonaws.com')

# Ceph RGW (우리)
s3 = boto3.client('s3', endpoint_url='http://10.10.10.11:7480')
```
같은 SDK + bucket/key API. 호환성이 vendor lock-in 회피 핵심.

**Q2. 그럼 우리는 vendor lock-in이 없네?**
A. 맞아요. Harbor → Ceph RGW에서 → AWS S3로 endpoint만 바꾸면 동작. 마이그레이션도 `aws s3 sync` 한 줄.

**Q3. AWS S3가 11 nines인데 Ceph 3-replica는 6 nines. 위험 아닌가?**
A. (1) 우리 워크로드는 이미지 (재생성 가능, builds로), (2) 진짜 11 nines 필요한 데이터 (재무, 의료)는 별도 백업 → AWS Glacier. (3) Ceph snapshot으로 추가 보호.

**Q4. AWS S3 무한 확장인데 Ceph는 디스크 한계 있는데?**
A. 맞음. 그래서 (1) 우리는 200GB 이하 사용으로 한계 멀음, (2) 노드 추가하면 확장 (단, ★★★ 단계적), (3) 진짜 PB급 데이터면 AWS 또는 Ceph 노드 100대+ 도입.

**Q5. Ceph RGW가 죽으면 Harbor 못 쓰는데 백업이라도 AWS S3에 있나?**
A. 현재 없음. Phase 6에서 Harbor backup 정책 추가 시 (1) Harbor 자체 backup API, (2) `aws s3 sync s3://harbor-registry-on-ceph s3://harbor-backup-on-aws` 같은 cron job 검토.

**Q6. AWS S3로 다 가면 인건비 절감 + 가용성 ↑ 아닌가?**
A. 워크로드 규모 의존. 우리 같은 200GB는 비용 ₩2~3만/월 vs 운영 부담 차이 미미. 진짜 운영 규모 (수TB+) 가면 AWS가 합리적. 학습 환경엔 Ceph로 분산 시스템 + S3 호환성 모두 배움.
