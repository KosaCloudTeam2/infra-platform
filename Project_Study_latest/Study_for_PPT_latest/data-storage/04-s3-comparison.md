# 04. Ceph RGW vs AWS S3 — 비용/효율 비교

> ⭐ **한 줄 요약**: **"S3"는 프로토콜이지 서비스가 아니다.** Ceph RGW는 우리 클러스터에서 돌아가는 S3 호환 API (무료, 내부망)고, AWS S3는 Amazon이 운영하는 클라우드 서비스 (GB 과금)다. 우리 환경처럼 약 200GB 이하 사용에선 **Ceph RGW가 4~5배 저렴**하다.

---

## 🎯 핵심 개념부터 — "S3"라는 단어의 두 가지 의미

많은 사람이 "S3"라고 하면 **AWS S3 서비스** 하나만 떠올린다. 그런데 사실 S3는 **HTTP REST API 스펙**의 이름이기도 하다. Amazon이 2006년에 만든 이 표준은 워낙 보편화되어, 지금은 수많은 회사가 같은 API를 흉내내는 자체 구현체를 만들어 쓴다.

우리 프로젝트의 Harbor는 "S3 백엔드"를 쓰는데, 이때 S3가 AWS S3가 아니라 우리 Ceph 클러스터에서 돌아가는 **Ceph RGW**다. 같은 S3 SDK 코드 (`boto3`, AWS CLI 등)로 endpoint만 바꾸면 어느 구현체든 동일하게 작동한다. 이 점이 매우 중요한 이유는, 한 번 Ceph RGW로 시작했어도 나중에 AWS S3로 옮기는 게 endpoint URL 변경 한 줄이라는 뜻이다. **벤더 락인 회피의 핵심**이 바로 이 S3 호환성이다.

```
S3 (프로토콜) 구현체들:
  ├─ AWS S3          (Amazon)
  ├─ Ceph RGW        (우리)
  ├─ MinIO           (오픈소스, 가볍고 빠름)
  ├─ OpenStack Swift (오래된 클래식)
  └─ ... 수십 개
```

---

## 🎯 우리 사용 현황

현재 우리는 AWS S3를 단 한 글자도 사용하지 않는다. 대신 Ceph 클러스터 안에서 돌고 있는 RGW (RADOS Gateway) 데몬을 통해 S3 API를 우리 인프라 안에서 제공한다.

| 항목 | 값 |
|---|---|
| 사용 중인 구현체 | **Ceph RGW** (자체 호스팅) |
| Endpoint | http://10.10.10.11:7480 |
| 사용 워크로드 | Harbor 이미지 blob (bucket: `harbor-registry`) |
| Bucket 사용량 | 약 5~10 GB (현재) |
| AWS S3 사용 | ❌ 없음 |

Harbor가 진짜로 Ceph RGW를 백엔드로 쓰는 증거는 helm values에서 확인할 수 있다.

```yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      region: default
      bucket: harbor-registry
      regionendpoint: http://10.10.10.11:7480  # ← 우리 Ceph (AWS 아님)
      v4auth: true
      secure: false
```

`regionendpoint`가 AWS의 `https://s3.ap-northeast-2.amazonaws.com` 같은 외부 주소가 아니라, 우리 ceph1 노드의 내부 IP인 `10.10.10.11:7480`인 점이 핵심이다. Harbor 입장에선 그저 "S3 API를 말하는 서버"가 외부냐 내부냐 차이일 뿐, 동작은 똑같다.

---

## 🔍 정밀 비교

### 1. 단가 비교 (Seoul region 2026 기준)

먼저 두 옵션의 가격 구조를 살펴보자. AWS S3는 사용량 기반 종량제고, Ceph RGW는 우리가 이미 소유한 인프라 위에서 돌아가니까 추가 단가가 없다.

