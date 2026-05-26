# Storage Platform 발표 증거 검증 가이드

> 대상: Ceph(분산 스토리지), 온프레 DB(Database), Backup(백업), Redis(인메모리 데이터 저장소) 목적:
> 발표에 사용할 캡처/영상/측정값 확보 연계: `storage-platform-evidence-explainer.md`의 동일 Evidence
> ID 기준 설명

---

## 1. 사용 원칙

핵심 원칙:

- 발표 메시지와 직접 연결되는 검증만 포함
- 모든 기록값은 명령어와 1:1 연결
- 캡처 후 값 출처 표시
- endpoint, IP, 계정, bucket, pool, secret 마스킹
- 수치 단독 제시 금지
- 수치 + 의미 + 한계 세트 구성
- 운영 PVC/운영 DB 직접 부하 금지
- 영상은 짧은 동작 증명용
- 캡처는 발표 슬라이드 근거용

산출물 단위:

| 항목        | 내용                     |
| :---------- | :----------------------- |
| Evidence ID | 발표 증거 식별자         |
| 발표 메시지 | 슬라이드에서 말할 결론   |
| 확보 자료   | 캡처/영상/측정값         |
| 검증 방법   | 실행 명령 또는 확인 절차 |
| 사용 기준   | 발표 포함/보류 기준      |
| 설명 위치   | explainer 문서의 동일 ID |

값 기록 규칙:

| 규칙      | 내용                                         |
| :-------- | :------------------------------------------- |
| 값 출처   | `명령어`, `출력 항목`, `라인/필드` 기록      |
| 캡처 범위 | 값이 보이는 화면만 캡처                      |
| 표 작성   | `측정값`, `측정 조건`, `발표 의미` 동시 기록 |
| 보류 기준 | 값 출처 설명 불가 시 발표 제외               |

파일명 규칙:

```text
YYYY-MM-DD_E<ID>_<area>_<metric>.png
YYYY-MM-DD_E<ID>_<area>_<demo>.mp4
YYYY-MM-DD_E<ID>_<area>_<metric>.txt
```

예시:

```text
2026-05-25_E3_ceph_iperf3_10g.png
2026-05-25_E3_ceph_rbd_fio.txt
2026-05-25_E8_redis_sentinel_failover.mp4
```

---

## 2. 발표 증거 목록

### 2.1 본문 발표용 증거

| ID  | 발표 메시지                                             | 확보 자료                                    | 발표 형태 | 설명 문서 |
| :-- | :------------------------------------------------------ | :------------------------------------------- | :-------- | :-------- |
| E1  | Ceph는 replica 기반으로 장애 risk를 줄이는 storage 기반 | `ceph -s`, `ceph df`, pool replica 캡처      | 캡처      | E1        |
| E2  | RBD/RGW를 나눠 block/object storage를 제공              | PVC/StorageClass, RGW bucket stats 캡처      | 캡처      | E2        |
| E3  | 10G network는 정상, write 병목은 HDD 기반 Ceph path     | iperf3, fio/RADOS 결과                       | 수치 표   | E3        |
| E4  | 온프레 DB는 ProxySQL 경유 PXC 3-node 구조               | ProxySQL route, PXC wsrep 캡처               | 캡처      | E4        |
| E5  | DB backup은 replica와 별도인 특정 시점 복구 수단        | backup timestamp, binlog, restore 결과       | 캡처      | E5        |
| E6  | Object backup은 Ceph RGW에서 AWS S3로 copy-only 구성    | source/backup count, restore dry-run         | 캡처      | E6        |
| E7  | Redis는 DB 부하 감소와 예매 상태 단일 기준점            | HIT/MISS latency, Redis stats, DB query 변화 | 수치 표   | E7        |
| E8  | Redis Sentinel은 master 장애 시 failover 근거 제공      | failover 전후 master, 짧은 영상              | 영상/캡처 | E8        |

### 2.2 Q&A 대비용 보조 증거

| ID  | 사용 상황              | 확보 자료                       | 본문 포함 기준                  |
| :-- | :--------------------- | :------------------------------ | :------------------------------ |
| Q1  | DB 성능 질문           | PXC sysbench TPS/p95            | 실제 측정값과 조건 설명 가능 시 |
| Q2  | RGW endpoint HA 질문   | RGW daemon 수, LB/VIP 존재 여부 | 단일 endpoint risk 설명 필요 시 |
| Q3  | Redis 자체 처리량 질문 | redis-benchmark GET/SET ops/sec | app HIT/MISS 수치 보조로만      |

### 2.3 제외 또는 후순위 증거

| 항목                         | 제외 이유                                  |
| :--------------------------- | :----------------------------------------- |
| Pod-to-Pod network 단독 수치 | Ceph/DB/Redis 발표 메시지와 직접 연결 약함 |
| Redis commandstats 세부 명령 | 발표에서 의미 부여 어려움                  |
| 모든 PVC 전체 목록           | 너무 넓은 운영 세부 정보                   |
| endpoint/IP/name 상세        | 발표 청중에게 불필요, 보안 노출 risk       |
| benchmark 원본 전체 로그     | 슬라이드 가독성 낮음                       |

---

## 3. E1 Ceph 기본 상태와 Replica

발표 메시지:

- Ceph cluster 정상 상태
- 3-replica 기반 장애 risk 감소
- replica는 backup 대체 아님

확보 자료:

- `E1_ceph_status.png`
- `E1_ceph_capacity.png`
- `E1_ceph_replica.png`

검증 명령:

