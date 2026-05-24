# Storage Platform 발표 근거/설명 자료

> 대상: Ceph(분산 스토리지), 온프레 DB(Database), Backup(백업), Redis(인메모리 데이터 저장소) 발표
> 설명용 목적: 수치/캡처의 의미, 기술 선택 근거, Q&A 답변 기준 정리 제외: AWS RDS, OLAP, 데이터
> workload 튜닝, burst 전체 자동화 상세

---

## 1. 발표 범위

담당 범위:

- Ceph(분산 스토리지)
- RBD(RADOS Block Device)
- RGW(RADOS Gateway)
- 온프레 DB(Percona XtraDB Cluster/PXC, ProxySQL)
- Backup(DB backup, object backup)
- Redis(인메모리 데이터 저장소)

제외 범위:

- AWS RDS 설계
- OLAP/분석 workload
- 데이터 파이프라인
- EKS 운영 상세
- Route 53 burst automation 상세

발표 관점:

- 트래픽 외 인프라 기반
- 저장소 성능
- 데이터 가용성
- 백업 복구성
- 캐시/예매 상태 일관성

---

## 2. 핵심 메시지

요약:

- Ceph: 온프레에서 block/object storage 동시 제공
- RBD: Kubernetes PVC, VM disk 기반
- RGW: Harbor image blob, 앱 object 저장 기반
- PXC: 온프레 운영 DB 고가용성 기반
- ProxySQL: 앱 DB endpoint 단순화와 writer routing 기반
- Backup: replica와 별개인 특정 시점 복구 수단
- Redis: DB 부하 감소 + AWS/온프레 예매 상태 단일 기준점

발표 문장 후보:

```text
저는 트래픽 처리 자체보다, 트래픽이 몰렸을 때도 데이터를 안정적으로 보관하고 빠르게 접근하게 만드는 저장소와 캐시 계층을 담당했습니다.
Ceph는 RBD와 RGW를 통해 VM/Kubernetes 볼륨과 object 저장소를 함께 제공했고, Redis는 DB 부하 감소와 예매 상태 일관성 기준점 역할을 맡았습니다.
```

---

## 3. Ceph 설명 근거

### 3.1 Ceph 선택 이유

프로젝트 가정:

- 공연 기획 회사
- 티켓팅 서비스 운영
- 이미지/영상 자료 다수 보유
- 자체 온프레 인프라 활용 필요
- cloud bursting 시 AWS 연계 필요

Ceph 사용 이유:

- scale-out storage 구성 가능
- RBD/RGW/CephFS 등 다양한 interface 제공
- commodity server 기반 확장 가능
- Kubernetes PVC와 Proxmox VM disk 연계 가능
- S3 호환 object storage 제공
- replica/self-healing 기반 장애 risk 감소

효용가치:

- storage 운영 단일화
- block/object storage 분리 제공
- Harbor image blob 저장 기반 확보
- 앱 이미지/영상 object 저장 기반 확보
- 디스크/노드 장애 시 data availability 향상

### 3.2 RBD/RGW 사용 구분

RBD:

- block volume
- Kubernetes PVC
- Proxmox VM disk
- Redis/PXC/Jenkins/Prometheus 등 Stateful workload 저장소
- access mode 대부분 RWO(ReadWriteOnce)

RGW:

- S3-compatible object storage
- Harbor image blob 저장
- 앱 object 이미지/영상 저장
- bucket/object 단위 관리
- AWS S3 copy backup 대상

발표 표현:

- `RBD는 VM과 Kubernetes Pod가 사용하는 block storage`
- `RGW는 Harbor image blob과 앱 object를 저장하는 S3 호환 storage`

용어 참고:

- 발표 중 쉬운 표현: `Harbor image`
- 구조상 정확한 표현: `Harbor image blob`
- 이유: registry는 image layer와 manifest를 blob 형태로 저장

### 3.3 현재 설정 선택 이유

3-replica:

- OSD 장애 대응
- 노드 장애 대응
- read availability 향상
- usable capacity 감소 trade-off

HDD 기반 OSD:

- 학습/시연 환경 비용 절감
- 대용량 object 저장 가정과 부합
- random write 성능 한계 존재
- 운영급 구성 시 SSD/NVMe 검토 필요

10G storage network:

- Ceph replication traffic 분리 목적
- storage node 간 대역폭 확보 목적
- network 병목 여부 분리 측정 가능

etcd local disk:

- Kubernetes control-plane 안정성 우선
- Ceph 장애와 control-plane quorum 장애 결합 방지
- 실수/착오 후 local 구성으로 정리한 사항

### 3.4 Ceph replica와 backup 차이

Replica:

- 현재 data copy 자동 유지
- 디스크 장애 risk 감소
- 노드 장애 risk 감소
- self-healing 기반 복구
- 같은 시점의 data 복제

Backup:

- 특정 시점 복구
- 삭제/오염/랜섬웨어 대응
- 운영 실수 대응
- 별도 계정/별도 위치 보관
- restore 절차 검증 필요

핵심 설명:

```text
Ceph replica는 백업을 대체하지는 않지만, 백업만 있는 구조보다 운영 중 장애 risk를 줄이는 데 효과가 있습니다.
다만 사용자가 object를 삭제하거나 데이터가 논리적으로 오염되면 replica도 같은 상태가 되므로, AWS S3 백업을 별도로 두었습니다.
```

### 3.5 Ceph 성능 수치 해석

수치 해석 기준:

- iperf3 9Gbps 이상: 10G network 정상
- RBD 4K randwrite 낮음: HDD random write 한계
- cache on/off 차이 큼: cache 포함 수치 과대해석 주의
- 1M seqwrite 낮음: replica/WAL/DB/HDD 영향 가능성
- RADOS 4K write 낮음: backend storage 한계 근거

발표 표현:

```text
10G network는 정상 대역폭을 확인했지만, Ceph write 성능은 HDD 기반 OSD와 replica write path의 영향을 받았습니다.
따라서 현재 구성의 병목은 network보다 disk/write path 쪽으로 해석했고, 운영급 구성에서는 SSD WAL/DB 분리 또는 NVMe OSD를 개선 후보로 봤습니다.
```

피해야 할 표현:

- `10G니까 Ceph도 빠르다`
- `Ceph replica가 backup이다`
- `cache on 1,700 IOPS가 실제 disk 성능이다`
- `HDD로 운영급 random write 충분`

---

## 4. 온프레 DB 설명 근거

### 4.1 PXC 선택 이유

PXC 역할:

- 온프레 운영 DB
- 3-node DB HA
- Galera 동기 복제
- Single Writer 운영 기준
- Kubernetes RBD PVC 사용

효용가치:

- DB node 장애 대응
- 운영 DB local 처리
- cloud burst와 별개인 기준 data 저장소
- ProxySQL과 결합한 endpoint 안정화

한계:

- Galera 동기 복제 write latency 증가 가능성
- split-brain 방지 quorum 중요
- DB backup 별도 필요
- RBD storage 성능 영향 가능성

### 4.2 ProxySQL 선택 이유

역할:

- 앱 DB endpoint 단일화
- writer hostgroup routing
- connection 관리
- PXC 직접 접속 회피

발표 표현:

```text
앱은 PXC node에 직접 붙지 않고 ProxySQL endpoint를 통해 접근합니다.
이를 통해 DB node 변경이나 writer 변경 상황에서 앱 설정을 단순화했습니다.
```

주의:

- ProxySQL 단일 구성 시 SPOF 가능성
- HAProxy/VIP 또는 복수 ProxySQL 개선 후보

### 4.3 온프레 DB 성능 수치 해석

측정값 의미:

- TPS: OLTP 처리량
- avg latency: 평균 응답 시간
- p95 latency: 대부분 사용자 요청 지연 기준
- p99 latency: tail latency
- errors: DB/ProxySQL/lock 문제 여부

발표 기준:

- PXC wsrep 상태 정상 먼저 확인
- sysbench는 별도 test schema 기준
- 운영 schema 직접 부하 금지
- 수치 부진 시 RBD/PXC/Galera/동시성 조건 함께 설명

---

## 5. Backup 설명 근거

### 5.1 백업 분리 원칙

분리 대상:

- DB backup
- Object backup
- Harbor metadata backup
- Harbor image blob replication/archive

이유:

- DB: 트랜잭션 일관성 필요
- Object: 파일/object count와 checksum 기준
- Harbor metadata: project/user/replication 설정 필요
- Image blob: registry layer/manifest 저장 구조 고려