| 항목 | AWS S3 Standard | Ceph RGW (우리 TCO) |
|---|---|---|
| Storage | $0.025/GB/월 (~₩33/GB) | ₩44/GB/월 (인건비 제외) |
| PUT/POST 요청 | $0.0047/1000 | $0 (내부망) |
| GET 요청 | $0.00037/1000 | $0 |
| 데이터 OUT (인터넷) | $0.126/GB | $0 (내부망) |
| 데이터 OUT (same region) | $0 | $0 |

표만 봐선 Ceph가 GB당 더 비싸 보일 수도 있다 (₩44 vs ₩33). 하지만 이건 단순 비교가 함정인 게, **AWS는 요청 1000건마다 별도 과금이 붙고 데이터 outbound가 GB당 12센트**다. 실제 워크로드에서 요청과 트래픽이 쌓이면 이 부수 비용이 storage 단가보다 더 커질 수 있다. 반면 Ceph는 우리 LAN 안이라 요청도 트래픽도 모두 무료다.

### 2. 성능 비교

성능은 우리 환경의 압도적 우위다.

| 차원 | AWS S3 | Ceph RGW |
|---|---|---|
| Latency (PUT) | 30~100ms (인터넷 경유) | 1~5ms (LAN) |
| Throughput (PUT) | 1 Gbps+ (multi-part 시) | 10G NIC 한계 (~1 GB/s) |
| Durability | 11 nines (99.999999999%) | 3-replica = ~6 nines |
| Availability | 99.99% SLA | 단일 RGW = SPoF (현재) |

**Latency**가 30~50배 차이 나는 이유는 단순하다. AWS S3로 가려면 우리 클러스터 → pfSense → ISP → AWS Seoul region까지 거쳐야 하니까 round-trip 자체가 수십 ms다. Ceph RGW는 같은 10G 패브릭 안에 있으니 ping latency가 그대로 응답시간이다.

**Durability** 측면에선 AWS가 훨씬 강하다. AWS S3의 "11 nines"는 1000만 개 파일 중 1개 손실에 1만 년 걸리는 수준의 보장이다. 우리 Ceph 3-replica는 약 6 nines로, 진짜 critical한 백업 데이터를 보관할 정도는 아니다. 그래서 **이미지 같이 재생성 가능한 데이터는 Ceph, 진짜 영구 보관 데이터는 AWS S3**로 분리하는 게 합리적이다.

### 3. 시나리오별 실제 비용

추상적인 단가 비교보다 우리 실제 워크로드를 대입해보는 게 더 와닿는다.

| 워크로드 | 용량 | AWS S3 월비용 | Ceph RGW 월비용 | 차이 |
|---|---|---|---|---|
| Harbor (현재) | 10 GB | ~₩540 | ~₩440 | 비슷 |
| Harbor (성장 후) | 150 GB | ~₩5,100 | ~₩6,600 | 약간 AWS 유리 |
| Loki 7일 retention | 70 GB + 자주 write/read | ~₩20,000 | ~₩3,100 | **RGW 6배 저렴** |
| 1 TB | 1 TB | ~₩40,000 | ~₩44,000 | 거의 동일 |
| 백업 (10 TB) | 10 TB | $250 또는 Glacier $40 | Ceph 용량 부족 | **AWS 압승** |
| Cold archive (Glacier Deep Archive) | 10 TB | $10 | 불가 | **AWS 압승** |

흥미로운 패턴이 보인다. **작은 용량이면 거의 비슷하고, 중간 용량 + 요청 많은 워크로드 (Loki 같은 로그)는 Ceph가 압도적, 대용량 cold storage는 AWS Glacier가 압도적이다.**

특히 Loki 케이스를 보면 Ceph가 6배 저렴한 이유는 **로그 쓰기/읽기 트래픽이 매우 많기 때문**이다. AWS S3는 요청 1건당 과금이 붙고 outbound 데이터 비용도 발생하는데, Loki처럼 초당 수십~수백 건씩 chunk를 쓰고 읽으면 이게 누적되어 storage 단가의 몇 배까지 부풀어 오른다. 우리 Ceph RGW는 그런 요청 비용이 0이라 가격 차이가 폭발적으로 벌어진다.