```bash
ceph -s
ceph health detail
ceph osd tree
ceph df
ceph osd pool ls detail
ceph osd pool get <RBD_POOL> size
ceph osd pool get <RBD_POOL> min_size
ceph osd pool get <RGW_DATA_POOL> size
ceph osd pool get <RGW_DATA_POOL> min_size
```

명령-값 매핑:

| 실행 명령                                    | 출력에서 확인할 위치                    | 기록할 값                     | 발표 사용                      |
| :------------------------------------------- | :-------------------------------------- | :---------------------------- | :----------------------------- |
| `ceph -s`                                    | `health:`                               | `HEALTH_OK` 또는 warning 사유 | cluster 정상성                 |
| `ceph -s`                                    | `osd:`                                  | `N osds: N up, N in`          | OSD 참여 상태                  |
| `ceph -s`                                    | `pgs:`                                  | `active+clean` 비율/개수      | 성능 측정 가능 상태            |
| `ceph health detail`                         | warning/detail line                     | warning 원인                  | warning 설명 가능 여부         |
| `ceph osd tree`                              | `CLASS`, `WEIGHT`, `STATUS`, `REWEIGHT` | OSD 수, host 분산, `up` 상태  | 노드/디스크 분산 근거          |
| `ceph df`                                    | `RAW STORAGE`의 `SIZE`                  | raw capacity                  | 전체 물리 용량                 |
| `ceph df`                                    | `POOLS`의 `MAX AVAIL`                   | usable capacity               | replica 반영 후 사용 가능 용량 |
| `ceph osd pool get <RBD_POOL> size`          | `size:`                                 | RBD replica size              | RBD data 복제 수               |
| `ceph osd pool get <RBD_POOL> min_size`      | `min_size:`                             | RBD min_size                  | 장애 시 I/O 허용 기준          |
| `ceph osd pool get <RGW_DATA_POOL> size`     | `size:`                                 | RGW replica size              | object data 복제 수            |
| `ceph osd pool get <RGW_DATA_POOL> min_size` | `min_size:`                             | RGW min_size                  | object I/O 허용 기준           |

기록 예시:

| 발표 항목        | 값  | 출처                                     |
| :--------------- | :-- | :--------------------------------------- |
| Ceph health      |     | `ceph -s health`                         |
| OSD 상태         |     | `ceph -s osd`, `ceph osd tree`           |
| raw capacity     |     | `ceph df RAW STORAGE SIZE`               |
| usable capacity  |     | `ceph df POOLS MAX AVAIL`                |
| RBD replica size |     | `ceph osd pool get <RBD_POOL> size`      |
| RGW replica size |     | `ceph osd pool get <RGW_DATA_POOL> size` |

발표 포함 기준:

- `HEALTH_OK`
- PG `active+clean`
- replica size 설명 가능
- usable capacity와 raw capacity 차이 설명 가능

발표 보류 기준:

- `HEALTH_ERR`
- PG not clean
- replica size 확인 실패
- health warning 원인 설명 불가

---

## 4. E2 RBD/RGW 사용처

발표 메시지:

- RBD: VM/Kubernetes block volume
- RGW: Harbor image blob, 앱 object 저장
- 같은 Ceph cluster에서 block/object 역할 분리

확보 자료:

- `E2_rbd_storageclass_pvc.png`
- `E2_rgw_bucket_stats.png`

검증 명령:

```bash
kubectl get sc
kubectl get pvc -A
kubectl get pv
rbd ls -p <RBD_POOL>
radosgw-admin bucket list
radosgw-admin bucket stats --bucket <HARBOR_OR_APP_BUCKET>
```

명령-값 매핑:

| 실행 명령                                                    | 출력에서 확인할 위치                                                | 기록할 값                                   | 발표 사용                              |
| :----------------------------------------------------------- | :------------------------------------------------------------------ | :------------------------------------------ | :------------------------------------- |
| `kubectl get sc`                                             | `PROVISIONER`                                                       | `rbd.csi.ceph.com` 또는 RBD CSI provisioner | Kubernetes RBD 사용 근거               |
| `kubectl get sc`                                             | StorageClass name                                                   | RBD StorageClass 이름                       | PVC와 RBD 연결 기준                    |
| `kubectl get pvc -A`                                         | `NAMESPACE`, `NAME`, `STATUS`, `VOLUME`, `CAPACITY`, `STORAGECLASS` | PXC/Redis/Harbor 등 PVC와 StorageClass      | Stateful workload 저장소 근거          |
| `kubectl get pv`                                             | `CSI` 또는 `STORAGECLASS`                                           | RBD CSI 기반 PV 여부                        | PVC가 Ceph RBD로 provision된 근거      |
| `rbd ls -p <RBD_POOL>`                                       | image 목록                                                          | PVC/PV와 연결된 RBD image 존재              | Ceph 내부 block image 근거             |
| `radosgw-admin bucket list`                                  | bucket name 목록                                                    | Harbor/App bucket 존재                      | RGW 사용처 후보 확인                   |
| `radosgw-admin bucket stats --bucket <HARBOR_OR_APP_BUCKET>` | `bucket`                                                            | bucket 이름                                 | 캡처 대상 bucket                       |
| `radosgw-admin bucket stats --bucket <HARBOR_OR_APP_BUCKET>` | `usage.rgw.main.num_objects`                                        | object count                                | Harbor image blob/App object 저장 근거 |
| `radosgw-admin bucket stats --bucket <HARBOR_OR_APP_BUCKET>` | `usage.rgw.main.size_kb_actual`                                     | actual size                                 | object 저장량 근거                     |

기록 예시:

| 발표 항목           | 값  | 출처                                |
| :------------------ | :-- | :---------------------------------- |
| RBD StorageClass    |     | `kubectl get sc PROVISIONER`        |
| RBD 사용처          |     | `kubectl get pvc -A STORAGECLASS`   |
| RBD image 존재      |     | `rbd ls -p <RBD_POOL>`              |
| RGW bucket          |     | `radosgw-admin bucket stats bucket` |
| bucket object count |     | `usage.rgw.main.num_objects`        |
| bucket size         |     | `usage.rgw.main.size_kb_actual`     |

발표 포함 기준:

- RBD PVC 사용처 2개 이상 확인
- RGW bucket stats 확인
- Harbor image blob 표현 유지

발표 보류 기준:

- bucket 용도 불명
- PVC 이름만 있고 workload 연결 설명 불가
- Harbor image와 image blob 표현 혼동

---

## 5. E3 Ceph 10G와 HDD Write 병목

발표 메시지:

- 10G 전송망은 정상 대역폭
- Ceph write 성능은 HDD와 replica write path 영향
- 운영급 구성은 SSD WAL/DB 또는 NVMe OSD 개선 후보

확보 자료:

- `E3_ceph_iperf3_10g.png`
- `E3_ceph_rados_4k.txt`
- `E3_ceph_rbd_fio_cache_on.txt`
- `E3_ceph_rbd_fio_cache_off.txt`
- `E3_ceph_rbd_fio_seqwrite.txt`
- `E3_ceph_performance_table.png`

사전 조건:

- E1 통과
- 테스트 전용 pool/image/PVC 사용
- 운영 PVC 직접 측정 금지
- 측정 시간/조건 기록

10G network:

```bash
ethtool <STORAGE_NIC>

# server
iperf3 -s -B <STORAGE_NODE_IP>

# client
iperf3 -c <STORAGE_NODE_IP> -P 4 -t 30
```

RADOS 4K write:

```bash
rados bench -p <TEST_POOL> 60 write -b 4K -t 16 --no-cleanup
rados cleanup -p <TEST_POOL>
```

RBD fio cache on:

```bash
rbd create -p <RBD_POOL> perf-rbd-test --size 4096

fio --name=rbd-4k-randwrite-cache-on \
  --ioengine=rbd \
  --clientname=admin \
  --pool=<RBD_POOL> \
  --rbdname=perf-rbd-test \
  --rw=randwrite \
  --bs=4k \
  --iodepth=32 \
  --numjobs=4 \
  --runtime=60 \
  --time_based \
  --group_reporting
```

RBD fio cache off:

```bash
cp /etc/ceph/ceph.conf /tmp/ceph-cache-off.conf
printf '\n[client]\nrbd cache = false\n' >> /tmp/ceph-cache-off.conf

fio --name=rbd-4k-randwrite-cache-off \
  --ioengine=rbd \
  --clientname=admin \
  --pool=<RBD_POOL> \
  --rbdname=perf-rbd-test \
  --conf=/tmp/ceph-cache-off.conf \
  --rw=randwrite \
  --bs=4k \
  --iodepth=32 \
  --numjobs=4 \
  --runtime=60 \
  --time_based \
  --group_reporting
```

RBD 1M seqwrite:

```bash
fio --name=rbd-1m-seqwrite \
  --ioengine=rbd \
  --clientname=admin \
  --pool=<RBD_POOL> \
  --rbdname=perf-rbd-test \
  --rw=write \
  --bs=1m \
  --iodepth=16 \
  --numjobs=1 \
  --runtime=60 \
  --time_based \
  --group_reporting

rbd rm -p <RBD_POOL> perf-rbd-test
```

명령-값 매핑:

| 실행 명령                                   | 출력에서 확인할 위치                      | 기록할 값        | 발표 사용                        |
| :------------------------------------------ | :---------------------------------------- | :--------------- | :------------------------------- |
| `ethtool <STORAGE_NIC>`                     | `Speed:`                                  | `10000Mb/s` 여부 | 10G link 확인                    |
| `ethtool <STORAGE_NIC>`                     | `Duplex:`                                 | `Full` 여부      | NIC 정상 조건                    |
| `iperf3 -c ... -P 4 -t 30`                  | `[SUM] ... receiver`                      | Gbits/sec        | 실제 10G network throughput      |
| `iperf3 -c ... -P 4 -t 30`                  | `[SUM] ... sender`                        | Gbits/sec        | sender/receiver 차이 확인        |
| `iperf3 -c ... -P 4 -t 30`                  | `Retr`                                    | retransmit 수    | packet 재전송 여부               |
| `rados bench ... write -b 4K`               | `Bandwidth (MB/sec)`                      | MB/s             | Ceph backend write bandwidth     |
| `rados bench ... write -b 4K`               | `Average IOPS`                            | IOPS             | backend 4K write 기준            |
| `rados bench ... write -b 4K`               | `Average Latency(s)`                      | latency          | backend write latency            |
| `fio --name=rbd-4k-randwrite-cache-on ...`  | `write: IOPS=`                            | IOPS             | cache 포함 RBD write 수치        |
| `fio --name=rbd-4k-randwrite-cache-on ...`  | `write: BW=`                              | bandwidth        | cache 포함 bandwidth             |
| `fio --name=rbd-4k-randwrite-cache-on ...`  | `clat percentiles`의 `95.00th`, `99.00th` | p95/p99 latency  | tail latency                     |
| `fio --name=rbd-4k-randwrite-cache-off ...` | `write: IOPS=`                            | IOPS             | cache 제외 RBD write 수치        |
| `fio --name=rbd-4k-randwrite-cache-off ...` | `write: BW=`                              | bandwidth        | cache 제외 bandwidth             |
| `fio --name=rbd-4k-randwrite-cache-off ...` | `clat percentiles`의 `95.00th`, `99.00th` | p95/p99 latency  | HDD write path 영향              |
| `fio --name=rbd-1m-seqwrite ...`            | `write: IOPS=`                            | IOPS             | 1M sequential write operation 수 |
| `fio --name=rbd-1m-seqwrite ...`            | `write: BW=`                              | MB/s             | 대용량 write throughput          |
| `fio --name=rbd-1m-seqwrite ...`            | `clat percentiles`의 `95.00th`, `99.00th` | p95/p99 latency  | 대용량 write latency             |

