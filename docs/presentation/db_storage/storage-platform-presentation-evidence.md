# Storage Platform 발표용 검증값/성능지표

> 목적: Ceph, 온프레 DB, Backup, Redis 발표에 바로 사용할 검증값과 성능 측정값 정리 기준: 발표용
> 요약 자료, endpoint/IP/pool/user/secret 세부값 제외 원칙: 수치 발표 전 최신 재측정값 우선

---

## 1. 발표용 원칙

- 발표 포함: 구조가 실제로 동작한다는 근거
- 발표 포함: 성능 병목 해석에 필요한 수치
- 발표 포함: 장애 대응 또는 한계 설명에 필요한 상태값
- 발표 제외: endpoint URL
- 발표 제외: bucket 이름
- 발표 제외: pool 이름
- 발표 제외: 내부 IP
- 발표 제외: 계정명, secret, password
- 발표 제외: 긴 명령 옵션

발표 문장 기준:

- "어디에 연결됐는가"보다 "어떤 계층이 어떤 역할을 검증했는가" 중심
- "수치가 있다"보다 "수치가 어떤 병목을 의미하는가" 중심
- "모든 것이 완료"보다 "완료된 근거와 남은 리스크" 분리

---

## 2. 한 장 요약

| 영역          | 발표용 핵심 근거                      | 발표 메시지                            | 상태                   |
| :------------ | :------------------------------------ | :------------------------------------- | :--------------------- |
| Ceph          | 6 OSD, 10G, RBD/RGW, replica 구조     | 저장소 통합과 자동 복제 구조           | 최신 캡처 필요         |
| Ceph 성능     | 10G 9.4 Gbps, RBD seqwrite 35 MB/s    | 네트워크보다 HDD write path 병목       | 재측정 필요            |
| RGW           | RGW 단일 daemon 기록                  | 데이터 복제와 endpoint HA는 별도       | 리스크로 제시          |
| On-prem DB    | ProxySQL -> PXC 3 nodes, Galera sync  | 운영 DB 경로와 동기 복제 구조          | 최신 캡처 필요         |
| DB Backup     | PXC backup/binlog 정책                | Object backup과 DB backup 분리         | 실행 로그 확인 필요    |
| Object Backup | RGW -> AWS S3 copy-only               | 삭제/오염 복구용 2차 백업              | object count 확인 필요 |
| Redis         | Sentinel 3 nodes, quorum 2, failover  | 단일 Redis 장애 대응 구조              | 최신 캡처 필요         |
| Redis 효과    | keyspace hit 증가, queue command 증가 | DB 직접 접근량 감소와 대기열 상태 관리 | 수치 재확인 필요       |

---

## 3. Ceph 발표용 검증값

### 3.1 구성 근거

| 항목         | 발표용 값                 | 해석                               | 캡처 우선순위 |
| :----------- | :------------------------ | :--------------------------------- | :------------ |
| Ceph 노드    | 6 nodes                   | 분산 저장소 구성                   | 높음          |
| OSD          | 6 OSD                     | 디스크 단위 저장 daemon            | 높음          |
| Raw 용량     | 6 TB                      | 물리 디스크 전체 용량              | 높음          |
| 가용 용량    | 2 TB                      | 3-replica 기준 실사용 용량         | 높음          |
| 디스크       | HDD 기반                  | write latency 한계 요인            | 높음          |
| OSD backend  | BlueStore                 | Ceph 최신 OSD backend              | 낮음          |
| Network      | 10GbE fabric              | 스토리지 복제/읽기 경로 확보       | 높음          |
| Network 분리 | Public / Cluster network  | client traffic과 복제 traffic 분리 | 중간          |
| RBD          | K8s PVC, Proxmox VM disk  | block storage 역할                 | 높음          |
| RGW          | Harbor/App object backend | S3 호환 object storage 역할        | 높음          |

발표 메시지:

- Ceph는 단순 디스크 묶음이 아니라 block과 object를 함께 제공하는 온프레 저장소 계층
- RBD는 PVC/VM disk, RGW는 Harbor image blob과 앱 object 저장 담당
- 6TB Raw는 3-replica 기준 약 2TB usable로 설명
- HDD 기반이므로 고 IOPS workload는 성능 검증과 별도 설계 필요

### 3.1.1 RBD/RGW 활용 근거