### 4. Break-even 분석 — 언제 어느 게 유리한가

```
Storage 양 (GB)
  ↓
~100 GB:      거의 동일 (둘 다 너무 작아 차이 무시)
100~500 GB:   요청 적으면 AWS, 요청 많으면 Ceph 유리
500 GB~2 TB:  Ceph 명확히 유리 (요청 비용 효과 큼)
2~5 TB:       수렴 (Ceph 용량 한계 접근, 노드 추가 비용 발생)
5 TB 이상:    AWS 유리 (Ceph는 노드 추가 ★★★)
Cold/Archive: AWS Glacier 압승
```

우리 환경처럼 200GB 이하면 **명확히 Ceph가 유리**다. 하지만 만약 5TB 이상의 백업 데이터를 다뤄야 한다면 그땐 AWS S3 Glacier가 합리적이다. 이건 hybrid 패턴으로 풀 수 있다 (밑의 확장 옵션 A 참고).

---

## 💡 우리가 Ceph RGW를 선택한 이유

위 비교를 바탕으로 우리가 Ceph RGW를 선택한 진짜 이유를 풀어 설명하면 다섯 가지다.

**첫째, 비용이 명백히 우리 편이다.** Harbor에 향후 Loki/Tempo S3 backend까지 합쳐도 500GB를 넘기 어렵다. 같은 사용량을 AWS S3로 했을 때 월 ₩2~3만이 발생하는데, Ceph RGW는 이미 깔린 Ceph 인프라 위에서 돌아 추가 비용이 사실상 0이다. 1년 ₩30만 절감은 학습 환경에선 작아 보여도, **트레이드오프 분석을 직접 한 결과**라는 점에서 학습 가치가 크다.

**둘째, 데이터 주권 문제다.** 컨테이너 이미지 안에는 우리 회사의 코드, 빌드 결과물, 때로는 환경 변수에 박힌 설정값까지 들어 있다. 이걸 외부 클라우드에 모두 보내는 건 컴플라이언스/보안 관점에서 부담스러운 결정이다. 우리 클러스터 안에서 처리하면 데이터가 절대 외부로 안 나간다.

**셋째, 지연시간이 30배 이상 차이난다.** Harbor에 1GB짜리 이미지를 push할 때 AWS S3로 보내면 인터넷 trip + AWS API gateway까지 거쳐 수십 초 걸린다. Ceph는 같은 LAN 안이라 거의 디스크 속도에 가깝게 끝난다. CI 빌드 시간에 직접 영향을 주는 부분이다.

**넷째, 외부 의존성이 0이다.** AWS S3 API가 일시적으로 down되면 (실제로 1년에 몇 번씩 발생) 우리 빌드가 멈춘다. 인터넷이 끊겨도 같은 문제. Ceph는 우리 데이터센터 안이라 외부 사고와 완전 격리된다.

**다섯째, 학습 가치다.** Ceph 분산 시스템을 직접 운영해보는 경험은 어디서 사기 어렵다. 동시에 S3 API와 100% 호환되니, 향후 AWS로 옮기더라도 코드 한 줄 안 바꾸고 endpoint만 교체하면 된다. 진짜 vendor lock-in 회피 패턴을 손으로 익힌 셈이다.

---

## ⚖️ Trade-off — 잃은 것도 있다

Ceph RGW를 선택하면서 우리가 의식적으로 포기한 것들이 있다.

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 저지연 | RGW SPoF (현재 1 daemon만) |
| 데이터 주권 | AWS 11 nines durability 못 누림 |
| 외부 의존성 0 | 자체 운영 부담 (Ceph 클러스터 관리) |
| 학습 가치 | AWS 관리 편의 (자동 백업, 무한 확장) X |

가장 큰 약점은 **현재 RGW가 ceph1 노드 1개 daemon만 돌고 있다는 점**이다. 이 노드가 죽으면 Harbor의 이미지 push/pull이 즉시 멈춘다. AWS S3는 region 단위로 multi-AZ 자동 분산이라 이런 SPoF가 없다. 우리는 Phase 6에서 RGW를 ceph2에도 추가해 HA를 확보할 계획인데, 이건 확장 옵션 B에서 자세히 다룬다.