### 5.2 DB backup 설명

근거 항목:

- full backup timestamp
- binlog 활성 여부
- backup file 존재
- restore dry-run 또는 복구 테스트 여부

발표 표현:

```text
DB는 단순 파일 복사가 아니라 트랜잭션 일관성이 중요하기 때문에 XtraBackup과 binlog 기준으로 백업/복구 근거를 확인했습니다.
복구 테스트가 완료되지 않은 경우에는 백업 파일 존재까지만 말하고, restore 검증은 후속 과제로 분리했습니다.
```

### 5.3 Object backup 설명

구조:

- 원본: Ceph RGW bucket
- 백업: AWS S3 bucket
- 방식: copy-only
- 목적: 원본 삭제 전파 방지
- 검증: source/backup object count, size, restore dry-run

발표 표현:

```text
정적 이미지와 영상 object는 Ceph RGW에 저장하고, AWS S3로 copy-only 백업했습니다.
copy-only 방식은 원본 삭제나 실수 삭제가 백업까지 즉시 전파되는 것을 막기 위한 선택입니다.
```

---

## 6. Redis 설명 근거

### 6.1 Redis 선택 이유

프로젝트 상황:

- 티켓팅 순간 트래픽 집중
- 동일 예매 정보 반복 조회
- AWS burst 중 온프레/클라우드 동시 접근
- RDS read replica와 온프레 DB 간 지연 가능성

Redis 역할:

- cache layer
- queue/status store
- 예매 상태 단일 기준점
- DB read 부하 감소
- AWS/온프레 앱의 공통 조회 지점

효용가치:

- cache HIT 시 응답 시간 단축
- DB connection/query 감소
- 순간 read traffic 흡수
- AWS/on-prem 간 예매 상태 일관성 확보

발표 문장 후보:

```text
Redis는 단순히 DB 부하를 줄이는 캐시만이 아니라, AWS와 온프레미스 앱이 동일한 예매 상태를 바라보게 하는 기준점 역할도 맡았습니다.
RDS read replica나 DB 복제 지연으로 몇 초 차이가 날 수 있는 정보는 Redis key를 기준으로 통일했습니다.
```

### 6.2 Sentinel 구성 이유

구성:

- Redis node 3개
- Sentinel quorum 2
- master 장애 시 replica promotion
- RBD PVC 기반 persistent volume

선택 이유:

- 단일 Redis master 장애 risk 완화
- Kubernetes Pod 장애 시 자동 복구 흐름 확보
- 발표 시 failover 시연 가능
- 구조 단순성

한계:

- failover 중 짧은 write 중단 가능성
- client reconnect 처리 필요
- Sentinel 자체도 quorum 유지 필요
- Redis Cluster와 다르게 sharding 목적 아님

### 6.3 Redis 성능 수치 해석

측정 항목:

- GET ops/sec
- SET ops/sec
- avg latency
- keyspace_hits
- keyspace_misses
- cache HIT latency
- cache MISS latency
- DB Questions/Threads_connected 변화

해석:

- GET/SET ops/sec: cache layer 처리 여유
- HIT/MISS latency: 사용자 체감 차이
- hit ratio: cache 활용률
- DB QPS 감소: DB offload 근거
- Sentinel failover time: HA 전환 시간

주의:

- hit ratio만으로 DB 부하 감소 단정 금지
- DB query 감소와 함께 제시
- benchmark 수치와 실제 app latency 구분
- failover는 무중단 0초 보장 아님

---

## 7. 발표 자료 구성 기준

### 7.1 필수 캡처

Ceph:

- `ceph -s`
- `ceph df`
- pool `size/min_size`
- fio/rados/iperf3 결과

DB:

- PXC pod/PVC
- wsrep 상태
- ProxySQL routing
- backup timestamp/binlog

Backup:

- RGW source bucket stats
- AWS S3 backup object count
- restore dry-run 결과

Redis:

- Sentinel `ckquorum`
- failover 전후 master
- Redis benchmark
- Cache HIT/MISS 응답 시간

### 7.2 발표 표 구성

권장 표:

| Layer   | 측정값            | 의미                |
| :------ | :---------------- | :------------------ |
| Storage | RBD 4K randwrite  | HDD write path 한계 |
| Storage | RBD 1M seqwrite   | 대용량 write 기준   |
| Network | NIC raw iperf3    | 10G fabric 정상     |
| Network | Pod-to-Pod iperf3 | CNI overhead 포함   |
| DB      | PXC TPS/p95       | 온프레 DB 처리 기준 |
| Cache   | Redis GET/SET     | cache layer 여유    |
| App     | HIT/MISS latency  | 사용자 체감 개선    |
| Backup  | restore dry-run   | 복구 가능성 근거    |

### 7.3 시연 우선순위

1순위:

- Redis Sentinel failover
- Cache HIT/MISS latency 비교
- Ceph 성능 수치표

2순위:

- Object backup restore dry-run
- PXC wsrep 상태
- ProxySQL routing

보류 후보:

- 운영 PVC live fio
- 운영 DB live destructive test
- Pod 삭제 기반 Redis 장애 주입

---

## 8. 예상 질문 답변

| 질문                          | 답변 기준                                                                        |
| :---------------------------- | :------------------------------------------------------------------------------- |
| 왜 Ceph 사용?                 | RBD/RGW를 한 cluster에서 제공, 온프레 storage 통합, object 대용량 자료 저장 목적 |
| Ceph replica면 backup 불필요? | 장애 risk 감소에는 도움, 삭제/오염/실수 복구는 backup 필요                       |
| 10G인데 왜 write가 낮음?      | network는 정상, HDD random write와 replica/WAL path 영향                         |
| HDD로 운영 가능?              | 대용량 object 중심은 가능, DB/random write 운영급은 SSD WAL/DB 또는 NVMe 검토    |
| RBD와 RGW 차이?               | RBD는 block volume, RGW는 S3 호환 object storage                                 |
| Harbor image blob 표현 이유?  | registry는 layer/manifest blob 저장 구조                                         |
| 왜 Redis 사용?                | DB 부하 감소, 예매 상태 단일 기준점, burst 시 AWS/온프레 일관성                  |
| Redis가 DB 대체?              | 아님, 임시 상태/cache/queue 계층, 원장 data는 DB                                 |
| Sentinel이면 무중단?          | 짧은 전환 시간 존재, client reconnect 필요                                       |
| PXC에서 AWS DB 제외 이유?     | 발표 담당 범위가 온프레 DB, AWS RDS/OLAP는 다른 담당 범위                        |
| ProxySQL 단일이면 문제?       | SPOF 가능, 복수 ProxySQL/VIP 개선 후보                                           |
| backup 검증 기준?             | backup 파일 존재보다 restore dry-run/복구 테스트 여부 중요                       |

---

## 9. 말하면 안 되는 표현

금지 표현:

- `Ceph replica가 백업`
- `10G라서 Ceph 성능 충분`
- `Redis가 DB 대체`
- `Sentinel이면 장애 영향 없음`
- `cache HIT IOPS가 실제 disk 성능`
- `AWS RDS/OLAP까지 내 담당`
- `백업 파일 있으니 복구 가능`

대체 표현:

- `Ceph replica는 장애 risk 감소, backup은 특정 시점 복구`
- `10G network는 정상, write 성능은 HDD path 영향`
- `Redis는 cache/queue/상태 기준점`
- `Sentinel은 failover 시간 존재`
- `cache 포함 수치와 disk 직접 수치 구분`
- `온프레 DB 범위 중심`
- `복구 가능성은 restore dry-run으로 확인`

---

## 10. 최종 발표 결론

결론 문장:

```text
이번 구성은 온프레 기반 Kubernetes와 Proxmox 위에서 Ceph를 중심 storage로 두고, RBD와 RGW를 나눠 block/object workload를 처리하도록 설계했습니다.
DB는 PXC와 ProxySQL로 온프레 운영 경로를 구성했고, Redis는 티켓팅 상황에서 DB 부하를 줄이면서 AWS와 온프레가 같은 예매 상태를 바라보게 하는 기준점으로 사용했습니다.
백업은 Ceph replica와 분리해 DB와 object를 별도 정책으로 관리했고, 성능 검증에서는 10G network는 정상이나 HDD 기반 Ceph write path가 주요 한계라는 점을 확인했습니다.
```
