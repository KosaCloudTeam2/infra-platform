# Storage Platform 발표 증거 설명서

> 대상: `storage-platform-evidence-verification-guide.md`에서 확보한 Evidence ID 목적:
> 캡처/영상/측정값을 발표에서 어떻게 설명할지 정리 원칙: 증거 없는 주장 금지, 의미 없는 수치 제외,
> 한계 포함

---

## 1. 설명 방식

발표 구조:

1. 설계 의도
2. 확보한 증거
3. 수치/캡처 의미
4. 한계와 개선안

말하기 규칙:

- "구성했습니다"보다 "무엇을 해결하기 위해 구성했는지" 우선
- "측정했습니다"보다 "측정값이 어떤 판단 근거인지" 우선
- 수치 단독 제시 금지
- 백업/replica/cache 역할 혼동 금지
- AWS RDS/OLAP/데이터 workload 범위 제외 명시

공통 발표 문장:

```text
제 담당 범위는 트래픽 자체보다, 트래픽이 몰렸을 때 데이터가 안정적으로 저장되고 빠르게 조회되도록 하는 온프레 storage, DB, backup, Redis 계층입니다.
각 증거는 단순 명령 결과가 아니라 설계 의도와 한계를 같이 설명하기 위한 자료로 준비했습니다.
```

---

## 2. Evidence 전체 연결표

| ID  | 검증 자료                     | 발표에서 말할 결론          | 발표 가치 |
| :-- | :---------------------------- | :-------------------------- | :-------- |
| E1  | Ceph 상태/용량/replica        | replica 기반 storage 안정성 | 높음      |
| E2  | RBD PVC/RGW bucket            | block/object 역할 분리      | 높음      |
| E3  | iperf3/fio/RADOS              | 10G 정상, HDD write 병목    | 높음      |
| E4  | ProxySQL/PXC wsrep            | 온프레 DB 경로와 HA         | 높음      |
| E5  | DB backup/binlog/restore      | DB 특정 시점 복구성         | 높음      |
| E6  | RGW/S3 count/dry-run          | object copy-only backup     | 높음      |
| E7  | HIT/MISS/Redis stats/DB stats | Redis 효용과 상태 일관성    | 높음      |
| E8  | Sentinel failover 영상        | Redis HA 동작 근거          | 높음      |
| Q1  | PXC sysbench                  | DB 성능 질문 대응           | 보조      |
| Q2  | RGW daemon/LB                 | endpoint HA 질문 대응       | 보조      |
| Q3  | redis-benchmark               | Redis capacity 질문 대응    | 보조      |

---

## 3. E1 Ceph 기본 상태와 Replica

### 3.1 보여줄 자료

- `ceph -s`
- `ceph df`
- pool `size/min_size`
- OSD tree

### 3.2 발표 메시지

```text
Ceph는 여러 OSD에 데이터를 분산 저장하고 replica를 유지하는 구조입니다.
이 구성에서는 디스크나 노드 장애가 발생해도 데이터 가용성 risk를 줄일 수 있습니다.
다만 replica는 같은 시점의 복제본이므로, 삭제나 오염까지 되돌리는 backup은 별도로 필요합니다.
```

### 3.3 자료 의미

- `HEALTH_OK`: 측정 신뢰성 기준
- `active+clean`: placement group 정상 기준
- `size=3`: replica 3개 유지 기준
- raw/usable 차이: replica trade-off
- OSD up/in: storage node 참여 상태

### 3.4 질문 대응

| 질문                         | 답변                                             |
| :--------------------------- | :----------------------------------------------- |
| replica가 backup 아닌가?     | 장애 risk 감소 수단, 특정 시점 복구 수단 아님    |
| usable 용량이 왜 줄어드는가? | 3-replica로 같은 data를 여러 OSD에 저장하기 때문 |
| replica의 장점               | 디스크/노드 장애 시 서비스 지속 가능성 향상      |

### 3.5 주의 표현

- 금지: `Ceph replica가 backup`
- 권장: `Ceph replica는 운영 중 장애 risk 감소, backup은 특정 시점 복구`

---

## 4. E2 RBD/RGW 사용처

### 4.1 보여줄 자료

- Kubernetes StorageClass/PVC
- RBD image 목록
- RGW bucket stats
- Harbor/App bucket object count

### 4.2 발표 메시지

```text
Ceph를 하나의 storage backend로 두고, RBD는 VM과 Kubernetes PVC 같은 block volume에 사용했습니다.
반면 RGW는 S3 호환 object storage로 사용해서 Harbor image blob과 앱의 이미지/영상 object를 저장하도록 분리했습니다.
```

### 4.3 자료 의미