또 다른 한계는 **용량이 우리 디스크 한계 안**이라는 점이다. Raw 6TB에서 3-replica 적용하면 실제 가용 2TB. 이 이상 쓰려면 노드 추가가 필요한데, AWS S3는 그냥 용량 제한이 없다. 그래서 진짜 대용량 백업 같은 use case는 hybrid 패턴 (Ceph hot + AWS cold)이 합리적이다.

---

## 🚀 확장 가능성

여기서부터는 우리 환경이 성장하거나 운영 요구가 강화될 때 어떤 옵션이 있는지 정리한다.

### Option A: ⭐ AWS S3로 일부 마이그레이션 (hybrid 패턴)

가장 현실적이고 추천하는 확장이다. **Hot 데이터 (자주 사용)는 Ceph RGW에 두고, cold 데이터 (백업/archive)는 AWS S3 Glacier로 보내는** 분리 전략이다. AWS Glacier Deep Archive는 GB당 월 $0.001 (₩1.3) 수준으로 극히 저렴해서, 1TB 백업도 월 ₩1300 정도밖에 안 된다.

운영은 cron job 하나로 충분하다. 매일 새벽 Ceph RGW에서 N일 이상 된 객체를 AWS S3로 sync한 다음 Ceph에서 삭제. Ceph 공간 절약 + AWS 백업 모두 챙긴다.

- 💰 **비용**: 10TB 백업 → 월 ₩50,000 (Glacier 기준)
- ⏱️ **작업**: 4시간 (lifecycle 정책 + cron + 모니터링)
- 🎯 **추천 시점**: 백업 데이터 누적 또는 진짜 DR 정책 정립 시

### Option B: ⭐ RGW HA — 현재 1 daemon → 2 daemon

지금의 가장 큰 약점인 RGW SPoF를 해소한다. ceph2 노드에 RGW 데몬을 추가로 띄우고, Harbor의 `regionendpoint`를 HAProxy 같은 load balancer 뒤로 보내 round-robin시킨다. 작업이 가볍고 (2~4시간), 비용도 0이라 **Phase 6 최우선 작업** 중 하나다.

- 💰 **비용**: 0 (다른 Ceph 노드의 자원만 사용)
- ⏱️ **작업**: 2~4시간 (RGW 추가 + HAProxy 설정 + Harbor regionendpoint 변경)
- 🎯 **추천 시점**: 즉시

### Option C: Erasure Coding pool (RGW 백엔드 최적화)

3-replica는 저장 효율이 33%인 반면, Erasure Coding 4+2는 67% 효율이다. 같은 디스크 용량으로 2배 더 저장 가능하다. 단점은 EC를 안정적으로 운영하려면 최소 8개 OSD가 권장돼 우리 6 노드론 부족하다.

- 🎯 **추천 시점**: Ceph 노드를 8대 이상으로 늘리고 cold storage 비중이 커진 후

### Option D: MinIO로 교체

MinIO는 S3 호환 외에는 다 빼고 가볍게 만든 솔루션이다. Ceph보다 메모리 사용량이 적고 setup이 단순하다. 단점은 Ceph가 제공하는 Block(RBD)/File(CephFS)까지 통합 운영하는 매력을 포기하게 된다.

- 🎯 **추천 시점**: Ceph 운영 부담을 줄이고 S3 기능만 원할 때 (우리엔 안 맞음)

### Option E: 진짜 multi-cloud (AWS + GCP + Azure 모두 S3)

학습 목적으로 여러 cloud의 S3 호환 스토리지를 동시에 사용해보는 옵션. 같은 SDK 코드로 endpoint만 바꿔 어디든 push 가능. vendor lock-in 회피 실전 학습이 된다.