| 인터페이스 | 발표용 사용처                                    | 발표 메시지                        |
| :--------- | :----------------------------------------------- | :--------------------------------- |
| RBD        | PXC, Redis, Jenkins, Harbor metadata, Prometheus | Stateful workload의 block volume   |
| RGW        | Harbor image blob, 앱 object                     | S3 호환 object storage             |
| CephFS     | 현재 핵심 발표 제외                              | RWX 요구 없으면 사용 우선순위 낮음 |

발표 메시지:

- 같은 Ceph cluster에서 block과 object를 동시에 제공
- PXC/Redis 같은 StatefulSet은 RBD PVC 사용
- Harbor image blob은 RGW S3 backend 사용
- Harbor metadata는 RBD PVC 영역으로 분리 가능

### 3.2 복제/가용성 근거

| 항목         | 발표용 값              | 해석                               | 상태        |
| :----------- | :--------------------- | :--------------------------------- | :---------- |
| Pool replica | size 3 확인 필요       | 데이터 3중 복제 근거               | 재확인 필요 |
| PG 상태      | active+clean 확인 필요 | 정상 복제/배치 상태                | 재확인 필요 |
| OSD 상태     | up/in 확인 필요        | 장애 없는 저장 daemon 상태         | 재확인 필요 |
| Self-healing | degraded 0 확인 필요   | 장애 후 정상 복구 상태             | 재확인 필요 |
| RGW endpoint | 단일 daemon 기록       | 데이터 복제와 API endpoint HA 분리 | 리스크      |

발표 메시지:

- Ceph replica는 디스크/노드 장애 대응
- Ceph replica는 백업 대체 아님
- RGW 데이터는 Ceph pool replica 대상
- RGW API endpoint는 daemon 다중화와 LB가 별도 필요

### 3.3 성능 측정값

| 항목                       | 기존 참고값  | 발표 해석                           | 발표 상태   |
| :------------------------- | :----------- | :---------------------------------- | :---------- |
| 10G network                | 9.4 Gbps     | 네트워크 자체는 주요 병목 아님      | 재측정 필요 |
| RBD 4K randwrite cache on  | 1,700 IOPS   | cache 포함 수치, 과장 금지          | 재측정 필요 |
| RBD 4K randwrite cache off | 100~200 IOPS | HDD 기반 write 한계에 가까운 참고값 | 재측정 필요 |
| RBD 1M seqwrite            | 35 MB/s      | sequential write도 HDD path 병목    | 재측정 필요 |
| RADOS 4K write             | 99 IOPS      | RADOS 계층 4K write 기준 참고값     | 재측정 필요 |
| Pod-to-Pod network         | 5.34 Gbps    | Calico/IPIP 경로도 1G 이상          | 참고        |

발표 메시지:

- 10G network는 충분한 편
- 실제 병목은 HDD OSD와 3-replica write path
- "10G라서 Ceph가 빠름" 표현 금지
- "네트워크는 확보했지만 write 성능은 HDD 특성상 제한" 표현 권장

### 3.3.1 병목 계층 해석

| 계층              | 이론/참고 한계 | 발표 해석           |
| :---------------- | :------------- | :------------------ |
| 10G NIC           | 약 1,250 MB/s  | 네트워크 상한       |
| 6 HDD 합산        | 약 600 MB/s    | 디스크 원시 처리량  |
| 3-replica 적용    | 약 200 MB/s    | 복제 비용 반영      |
| WAL/DB 같은 HDD   | 약 70~100 MB/s | seek thrashing 가능 |
| 실제 RBD seqwrite | 35 MB/s        | HDD write path 병목 |

개선 메시지:

- 개선 1순위: SSD WAL/DB 분리
- 기대 효과: seq write 4~8배, randwrite 5~15배 후보
- 단, 개선 효과는 실제 재측정 후 확정

표현 주의:

- `RADOS 4K randwrite` 표현은 원 측정 방식 확인 전 사용 지양
- `rados bench write -b 4K` 결과면 `RADOS 4K write`로 표현
- random write는 `fio RBD randwrite`와 구분

---

## 4. On-prem DB 발표용 검증값

### 4.1 담당 범위