- StorageClass/PVC: 앱이 실제 RBD 사용 중인 근거
- RBD image: Ceph 내부 block volume 존재 근거
- bucket stats: RGW object 저장 근거
- object count 증가: upload/push 흐름 확인 근거

### 4.4 질문 대응

| 질문                             | 답변                                                            |
| :------------------------------- | :-------------------------------------------------------------- |
| 왜 RBD와 RGW를 나눴나?           | block volume과 object storage의 access pattern 차이             |
| Harbor image인가 image blob인가? | 발표 중 Harbor image 가능, 저장 구조상 Harbor image blob이 정확 |
| 공연 기획 회사와 무슨 관련?      | 이미지/영상 object가 많아 S3 호환 object storage 가치 큼        |

### 4.5 주의 표현

- 금지: `docker image 저장`
- 권장: `Harbor image blob 저장`
- 금지: `RBD가 object 저장`
- 권장: `RBD는 block, RGW는 object`

---

## 5. E3 Ceph 10G와 HDD Write 병목

### 5.1 보여줄 자료

- `ethtool` 10G link
- `iperf3` 9Gbps 이상 결과
- RADOS 4K write
- RBD 4K randwrite cache on/off
- RBD 1M seqwrite
- 발표용 성능 표

### 5.2 발표 메시지

```text
하드 간 연결은 10G로 구성되어 있고, iperf3로 network 대역폭은 정상에 가깝게 확인했습니다.
하지만 Ceph write 성능은 HDD 기반 OSD와 replica write path의 영향을 받았습니다.
따라서 현재 병목은 network보다 disk/write path에 가깝고, 운영급 구성에서는 SSD WAL/DB 분리나 NVMe OSD가 개선 후보입니다.
```

### 5.3 자료 의미

| 측정값          | 의미                          |
| :-------------- | :---------------------------- |
| NIC raw iperf3  | 10G fabric 정상 여부          |
| RADOS 4K write  | Ceph backend write 기준       |
| RBD cache on    | client cache 포함 수치        |
| RBD cache off   | disk/write path에 가까운 수치 |
| RBD 1M seqwrite | 대용량 write throughput       |

### 5.4 발표 표 예시

| 항목            | 기존 참고값  | 최신 측정값 | 발표 해석          |
| :-------------- | :----------- | :---------- | :----------------- |
| NIC raw iperf3  | 9.4Gbps      |             | 10G 정상           |
| RADOS 4K write  | 99 IOPS      |             | backend write 한계 |
| RBD cache on    | 1,700 IOPS   |             | cache 포함         |
| RBD cache off   | 100~200 IOPS |             | HDD 영향           |
| RBD 1M seqwrite | 35MB/s       |             | 대용량 write 기준  |

### 5.5 질문 대응

| 질문                       | 답변                                                       |
| :------------------------- | :--------------------------------------------------------- |
| 10G인데 왜 느린가?         | network는 충분, HDD random write와 replica write path 영향 |
| cache on 수치를 써도 되나? | 조건 명시 시 가능, disk 성능으로 말하면 안 됨              |
| 운영급이면 어떻게 개선?    | SSD WAL/DB 분리, NVMe OSD, replica/EC 정책 재검토          |

### 5.6 주의 표현

- 금지: `10G라서 Ceph도 빠름`
- 권장: `10G는 정상, write 병목은 HDD/write path`
- 금지: `1,700 IOPS가 실제 disk 성능`
- 권장: `cache 포함 조건의 측정값`

---

## 6. E4 온프레 DB 경로와 PXC 상태

### 6.1 보여줄 자료

- ProxySQL `mysql_servers`
- ProxySQL `mysql_query_rules`
- PXC `wsrep_cluster_status`
- PXC `wsrep_cluster_size`
- PXC PVC

### 6.2 발표 메시지

```text
온프레 앱은 PXC node에 직접 붙지 않고 ProxySQL endpoint를 통해 접근합니다.
PXC는 Galera 기반 3-node 구조로 운영 DB의 가용성을 확보하고, 각 DB Pod는 Ceph RBD PVC를 사용합니다.
```

### 6.3 자료 의미

- ProxySQL route: 앱 DB 접근 경로 근거
- PXC wsrep status: cluster 정상성 근거
- wsrep cluster size: node 수 근거
- RBD PVC: DB storage 계층 근거

### 6.4 질문 대응

| 질문               | 답변                                                |
| :----------------- | :-------------------------------------------------- |
| 왜 ProxySQL 사용?  | 앱 endpoint 단순화, writer routing, connection 관리 |
| ProxySQL 단일이면? | SPOF 가능, 복수 ProxySQL/VIP 개선 후보              |
| AWS DB도 포함?     | 담당 범위는 온프레 DB, AWS RDS/OLAP는 제외          |