- 🎯 **추천 시점**: 학습 가치 우선 + 비용 부담 가능할 때

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 백업 용량 급증 | A (AWS Glacier hybrid) |
| Harbor push 자주 실패 | B (RGW HA) — Phase 6 최우선 |
| Ceph 운영 부담 ↑ | D (MinIO 검토) |
| 학습 가치 최대 | E (multi-cloud) |

---

## 🔗 다른 파트와의 연결

이 문서는 우리 인프라의 여러 부분과 맞물려 있다. 데이터 파트의 `03-storage-types.md`는 RGW가 Ceph 스토리지의 세 종류 (RBD/CephFS/RGW) 중 어떤 위치인지 설명한다. CI/CD 파트의 `cicd/04-harbor-registry.md`는 Harbor가 RGW를 어떻게 사용하는지 설정 관점에서 다룬다. 아키텍처의 `architecture/05-observability-design.md`는 향후 Loki/Tempo의 백엔드도 RGW로 전환할 계획을 언급한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Ceph RGW와 AWS S3가 코드 차이 있나요?**
**A.** 거의 없습니다. **endpoint URL만 바꾸면 같은 SDK 코드가 동작**합니다.
```python
# AWS S3
s3 = boto3.client('s3', endpoint_url='https://s3.ap-northeast-2.amazonaws.com')

# Ceph RGW (우리)
s3 = boto3.client('s3', endpoint_url='http://10.10.10.11:7480')
```
이 호환성이 vendor lock-in 회피의 핵심이고, Harbor가 이 패턴을 쓰는 이유입니다.

**Q2. 그럼 우리는 vendor lock-in이 정말 없나요?**
**A.** 코드 레벨에선 없습니다. Harbor를 AWS S3로 옮기고 싶으면 `regionendpoint`만 바꾸면 됩니다. 데이터 이동은 `aws s3 sync` 한 줄로 끝나고요. 다만 Lambda/CloudWatch/Route53 같은 다른 AWS native 서비스는 lock-in이 있죠 — 그건 우리가 hybrid 환경을 선택한 의식적 트레이드오프입니다.

**Q3. AWS S3가 11 nines durability인데 Ceph 6 nines는 위험하지 않나요?**
**A.** 데이터 종류에 따라 다릅니다. **우리 use case는 컨테이너 이미지** — Jenkins가 다시 build하면 재생성 가능합니다. 그래서 6 nines로 충분하고, 11 nines가 필요한 진짜 영구 보관 데이터 (재무 기록, 의료 기록 등)는 별도로 AWS Glacier 같은 데로 백업하는 hybrid 패턴이 합리적입니다.

**Q4. AWS S3는 무한 확장인데 Ceph는 디스크 한계 있지 않나요?**
**A.** 맞습니다. 우리 현재 사용은 200GB 이하라 한계가 멀지만, 만약 PB 단위로 가야 하면 (1) Ceph 노드 추가, (2) AWS S3로 일부 이전 두 가지 옵션이 있습니다. 진짜 PB급 영구 데이터는 AWS가 더 합리적이고, 우리 정도 규모엔 Ceph + 노드 추가가 비용 효율적입니다.

**Q5. Ceph RGW가 죽으면 Harbor 못 쓰는데 백업이라도 AWS S3에 있나요?**
**A.** 현재는 없습니다 (학습 환경 단순화). Phase 6에서 Harbor backup 정책 추가 시 `aws s3 sync` cron job으로 Ceph → AWS 동기화를 검토할 예정입니다. 이게 위 확장 옵션 A의 구체적인 실행 모습입니다.

**Q6. AWS로 다 가면 운영 부담도 줄고 가용성도 올라가지 않나요?**
**A.** 워크로드 규모와 우선순위에 따라 다릅니다. 우리처럼 200GB 정도면 비용은 ₩2~3만/월 차이라 미미하고, **학습 가치와 데이터 주권**을 더 중요시했습니다. 진짜 운영 단계에서 트래픽이 수TB 단위가 되면 AWS가 합리적이고, 그땐 Ceph→S3 마이그레이션이 endpoint URL 변경뿐이라 비용도 적습니다.