기록 예시:

| 항목                       | 기존 참고값  | 최신 측정값 | 출처                        | 발표 의미           |
| :------------------------- | :----------- | :---------- | :-------------------------- | :------------------ |
| NIC raw iperf3             | 9.4Gbps      |             | `iperf3 [SUM] receiver`     | 10G 정상 여부       |
| RADOS 4K write             | 99 IOPS      |             | `rados bench Average IOPS`  | backend write 기준  |
| RBD 4K randwrite cache on  | 1,700 IOPS   |             | `fio cache-on write: IOPS`  | cache 포함 수치     |
| RBD 4K randwrite cache off | 100~200 IOPS |             | `fio cache-off write: IOPS` | HDD write path 한계 |
| RBD 1M seqwrite            | 35MB/s       |             | `fio seqwrite write: BW`    | 대용량 write 기준   |

발표 포함 기준:

- iperf3와 fio 결과 모두 확보
- cache on/off 구분 가능
- HDD 기반 구성 한계 설명 가능

발표 보류 기준:

- cache on/off 구분 실패
- 테스트 대상 pool/PVC 불명
- Ceph health 비정상
- 운영 부하 영향 발생

---

## 6. E4 온프레 DB 경로와 PXC 상태

발표 메시지:

- 앱은 ProxySQL endpoint 경유
- PXC 3-node Galera 기반 운영 DB
- DB storage는 Ceph RBD PVC 사용

확보 자료:

- `E4_proxysql_route.png`
- `E4_pxc_wsrep_status.png`
- `E4_pxc_pvc.png`

검증 명령:

```bash
kubectl get sts,pod,pvc -A | grep -i pxc
```

```sql
SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
SELECT username, default_hostgroup FROM mysql_users;
SELECT rule_id, active, match_pattern, destination_hostgroup FROM mysql_query_rules ORDER BY rule_id;
SHOW STATUS LIKE 'wsrep_cluster_status';
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_ready';
SHOW STATUS LIKE 'wsrep_connected';
```

명령-값 매핑:

| 실행 명령                                                          | 출력에서 확인할 위치              | 기록할 값                               | 발표 사용                            |
| :----------------------------------------------------------------- | :-------------------------------- | :-------------------------------------- | :----------------------------------- |
| `kubectl get sts,pod,pvc -A \| grep -i pxc`                        | StatefulSet `READY`               | ready/desired 수                        | PXC workload 동작 여부               |
| `kubectl get sts,pod,pvc -A \| grep -i pxc`                        | Pod `READY`, `STATUS`             | PXC pod 정상 수                         | DB node count 근거                   |
| `kubectl get sts,pod,pvc -A \| grep -i pxc`                        | PVC `STATUS`, `STORAGECLASS`      | `Bound`, RBD StorageClass               | DB storage가 RBD PVC임               |
| `SELECT hostgroup_id, hostname, port, status FROM mysql_servers;`  | `hostgroup_id`, `status`          | writer/reader hostgroup과 `ONLINE` 상태 | ProxySQL routing 근거                |
| `SELECT username, default_hostgroup FROM mysql_users;`             | app user row                      | app user default hostgroup              | 앱이 ProxySQL 사용자로 접근하는 근거 |
| `SELECT rule_id, active, match_pattern, destination_hostgroup ...` | `active`, `destination_hostgroup` | query rule 활성 여부                    | writer/read routing 기준             |
| `SHOW STATUS LIKE 'wsrep_cluster_status';`                         | `Value`                           | `Primary`                               | Galera cluster 정상성                |
| `SHOW STATUS LIKE 'wsrep_cluster_size';`                           | `Value`                           | node 수                                 | PXC 3-node 근거                      |
| `SHOW STATUS LIKE 'wsrep_ready';`                                  | `Value`                           | `ON`                                    | DB node query 처리 가능 여부         |
| `SHOW STATUS LIKE 'wsrep_connected';`                              | `Value`                           | `ON`                                    | Galera 연결 상태                     |

기록 예시:

| 발표 항목            | 값                     | 출처                                                |
| :------------------- | :--------------------- | :-------------------------------------------------- |
| App DB path          | App -> ProxySQL -> PXC | `mysql_servers`, `mysql_users`, `mysql_query_rules` |
| PXC node count       |                        | `wsrep_cluster_size`, `kubectl get pod`             |
| wsrep_cluster_status |                        | `SHOW STATUS LIKE 'wsrep_cluster_status'`           |
| wsrep_ready          |                        | `SHOW STATUS LIKE 'wsrep_ready'`                    |
| PVC type             |                        | `kubectl get pvc -A STORAGECLASS`                   |

발표 포함 기준:

- ProxySQL routing 확인
- PXC 3-node 또는 현재 node 수 설명 가능
- wsrep 정상
- AWS DB 제외 범위 명확

발표 보류 기준:

- PXC 상태 불명
- 앱이 PXC 직접 접속하는 캡처
- ProxySQL 단일 SPOF 질문 대응 불가

---

## 7. E5 DB Backup 복구성

발표 메시지:

- DB backup은 replica와 별도
- 트랜잭션 일관성과 특정 시점 복구 기준
- backup file 존재보다 restore 검증 중요

확보 자료:

- `E5_db_backup_timestamp.png`
- `E5_db_binlog.png`
- `E5_db_restore_test.png`

검증 명령:

```bash
ls -al <DB_BACKUP_DIR>
find <DB_BACKUP_DIR> -maxdepth 2 -type f | tail
```

```sql
SHOW VARIABLES LIKE 'log_bin';
SHOW BINARY LOGS;
```

restore 검증:

```bash
# test DB 또는 restore 전용 환경 기준
<DB_RESTORE_COMMAND> --dry-run
```

명령-값 매핑:

| 실행 명령                                          | 출력에서 확인할 위치        | 기록할 값             | 발표 사용             |
| :------------------------------------------------- | :-------------------------- | :-------------------- | :-------------------- |
| `ls -al <DB_BACKUP_DIR>`                           | file list                   | backup file 존재 여부 | full backup 존재 근거 |
| `ls -al <DB_BACKUP_DIR>`                           | timestamp column            | 최신 backup 생성 시각 | backup 최신성         |
| `find <DB_BACKUP_DIR> -maxdepth 2 -type f \| tail` | 마지막 file 목록            | backup 구성 파일 존재 | backup 산출물 근거    |
| `SHOW VARIABLES LIKE 'log_bin';`                   | `Value`                     | `ON`/`OFF`            | binlog 활성 여부      |
| `SHOW BINARY LOGS;`                                | `Log_name`, `File_size`     | binlog 파일 목록/크기 | 특정 시점 복구 근거   |
| `<DB_RESTORE_COMMAND> --dry-run`                   | exit code / success message | 성공/실패             | restore 절차 검증     |

기록 예시:

| 발표 항목        | 값  | 출처                             |
| :--------------- | :-- | :------------------------------- |
| full backup      |     | `ls -al <DB_BACKUP_DIR>`         |
| backup timestamp |     | `ls -al timestamp`               |
| binlog           |     | `SHOW VARIABLES LIKE 'log_bin'`  |
| binlog files     |     | `SHOW BINARY LOGS`               |
| restore test     |     | `<DB_RESTORE_COMMAND> --dry-run` |

발표 포함 기준:

- backup timestamp 확보
- binlog 활성 여부 확인
- restore test 또는 dry-run 여부 명확

발표 표현 제한:

- restore 미검증 시: `백업 파일 존재, 복구 검증 후속 과제`
- restore 검증 시: `복구 가능성 확인`

---

## 8. E6 Object Backup Copy-only

발표 메시지:

- 이미지/영상 object는 Ceph RGW 저장
- AWS S3 copy-only backup으로 삭제 전파 방지
- restore dry-run으로 복구 가능성 확인

확보 자료:

- `E6_rgw_source_bucket.png`
- `E6_aws_s3_backup_count.png`
- `E6_object_restore_dryrun.png`

검증 명령:

```bash
radosgw-admin bucket stats --bucket <APP_BUCKET>
rclone size ceph:<APP_BUCKET> --config <RCLONE_CONFIG>
aws s3 ls s3://<BACKUP_BUCKET>/<PREFIX>/ --recursive --summarize
aws s3api get-bucket-lifecycle-configuration --bucket <BACKUP_BUCKET>
```

restore dry-run:

```bash
rclone copy aws-s3:<BACKUP_PREFIX> ceph:<RESTORE_TEST_BUCKET> \
  --config <RCLONE_CONFIG> \
  --dry-run \
  --progress
```

명령-값 매핑:

| 실행 명령                                                          | 출력에서 확인할 위치                     | 기록할 값                 | 발표 사용                 |
| :----------------------------------------------------------------- | :--------------------------------------- | :------------------------ | :------------------------ |
| `radosgw-admin bucket stats --bucket <APP_BUCKET>`                 | `bucket`                                 | source bucket 이름        | 원본 bucket 식별          |
| `radosgw-admin bucket stats --bucket <APP_BUCKET>`                 | `usage.rgw.main.num_objects`             | source object count       | 원본 object 수            |
| `radosgw-admin bucket stats --bucket <APP_BUCKET>`                 | `usage.rgw.main.size_kb_actual`          | source actual size        | 원본 저장량               |
| `rclone size ceph:<APP_BUCKET> ...`                                | `Total objects`                          | source object count       | RGW source 교차 확인      |
| `rclone size ceph:<APP_BUCKET> ...`                                | `Total size`                             | source size               | RGW source size 교차 확인 |
| `aws s3 ls s3://<BACKUP_BUCKET>/<PREFIX>/ --recursive --summarize` | `Total Objects`                          | backup object count       | AWS S3 백업 반영 여부     |
| `aws s3 ls s3://<BACKUP_BUCKET>/<PREFIX>/ --recursive --summarize` | `Total Size`                             | backup size               | 백업 저장량               |
| `aws s3api get-bucket-lifecycle-configuration ...`                 | `Rules`, `Status`, `Transitions`         | lifecycle rule 존재/상태  | 장기 보관 정책            |
| `rclone copy ... --dry-run --progress`                             | `Transferred`, `Checks`, dry-run summary | restore dry-run 성공 여부 | 복구 경로 확인            |

기록 예시:

| 발표 항목           | 값  | 출처                                                 |
| :------------------ | :-- | :--------------------------------------------------- |
| source object count |     | `radosgw-admin usage.rgw.main.num_objects`           |
| backup object count |     | `aws s3 ls --summarize Total Objects`                |
| source size         |     | `radosgw-admin usage.rgw.main.size_kb_actual`        |
| backup size         |     | `aws s3 ls --summarize Total Size`                   |
| lifecycle           |     | `aws s3api get-bucket-lifecycle-configuration Rules` |
| restore dry-run     |     | `rclone copy --dry-run summary`                      |

발표 포함 기준:

- source/backup count 비교 가능
- copy-only 정책 설명 가능
- restore dry-run 결과 확보

발표 보류 기준:

- 백업 bucket 용도 불명
- restore dry-run 미수행인데 복구 가능 단정
- Harbor image blob backup/replication 정책 혼동

---

## 9. E7 Redis 일관성/Cache 효과

발표 메시지:

- Redis는 DB 부하 감소 계층
- Redis는 AWS/온프레 예매 상태 단일 기준점
- HIT/MISS latency 차이로 사용자 체감 효과 설명 가능

확보 자료:

- `E7_cache_hit_latency.txt`
- `E7_cache_miss_latency.txt`
- `E7_redis_stats_before_after.png`
- `E7_db_questions_before_after.png`
- `E7_cache_effect_table.png`

측정 전:

```bash
redis-cli <AUTH_OPTION> INFO stats | grep -E "keyspace_hits|keyspace_misses|total_commands_processed"
```

```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Questions';
```

Cache HIT 측정:

```bash
curl -s -k <APP_CACHE_HIT_URL> > /dev/null

for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -k -w "%{time_total}\n" -o /dev/null <APP_CACHE_HIT_URL>
done
```

Cache MISS 측정:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -k -w "%{time_total}\n" -o /dev/null "<APP_CACHE_MISS_URL>?seed=$i"
done
```

측정 후:

```bash
redis-cli <AUTH_OPTION> INFO stats | grep -E "keyspace_hits|keyspace_misses|total_commands_processed"
```

```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Questions';
```

명령-값 매핑:

| 실행 명령                                                  | 출력에서 확인할 위치       | 기록할 값                      | 발표 사용             |
| :--------------------------------------------------------- | :------------------------- | :----------------------------- | :-------------------- |
| `redis-cli ... INFO stats \| grep ...` 측정 전             | `keyspace_hits`            | before hits                    | cache hit 기준값      |
| `redis-cli ... INFO stats \| grep ...` 측정 전             | `keyspace_misses`          | before misses                  | cache miss 기준값     |
| `redis-cli ... INFO stats \| grep ...` 측정 전             | `total_commands_processed` | before commands                | Redis 처리량 기준값   |
| `SHOW STATUS LIKE 'Threads_connected';` 측정 전            | `Value`                    | before DB connections          | DB connection 기준값  |
| `SHOW GLOBAL STATUS LIKE 'Questions';` 측정 전             | `Value`                    | before DB questions            | DB query 기준값       |
| `curl -s -k -w "%{time_total}\n" ... <APP_CACHE_HIT_URL>`  | stdout time 값 10개        | HIT latency p50/p95 또는 평균  | Redis cache 체감 응답 |
| `curl -s -k -w "%{time_total}\n" ... <APP_CACHE_MISS_URL>` | stdout time 값 10개        | MISS latency p50/p95 또는 평균 | DB 접근 포함 응답     |
| `redis-cli ... INFO stats \| grep ...` 측정 후             | `keyspace_hits`            | after hits                     | hit 증가량            |
| `redis-cli ... INFO stats \| grep ...` 측정 후             | `keyspace_misses`          | after misses                   | miss 증가량           |
| `redis-cli ... INFO stats \| grep ...` 측정 후             | `total_commands_processed` | after commands                 | Redis 처리 증가량     |
| `SHOW STATUS LIKE 'Threads_connected';` 측정 후            | `Value`                    | after DB connections           | DB connection 변화    |
| `SHOW GLOBAL STATUS LIKE 'Questions';` 측정 후             | `Value`                    | after DB questions             | DB query 증가량       |

계산값 매핑:

| 계산값               | 계산식                                                       | 입력값 출처             | 발표 사용             |
| :------------------- | :----------------------------------------------------------- | :---------------------- | :-------------------- |
| keyspace_hits 증가   | `after_hits - before_hits`                                   | Redis INFO stats 전/후  | Redis cache 사용 근거 |
| keyspace_misses 증가 | `after_misses - before_misses`                               | Redis INFO stats 전/후  | DB 접근 발생 근거     |
| hit ratio            | `after_hits_delta / (after_hits_delta + after_misses_delta)` | Redis INFO stats 전/후  | cache 활용률          |
| DB Questions 증가량  | `after_questions - before_questions`                         | MySQL `Questions` 전/후 | DB offload 비교       |
| HIT/MISS 개선 배율   | `MISS latency / HIT latency`                                 | curl HIT/MISS latency   | 사용자 체감 개선      |

기록 예시:

| 발표 항목            | 값  | 출처                                 |
| :------------------- | :-- | :----------------------------------- |
| Cache HIT latency    |     | `curl HIT time_total`                |
| Cache MISS latency   |     | `curl MISS time_total`               |
| HIT/MISS 개선 배율   |     | `MISS latency / HIT latency`         |
| keyspace_hits 증가   |     | `Redis keyspace_hits after-before`   |
| keyspace_misses 증가 |     | `Redis keyspace_misses after-before` |
| DB Questions 증가량  |     | `MySQL Questions after-before`       |

계산식:

```text
hits_delta = keyspace_hits_after - keyspace_hits_before
misses_delta = keyspace_misses_after - keyspace_misses_before
hit_ratio = hits_delta / (hits_delta + misses_delta)
improvement_ratio = cache_miss_latency / cache_hit_latency
db_questions_delta = questions_after - questions_before
```

발표 포함 기준:

- HIT/MISS 조건 구분 가능
- Redis stats 전후 비교 가능
- DB Questions 또는 connection 변화와 함께 제시
- AWS/온프레가 Redis를 공통 기준점으로 보는 구조 설명 가능

발표 보류 기준:

- HIT/MISS 구분 불명
- latency만 있고 DB 부하 감소 근거 없음
- Redis를 DB 대체처럼 표현할 위험

---

## 10. E8 Redis Sentinel Failover

발표 메시지:

- Redis Sentinel 3-node/quorum 기반 HA 구성
- master 장애 시 failover 가능
- failover는 0초 무중단이 아니라 전환 시간 존재

확보 자료:

- `E8_redis_ckquorum.png`
- `E8_redis_master_before.png`
- `E8_redis_master_after.png`
- `E8_redis_sentinel_failover.mp4`

구성 확인:

```bash
kubectl get pod,svc,pvc -n redis

kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel ckquorum mymaster

kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel get-master-addr-by-name mymaster
```

수동 failover 시연:

```bash
kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel failover mymaster

sleep 30

kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel get-master-addr-by-name mymaster
```

failover 후 cache 확인:

```bash
curl -s -k <APP_CACHE_URL>
curl -s -k <APP_CACHE_URL>
```

명령-값 매핑:

| 실행 명령                                                                      | 출력에서 확인할 위치         | 기록할 값                | 발표 사용                    |
| :----------------------------------------------------------------------------- | :--------------------------- | :----------------------- | :--------------------------- |
| `kubectl get pod,svc,pvc -n redis`                                             | Pod `READY`, `STATUS`        | Redis pod 정상 수        | Redis node count             |
| `kubectl get pod,svc,pvc -n redis`                                             | PVC `STATUS`, `STORAGECLASS` | Redis PVC Bound/RBD 여부 | Redis persistent volume 근거 |
| `redis-cli -p 26379 ... sentinel ckquorum mymaster`                            | `OK ... usable Sentinels`    | usable Sentinels 수      | Sentinel quorum 정상성       |
| `redis-cli -p 26379 ... sentinel ckquorum mymaster`                            | `OK ... quorum` 또는 메시지  | quorum 충족 여부         | failover 가능 조건           |
| `redis-cli -p 26379 ... sentinel get-master-addr-by-name mymaster` failover 전 | 1행 IP/host, 2행 port        | master before            | failover 전 master           |
| `redis-cli -p 26379 ... sentinel failover mymaster`                            | command result               | `OK` 여부                | controlled failover 시작     |
| `sleep 30`                                                                     | 시간 측정                    | 대기 시간                | failover 관찰 기준           |
| `redis-cli -p 26379 ... sentinel get-master-addr-by-name mymaster` failover 후 | 1행 IP/host, 2행 port        | master after             | master 변경 근거             |
| `curl -s -k <APP_CACHE_URL>` failover 후                                       | response body/status         | cache HIT 또는 정상 응답 | 앱 관점 Redis 사용 가능 여부 |

기록 예시:

| 발표 항목        | 값  | 출처                                           |
| :--------------- | :-- | :--------------------------------------------- |
| Redis node count |     | `kubectl get pod -n redis`                     |
| Sentinel quorum  |     | `sentinel ckquorum mymaster`                   |
| usable Sentinels |     | `sentinel ckquorum mymaster`                   |
| master before    |     | `sentinel get-master-addr-by-name` failover 전 |
| master after     |     | `sentinel get-master-addr-by-name` failover 후 |
| failover time    |     | failover command 시각 ~ master 변경 시각       |
| cache 유지       |     | failover 후 `curl <APP_CACHE_URL>`             |

발표 포함 기준:

- master before/after 차이 확인
- `ckquorum` 정상
- failover 후 cache 동작 확인
- 영상 30~60초 내 편집 가능

발표 보류 기준:

- failover 실패
- master 변경 확인 불가
- client 영향 설명 불가
- 운영 영향 발생

---

## 11. Q&A 보조 증거

### 11.1 Q1 PXC OLTP 성능

사용 상황:

- "온프레 DB 성능은 어느 정도인가?" 질문
- Redis 효과와 DB baseline 비교 필요

측정:

```bash
kubectl run sysbench-pxc \
  --image=severalnines/sysbench \
  --restart=Never \
  --command -- sleep 3600

kubectl wait --for=condition=ready pod/sysbench-pxc --timeout=120s

kubectl exec sysbench-pxc -- sysbench \
  --db-driver=mysql \
  --mysql-host=<PROXYSQL_ENDPOINT> \
  --mysql-port=6033 \
  --mysql-user=<TEST_USER> \
  --mysql-password=<TEST_PASSWORD> \
  --mysql-db=perf_test \
  --tables=4 \
  --table-size=100000 \
  --threads=8 \
  --time=60 \
  --report-interval=10 \
  /usr/share/sysbench/oltp_read_write.lua run