### 6.5 주의 표현

- 금지: `PXC라서 모든 장애 무중단`
- 권장: `PXC는 DB node 장애 risk를 줄이고, quorum과 routing 관리 필요`

---

## 7. E5 DB Backup 복구성

### 7.1 보여줄 자료

- DB backup 파일 timestamp
- binlog 활성화
- restore dry-run 또는 restore test 결과

### 7.2 발표 메시지

```text
DB는 단순 파일 복사가 아니라 트랜잭션 일관성이 중요합니다.
그래서 replica와 별개로 DB backup과 binlog를 확인했고, 복구 가능성은 restore dry-run 또는 별도 복구 테스트로 판단했습니다.
```

### 7.3 자료 의미

- backup timestamp: 최신 backup 기준
- binlog: 특정 시점 복구 가능성
- restore dry-run: 복구 절차 검증 근거
- restore 미수행: backup file 존재까지만 의미

### 7.4 질문 대응

| 질문                                | 답변                                 |
| :---------------------------------- | :----------------------------------- |
| Ceph replica면 DB backup 필요 없나? | 논리적 삭제/오염/실수 대응 위해 필요 |
| backup 성공 기준은?                 | 파일 존재 + restore 검증이 가장 확실 |
| restore 미수행이면?                 | 복구 검증은 후속 과제라고 표현       |

### 7.5 주의 표현

- 금지: `백업 파일 있으니 복구 가능`
- 권장: `백업 파일 존재, restore 검증 여부에 따라 표현 구분`

---

## 8. E6 Object Backup Copy-only

### 8.1 보여줄 자료

- RGW source bucket stats
- AWS S3 backup object count
- lifecycle 설정
- restore dry-run

### 8.2 발표 메시지

```text
정적 이미지와 영상 object는 Ceph RGW에 저장하고, AWS S3로 copy-only backup을 구성했습니다.
copy-only 방식은 원본 삭제나 실수 삭제가 backup까지 즉시 전파되는 것을 막기 위한 선택입니다.
```

### 8.3 자료 의미

- source count/size: 원본 object 기준
- backup count/size: 백업 반영 기준
- lifecycle: 장기 보관 정책
- restore dry-run: 복원 경로 확인

### 8.4 질문 대응

| 질문                             | 답변                                                          |
| :------------------------------- | :------------------------------------------------------------ |
| 왜 sync-delete가 아닌 copy-only? | 원본 삭제 실수가 backup 삭제로 전파되는 risk 차단             |
| Ceph replica와 차이?             | replica는 운영 장애 대응, AWS S3 backup은 별도 위치 복구 수단 |
| Harbor blob도 backup?            | Harbor image blob은 replication/archive 정책과 분리 설명 필요 |

### 8.5 주의 표현

- 금지: `Ceph replica가 있으니 object backup 불필요`
- 권장: `replica는 가용성, AWS S3 backup은 복구성`

---

## 9. E7 Redis 일관성/Cache 효과

### 9.1 보여줄 자료

- Cache HIT latency
- Cache MISS latency
- Redis keyspace hits/misses
- DB Questions/Threads_connected 전후
- HIT/MISS 개선 배율 표

### 9.2 발표 메시지

```text
Redis는 단순 캐시가 아니라, 티켓팅처럼 트래픽이 몰리는 상황에서 DB 부하를 줄이고 예매 상태를 빠르게 조회하게 하는 계층입니다.
또한 AWS와 온프레미스 앱이 RDS read replica 지연 차이가 아니라 Redis의 동일 key를 기준으로 예매 상태를 판단하도록 설계했습니다.
```

### 9.3 자료 의미

| 자료                 | 의미                        |
| :------------------- | :-------------------------- |
| HIT latency          | Redis 응답 경로 사용자 체감 |
| MISS latency         | DB 접근 포함 경로           |
| improvement ratio    | cache 효과                  |
| keyspace hits/misses | Redis 사용 근거             |
| DB Questions 변화    | DB 부하 감소 근거           |

### 9.4 발표 표 예시

| 항목                   | 측정값 | 발표 해석         |
| :--------------------- | :----- | :---------------- |
| Cache HIT latency      |        | Redis 조회 경로   |
| Cache MISS latency     |        | DB 접근 포함 경로 |
| HIT/MISS 개선 배율     |        | 사용자 체감 개선  |
| keyspace_hits 증가     |        | cache 사용 근거   |
| DB Questions 감소/완화 |        | DB offload 근거   |

### 9.5 질문 대응

| 질문                  | 답변                                                     |
| :-------------------- | :------------------------------------------------------- |
| Redis가 DB 대체?      | 아님, 원장 data는 DB, Redis는 cache/status/queue 계층    |
| 일관성은 어떻게?      | 중요한 예매 상태는 AWS/온프레가 Redis 동일 key 기준 조회 |
| hit ratio만으로 충분? | 아님, DB Questions/connection 변화와 함께 봐야 함        |