| 항목      | 발표 포함 여부 | 이유                         |
| :-------- | :------------- | :--------------------------- |
| PXC       | 포함           | 온프레 운영 DB               |
| ProxySQL  | 포함           | 앱 DB 접속 endpoint          |
| Galera    | 포함           | PXC 동기 복제 근거           |
| RBD PVC   | 포함           | StatefulSet 영속 저장소      |
| RDS       | 제외           | AWS DB 담당 외 영역          |
| OLAP      | 제외           | 데이터 워크로드 담당 외 영역 |
| admin-app | 제외           | 분석 워크로드 담당 외 영역   |

### 4.2 검증 근거

| 항목             | 발표용 값/상태              | 발표 메시지                    | 캡처 우선순위 |
| :--------------- | :-------------------------- | :----------------------------- | :------------ |
| App DB 경로      | App -> ProxySQL -> PXC      | 앱은 PXC 직접 연결 지양        | 높음          |
| PXC 형태         | StatefulSet 3 replica       | 안정적 Pod ID와 PVC 유지       | 높음          |
| PXC 복제         | Galera sync replication     | write 동기 복제와 일관성       | 높음          |
| PXC PVC          | RBD RWO PVC                 | 각 DB pod의 영속 block volume  | 높음          |
| PXC cluster 상태 | Primary 확인 필요           | 운영 DB cluster 정상           | 높음          |
| PXC node 수      | 설계값과 일치 확인 필요     | DB HA 구성 근거                | 중간          |
| ProxySQL routing | PXC hostgroup 확인 필요     | writer/read 경로 통제          | 높음          |
| DB connection    | Threads_connected 측정 필요 | Redis 효과 비교 기준           | 높음          |
| DB backup        | XtraBackup/binlog 확인 필요 | Object backup과 DB backup 분리 | 높음          |

발표 메시지:

- 온프레 DB는 PXC가 운영 데이터 기준
- 앱은 ProxySQL endpoint 경유
- ProxySQL은 DB 접속 경로와 connection pressure 통제 계층
- PXC는 3 nodes + Galera 동기 복제 + RBD PVC 구조
- 1 node 장애 시 quorum 유지 가능성 설명
- DB 백업은 Ceph replica나 Object backup과 별도

발표 제외:

- DB 계정명
- DB endpoint
- hostgroup 번호
- RDS route
- OLAP query 성능

---

## 5. Backup 발표용 검증값

### 5.1 Object Backup

| 항목              | 발표용 값/상태           | 발표 메시지               | 캡처 우선순위 |
| :---------------- | :----------------------- | :------------------------ | :------------ |
| 원본              | Ceph RGW object          | 운영 object 원본          | 높음          |
| 백업 대상         | AWS S3                   | 2차 백업 저장소           | 높음          |
| 방식              | copy-only                | 원본 삭제 전파 방지       | 높음          |
| key 구조          | 동일 key 유지            | 복구 시 앱/DB 변경 최소화 | 중간          |
| object count      | 원본/백업 비교 필요      | 백업 누락 여부 확인       | 높음          |
| restore dry-run   | 실행 결과 필요           | 복구 가능성 증거          | 높음          |
| Lifecycle         | 장기 보관 정책 확인 필요 | 비용 절감과 archive 구분  | 중간          |
| backup throughput | 측정 필요                | 백업 소요 시간 설명       | 낮음          |

발표 메시지:

- Ceph replica는 운영 장애 대응
- AWS S3 backup은 삭제/오염/운영 실수 복구 대응
- copy-only는 초기 운영 안정성 우선 정책
- Lifecycle은 장기 보관 비용 절감 목적

### 5.2 DB Backup

| 항목         | 발표용 값/상태                | 발표 메시지                       | 캡처 우선순위 |
| :----------- | :---------------------------- | :-------------------------------- | :------------ |
| Full backup  | XtraBackup 확인 필요          | 트랜잭션 일관성 있는 DB 백업 후보 | 높음          |
| binlog       | 보관 여부 확인 필요           | 특정 시점 복구 근거               | 높음          |
| backup file  | 생성 시각 확인 필요           | 백업 자동화 실행 근거             | 높음          |
| restore test | dry-run 또는 테스트 복구 필요 | 백업이 복구 가능함을 증명         | 높음          |
| 저장 위치    | 안전 저장소 확인 필요         | 운영 DB와 백업 분리               | 중간          |

발표 메시지:

- Object backup과 DB backup은 목적과 도구가 다름
- DB backup은 트랜잭션 일관성과 복구 시점 기준 필요
- 발표 전 실행 로그 또는 백업 파일 캡처 필요

---

## 6. Redis 발표용 검증값

### 6.1 구성/HA 근거

| 항목            | 발표용 값                        | 발표 메시지                    | 상태        |
| :-------------- | :------------------------------- | :----------------------------- | :---------- |
| Redis 구성      | Sentinel 3 nodes                 | 최소 HA 구성                   | 재확인 필요 |
| Sentinel quorum | quorum 2                         | 1대 장애 시 failover 판단 가능 | 재확인 필요 |
| Quorum 확인     | OK 3 usable Sentinels            | Sentinel 정상 동작 근거        | 재확인 필요 |
| Master 확인     | master 주소 조회 성공            | 현재 write 대상 확인           | 재확인 필요 |
| Failover        | master 장애 후 약 30초 이내 전환 | 장애 대응 근거                 | 재검증 필요 |
| PVC             | RBD RWO PVC                      | Redis 노드별 영속 저장소       | 재확인 필요 |

발표 메시지:

- Redis는 단일 cache가 아니라 Sentinel 기반 HA 구성
- 2 nodes + quorum 2는 장애에 취약
- 3 nodes + quorum 2가 최소 HA 기준

### 6.2 기능 검증 근거

| 항목              | 발표용 값/상태     | 발표 메시지                    | 상태           |
| :---------------- | :----------------- | :----------------------------- | :------------- |
| Queue endpoint    | 동작 확인 이력     | 대기열 상태 Redis 저장         | 재확인 필요    |
| FIFO command      | LPUSH/RPOP/LLEN    | queue 자료구조 동작            | 재확인 필요    |
| Keyspace          | db0 keys 확인      | 실제 Redis key 생성            | 재확인 필요    |
| Commands 증가     | 2.8K -> 31K 참고값 | 부하 테스트 중 Redis 사용 증가 | 재확인 필요    |
| Cache HIT latency | 6.6ms 참고값       | 캐시 응답 지연 감소 근거       | 측정 맥락 확인 |
| keyspace hit      | 증가 확인 필요     | cache hit 근거                 | 재확인 필요    |
| latency           | 측정 필요          | Redis 자체 병목 여부           | 중간           |

발표 메시지:

- Redis는 DB 대체가 아니라 DB 앞단 cache/queue 계층
- 반복 조회와 대기열 상태를 Redis가 흡수
- DB commit 이후 Redis 갱신/삭제, TTL 적용 필요

### 6.3 DB 부하 감소 근거

| 항목            | Redis 없음 | Redis 있음 | 발표 메시지              | 상태        |
| :-------------- | :--------- | :--------- | :----------------------- | :---------- |
| App p95 latency | 측정 필요  | 측정 필요  | 응답 지연 감소 여부      | 재측정 필요 |
| DB QPS          | 측정 필요  | 측정 필요  | DB query 감소 여부       | 재측정 필요 |
| DB connection   | 측정 필요  | 측정 필요  | connection pressure 완화 | 재측정 필요 |
| Redis hit ratio | 해당 없음  | 측정 필요  | cache 효율               | 재측정 필요 |
| Redis latency   | 해당 없음  | 측정 필요  | cache 자체 병목 여부     | 재측정 필요 |

발표 메시지:

- Redis 성능 주장은 DB QPS 또는 connection 감소와 함께 제시
- hit ratio만으로 DB 부하 감소 단정 금지
- k6, ProxySQL/PXC metrics, Redis INFO stats를 함께 사용

---

## 7. 발표 슬라이드별 사용 위치

| 슬라이드 주제  | 사용할 근거                        | 말할 메시지                         |
| :------------- | :--------------------------------- | :---------------------------------- |
| Ceph 구성      | 6 OSD, HDD, 10G, RBD/RGW           | 온프레 저장소 계층 구축             |
| Ceph 성능      | 9.4 Gbps, 35 MB/s, 99 IOPS         | 네트워크보다 HDD write path 병목    |
| Ceph 용량      | 6TB Raw -> 2TB usable              | 3-replica 비용과 가용성 trade-off   |
| Ceph 복제/백업 | replica size, active+clean, AWS S3 | 복제와 백업 목적 분리               |
| RGW 리스크     | single daemon                      | 데이터 복제와 endpoint HA 구분      |
| On-prem DB     | ProxySQL -> PXC, Galera, RBD PVC   | 운영 DB 경로와 동기 복제 구조       |
| DB Backup      | XtraBackup/binlog/restore evidence | 트랜잭션 일관성 있는 별도 백업 필요 |
| Redis HA       | Sentinel 3 nodes, quorum 2         | Redis 단일 장애 대응                |
| Redis 효과     | keyspace hit, commands, DB QPS     | DB 부하 감소와 queue 상태 관리      |