```

명령-값 매핑:

| 실행 명령                                | 출력에서 확인할 위치            | 기록할 값      | 사용            |
| :--------------------------------------- | :------------------------------ | :------------- | :-------------- |
| `kubectl run sysbench-pxc ...`           | `pod/sysbench-pxc created`      | Pod 생성 성공  | 측정 환경 준비  |
| `kubectl wait --for=condition=ready ...` | `condition met`                 | Pod ready 여부 | 측정 가능 상태  |
| `sysbench ... run`                       | `transactions:`                 | TPS            | OLTP 처리량     |
| `sysbench ... run`                       | `queries:`                      | QPS            | DB query 처리량 |
| `sysbench ... run`                       | `Latency (ms): avg`             | avg latency    | 평균 응답 시간  |
| `sysbench ... run`                       | `Latency (ms): 95th percentile` | p95 latency    | tail latency    |
| `sysbench ... run`                       | `SQL statistics: errors`        | error count    | 측정 신뢰성     |

기록 예시:

| 항목        | 값  | 출처                             |
| :---------- | :-- | :------------------------------- |
| TPS         |     | `sysbench transactions per sec`  |
| QPS         |     | `sysbench queries per sec`       |
| avg latency |     | `sysbench Latency avg`           |
| p95 latency |     | `sysbench 95th percentile`       |
| error count |     | `sysbench SQL statistics errors` |

본문 제외 기준:

- test schema 조건 설명 불가
- cleanup 미확인
- 실제 서비스 쿼리와 차이 설명 불가

### 11.2 Q2 RGW Endpoint HA

사용 상황:

- "Object data는 복제되는데 endpoint 장애는?" 질문

측정:

```bash
ceph orch ps --daemon_type rgw
ceph orch ls --service_type rgw
ss -lntp | grep 7480
```

명령-값 매핑:

| 실행 명령                         | 출력에서 확인할 위치   | 기록할 값             | 사용                    |
| :-------------------------------- | :--------------------- | :-------------------- | :---------------------- |
| `ceph orch ps --daemon_type rgw`  | daemon row 개수        | RGW daemon 수         | service HA 여부         |
| `ceph orch ps --daemon_type rgw`  | `STATUS`, `HOST`       | daemon 상태/분산 host | 장애 domain 확인        |
| `ceph orch ls --service_type rgw` | `PLACEMENT`, `RUNNING` | service 배치/실행 수  | RGW service 구성        |
| `ss -lntp \| grep 7480`           | listen address/process | endpoint listen 여부  | 단일 endpoint risk 확인 |

기록 예시:

| 항목               | 값  | 출처                                       |
| :----------------- | :-- | :----------------------------------------- |
| RGW daemon 수      |     | `ceph orch ps --daemon_type rgw` row count |
| daemon host 분산   |     | `ceph orch ps HOST`                        |
| LB/VIP 존재 여부   |     | `ceph orch ls`, 외부 LB 구성 확인          |
| 단일 endpoint 여부 |     | `ss -lntp`, service endpoint 구성          |

본문 제외 기준:

- 현재 단일 endpoint면 본문에서는 리스크로만 짧게 언급
- HA 구성 완료가 아니면 "개선 과제" 표현

### 11.3 Q3 Redis Benchmark

사용 상황:

- "Redis 자체 처리량은 충분한가?" 질문

측정:

```bash
kubectl run redis-bench \
  --rm -i \
  --restart=Never \
  --image=redis:7-alpine \
  --command -- \
  redis-benchmark \
    -h <REDIS_MASTER_ENDPOINT> \
    -p 6379 \
    <AUTH_OPTION> \
    -t get,set \
    -n 50000 \
    -c 100 \
    -q
```

명령-값 매핑:

| 실행 명령                                           | 출력에서 확인할 위치 | 기록할 값               | 사용                  |
| :-------------------------------------------------- | :------------------- | :---------------------- | :-------------------- |
| `redis-benchmark ... -t get,set -n 50000 -c 100 -q` | `GET:` line          | GET requests per second | Redis read 처리 여유  |
| `redis-benchmark ... -t get,set -n 50000 -c 100 -q` | `SET:` line          | SET requests per second | Redis write 처리 여유 |
| `redis-benchmark ... -n 50000`                      | command option       | request 수              | 측정 조건             |
| `redis-benchmark ... -c 100`                        | command option       | concurrency             | 측정 조건             |

기록 예시:

| 항목        | 값    | 출처                       |
| :---------- | :---- | :------------------------- |
| GET ops/sec |       | `redis-benchmark GET line` |
| SET ops/sec |       | `redis-benchmark SET line` |
| request 수  | 50000 | command `-n`               |
| concurrency | 100   | command `-c`               |

본문 제외 기준:

- app HIT/MISS 수치 확보 시 본문에서는 생략 가능
- benchmark는 실제 app 응답 시간 대체 불가

---

## 12. 최종 발표 자료 매핑

| 슬라이드     | Evidence ID | 자료                      | 한 줄 설명                    |
| :----------- | :---------- | :------------------------ | :---------------------------- |
| Storage 구조 | E1, E2      | Ceph 상태/PVC/bucket 캡처 | Ceph가 block/object 기반 제공 |
| Storage 성능 | E3          | iperf3/fio 표             | 10G 정상, HDD write path 한계 |
| On-prem DB   | E4          | ProxySQL/PXC 캡처         | App -> ProxySQL -> PXC        |
| Backup       | E5, E6      | backup/restore 캡처       | replica와 backup 분리         |
| Redis 효과   | E7          | HIT/MISS 표               | DB 부하 감소 + 상태 일관성    |
| Redis HA     | E8          | failover 영상             | Sentinel 기반 master 전환     |

발표 제외 확인:

- endpoint/IP/secret 노출 없음
- 설명 불가 수치 없음
- 단독 benchmark 과장 없음
- backup과 replica 혼동 없음
- Redis와 DB 역할 혼동 없음