### 9.6 주의 표현

- 금지: `Redis가 DB 역할`
- 권장: `Redis는 빠른 조회와 상태 기준점, DB는 원장`
- 금지: `hit ratio만으로 DB 부하 감소 증명`
- 권장: `hit ratio + DB query 변화로 설명`

---

## 10. E8 Redis Sentinel Failover

### 10.1 보여줄 자료

- Sentinel `ckquorum`
- failover 전 master
- failover 후 master
- failover 후 cache hit
- 30~60초 영상

### 10.2 발표 메시지

```text
Redis는 Sentinel 3-node/quorum 2 기준으로 구성했습니다.
수동 failover 시연에서는 기존 master가 바뀌고, 이후에도 cache 요청이 동작하는 것을 확인해 Redis 계층의 HA 근거로 제시합니다.
```

### 10.3 자료 의미

- `ckquorum`: Sentinel 합의 가능성
- master before/after: failover 발생 근거
- cache hit after: 앱 관점 동작 확인
- failover time: 전환 시간

### 10.4 질문 대응

| 질문                            | 답변                                               |
| :------------------------------ | :------------------------------------------------- |
| Sentinel이면 무중단?            | 0초 무중단 아님, 전환 시간과 client reconnect 필요 |
| 왜 Pod kill 대신 수동 failover? | 발표 시 안전한 controlled failover                 |
| Redis Cluster와 차이?           | Sentinel은 HA 중심, Cluster는 sharding 포함        |

### 10.5 주의 표현

- 금지: `Sentinel이라 장애 영향 없음`
- 권장: `Sentinel은 failover를 제공하지만 전환 시간 존재`

---

## 11. Q&A 보조 증거 설명

### 11.1 Q1 PXC OLTP 성능

사용 조건:

- 실제 sysbench 측정값 존재
- test schema 기준 설명 가능
- cleanup 확인

발표 위치:

- 본문 슬라이드 제외
- DB 성능 질문 시 보조 답변

답변 문장:

```text
PXC OLTP 성능은 별도 test schema에서 sysbench로 TPS와 p95 latency를 확인했습니다.
다만 실제 서비스 쿼리와 완전히 동일하지 않기 때문에, 발표 본문에서는 구조와 HA 근거를 중심으로 제시했습니다.
```

### 11.2 Q2 RGW Endpoint HA

사용 조건:

- RGW daemon 수 확인
- LB/VIP 존재 여부 확인
- 단일 endpoint이면 risk로 설명

답변 문장:

```text
RGW의 object data는 Ceph pool replica 대상이지만, S3 API endpoint 자체의 HA는 별도 구성 요소입니다.
현재 endpoint가 단일이면 data durability와 service endpoint HA를 구분해서 개선 과제로 설명합니다.
```

### 11.3 Q3 Redis Benchmark

사용 조건:

- app HIT/MISS 수치 확보 후 보조로만 사용
- Redis 자체 capacity 질문 시 사용

답변 문장:

```text
Redis benchmark는 Redis 자체 처리 여유를 보는 보조 지표입니다.
사용자 체감 효과는 benchmark보다 ticket-app의 Cache HIT/MISS 응답 시간으로 설명하는 것이 더 적절합니다.
```

---

## 12. 발표 제외 기준

제외할 자료:

- 설명 없는 명령 성공 캡처
- endpoint/IP/name이 중심인 캡처
- 운영 세부 설정 나열
- 단독 benchmark 결과
- 실제 app 흐름과 연결 안 되는 수치
- 실패 원인 설명 불가 수치

제외 이유:

- 발표 메시지 불명확
- 질문 시 방어 어려움
- 전문가 청중에게 노이즈
- 보안/운영 정보 노출 risk

---

## 13. 최종 발표 흐름

권장 순서:

1. Ceph 선택 이유와 역할 분리: E1, E2
2. 성능 검증과 한계: E3
3. 온프레 DB 운영 경로: E4
4. backup 정책: E5, E6
5. Redis 효용과 일관성: E7
6. Redis HA 시연: E8

마무리 문장:

```text
이번 담당 범위의 핵심은 storage와 cache 계층을 단순히 설치한 것이 아니라, 실제 발표에서 증명 가능한 근거로 연결한 점입니다.
Ceph는 block/object storage 기반과 replica 가용성을 제공했고, backup은 replica와 별도로 복구성을 담당했습니다.
Redis는 DB 부하 감소와 예매 상태 기준점 역할을 했고, Sentinel failover로 HA 동작 근거를 확보했습니다.
```