---

## 8. 발표에서 빼야 할 세부사항

- 내부 IP 주소
- endpoint URL
- exact bucket name
- exact pool name
- DB user
- Redis password
- AWS account id
- Harbor project명
- Kubernetes namespace 세부값
- 긴 명령 전체 옵션
- 운영 credential 위치

예외:

- 면접관/전문가가 구체적으로 질문한 경우
- 검증 캡처에서 민감 정보 마스킹 완료한 경우
- pool 이름이 성능 측정 대상 구분에 꼭 필요한 경우

---

## 9. 최종 발표용 수치 표

| 영역       | 지표                       | 발표값       | 최신 재측정값 | 발표 여부 | 비고                    |
| :--------- | :------------------------- | :----------- | :------------ | :-------- | :---------------------- |
| Ceph       | 10G network                | 9.4 Gbps     |               | 조건부    | 재측정값 우선           |
| Ceph       | Raw capacity               | 6 TB         |               | 가능      | 6 OSD 기준              |
| Ceph       | Usable capacity            | 2 TB         |               | 가능      | 3-replica 기준          |
| Ceph       | Pod-to-Pod network         | 5.34 Gbps    |               | 참고      | Calico/IPIP 경로        |
| Ceph       | RBD 4K randwrite cache on  | 1,700 IOPS   |               | 조건부    | cache 포함 명시         |
| Ceph       | RBD 4K randwrite cache off | 100~200 IOPS |               | 조건부    | HDD 한계 설명           |
| Ceph       | RBD 1M seqwrite            | 35 MB/s      |               | 조건부    | write path 병목         |
| Ceph       | RADOS 4K write             | 99 IOPS      |               | 조건부    | randwrite 표현 주의     |
| On-prem DB | PXC node count             | 3            |               | 조건부    | StatefulSet/Galera 확인 |
| Redis      | Sentinel quorum            | quorum 2     |               | 가능      | 3 nodes 전제            |
| Redis      | usable Sentinels           | 3            |               | 조건부    | 최신 `ckquorum` 필요    |
| Redis      | failover target            | 약 30초      |               | 조건부    | 장애 시험 후 발표       |
| Redis      | total commands             | 2.8K -> 31K  |               | 조건부    | 부하 테스트 맥락 필요   |
| Redis      | cache HIT latency          | 6.6ms        |               | 조건부    | 측정 위치 확인 필요     |
| Redis      | hit ratio                  | 측정 필요    |               | 측정 후   | DB 부하 감소 근거       |
| On-prem DB | DB connection              | 측정 필요    |               | 측정 후   | Redis 효과 비교         |
| Backup     | object count match         | 측정 필요    |               | 측정 후   | backup completeness     |
| Backup     | restore dry-run            | 실행 필요    |               | 실행 후   | 복구 가능성 근거        |

---

## 10. 발표용 결론 문장

- "Ceph는 RBD와 RGW로 block/object 저장소를 분리해 온프레 저장소 계층을 구성함."
- "6TB Raw 저장소를 3-replica로 운영하면 가용 용량은 약 2TB이며, 이는 용량보다 가용성을 우선한
  선택임."
- "성능 수치상 10G network는 충분하지만 HDD 기반 Ceph write path가 병목으로 확인됨."
- "Ceph replica는 장애 대응이고, AWS S3 backup은 삭제/오염 복구 대응임."
- "온프레 DB는 ProxySQL을 통해 PXC로 접근하고, PXC는 3 nodes Galera 동기 복제로 운영 데이터 일관성을
  유지함."
- "Redis Sentinel 3노드 구성으로 cache/queue 계층의 단일 장애 리스크를 줄임."
- "Redis 효과는 hit ratio, DB QPS, DB connection 감소로 증명해야 함."
