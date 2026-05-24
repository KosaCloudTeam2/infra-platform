# Storage Platform 발표 근거 검증 절차

> 대상: `storage-platform-presentation-evidence.md`의 발표용 검증값 목적: 발표에 사용할 최신
> 측정값과 캡처 확보 원칙: 운영 세부 endpoint/IP/계정/secret은 발표 자료에서 제외

---

## 1. 검증 진행 원칙

- 최신 측정값 우선
- 기존 문서 수치 참고값 처리
- 운영 PVC 직접 부하 테스트 금지
- 운영 DB destructive query 금지
- Redis failover 시험은 발표 준비 시간대 또는 테스트 환경에서만 수행
- endpoint, IP, bucket, pool, 계정명 캡처 시 마스킹
- 캡처 파일명에 날짜, 영역, 지표 포함

캡처 파일명 예시:

```text
2026-05-24_ceph_osd_tree.png
2026-05-24_ceph_iperf3_10g.png
2026-05-24_redis_ckquorum.png
2026-05-24_backup_object_count.png
```

최종 산출물:

- 발표용 수치 표
- 원본 캡처
- 수치 해석 1줄
- 리스크/한계 1줄

---

## 2. 전체 검증 순서

1. Ceph 기본 상태 확인
2. Ceph 용량/replica 확인
3. RBD/RGW 사용 근거 확인
4. 10G network 성능 확인
5. Ceph RADOS/RBD 성능 측정
6. RGW endpoint HA 리스크 확인
7. On-prem DB 경로 확인
8. PXC Galera 상태 확인
9. DB backup 근거 확인
10. Object backup 근거 확인
11. Redis Sentinel HA 확인
12. Redis 기능/효과 확인
13. 발표용 수치 표 작성
14. 민감 정보 마스킹

---

## 3. Ceph 기본 상태 확인

### 3.1 확인 목적

- Ceph cluster 정상 여부 확인
- OSD 수 확인
- 장애 상태 없는지 확인
- 성능 측정 전 기준 상태 확보

### 3.2 실행

Ceph 노드:

```bash
ceph -s
ceph health detail
ceph osd tree
ceph osd stat
ceph pg stat
ceph df
```

### 3.3 발표에 남길 값

| 발표 항목   | 기록값                                     |
| :---------- | :----------------------------------------- |
| Ceph health | `HEALTH_OK` 또는 설명 가능한 `HEALTH_WARN` |
| OSD 수      | `up/in` 개수                               |
| PG 상태     | `active+clean` 여부                        |
| Raw 용량    | 전체 raw capacity                          |
| 가용 용량   | replica 반영 후 usable capacity            |

### 3.4 발표 해석

- `6 OSD`, `6TB Raw`, `2TB usable` 확인 시 발표 사용 가능
- `HEALTH_WARN` 존재 시 원인 설명 없이 성능 수치 발표 금지
- PG가 `active+clean`이 아니면 성능 측정 보류

### 3.5 캡처 기준

- `ceph -s`
- `ceph osd tree`
- `ceph df`

---

## 4. Ceph Replica / Self-Healing 근거 확인

### 4.1 확인 목적

- 3-replica 구조 확인
- Ceph replica가 가용성 risk를 줄이는 근거 확보
- Ceph replica와 backup의 차이 설명 근거 확보

### 4.2 실행

Ceph 노드:

```bash
ceph osd pool ls detail
ceph osd pool get <RBD_POOL> size
ceph osd pool get <RBD_POOL> min_size
ceph osd pool get <RGW_DATA_POOL> size
ceph osd pool get <RGW_DATA_POOL> min_size
ceph pg stat
```

### 4.3 발표에 남길 값

| 발표 항목        | 기록값                   |
| :--------------- | :----------------------- |
| RBD replica size | `size` 값                |
| RGW replica size | `size` 값                |
| min_size         | 장애 시 최소 복제본 기준 |
| PG 상태          | `active+clean` 여부      |

### 4.4 발표 해석

- replica는 디스크/노드 장애 risk 감소
- replica는 삭제/오염/운영 실수 복구 대체 불가
- Backup은 특정 시점 복구와 논리적 손상 대응

### 4.5 캡처 기준

- `ceph osd pool ls detail`
- `ceph pg stat`

---

## 5. RBD/RGW 활용 근거 확인

### 5.1 확인 목적

- RBD가 Stateful workload PVC로 사용되는지 확인
- RGW가 Harbor/App object 저장에 사용되는지 확인
- RBD/RGW dual 활용 발표 근거 확보

### 5.2 RBD 확인

Kubernetes 접근 노드:

```bash
kubectl get sc
kubectl get pvc -A
kubectl get pv
kubectl get sts -A
```

Ceph 노드:

```bash
rbd ls -p <RBD_POOL>
rbd info -p <RBD_POOL> <RBD_IMAGE>
```

### 5.3 RGW 확인

Ceph 노드:

```bash
radosgw-admin bucket list
radosgw-admin bucket stats --bucket <HARBOR_OR_APP_BUCKET>
```

### 5.4 발표에 남길 값

| 발표 항목    | 기록값                                              |
| :----------- | :-------------------------------------------------- |
| RBD 사용처   | PXC, Redis, Jenkins, Harbor metadata, Prometheus 등 |
| RGW 사용처   | Harbor image blob, App object                       |
| StorageClass | RBD 기반 여부                                       |
| Bucket 증가  | push/upload 후 object count 증가                    |

### 5.5 발표 해석

- RBD: block volume
- RGW: S3 compatible object storage
- 같은 Ceph cluster에서 block/object 동시 제공

### 5.6 캡처 기준

- `kubectl get pvc -A`
- `kubectl get sc`
- `radosgw-admin bucket stats`

---

## 6. 10G Network 성능 확인

### 6.1 확인 목적

- Ceph 성능 병목이 network인지 disk인지 분리
- 10G fabric 정상 여부 확인

### 6.2 사전 확인

각 노드:

```bash
ip -br addr
ip route get <STORAGE_PEER_IP>
ethtool <STORAGE_NIC>
```

### 6.3 측정

서버 노드:

```bash
iperf3 -s -B <STORAGE_NODE_IP>
```

클라이언트 노드:

```bash
iperf3 -c <STORAGE_NODE_IP> -P 4 -t 30
```

### 6.4 발표에 남길 값

| 발표 항목            | 기록값      |
| :------------------- | :---------- |
| network throughput   | Gbps        |
| sender/receiver 차이 | Gbps        |
| retransmit           | 수치        |
| link speed           | 10Gbps 여부 |

### 6.5 발표 해석

- 9Gbps 이상이면 10G 경로 정상으로 설명 가능
- Ceph write가 낮은데 iperf3가 높으면 disk/write path 병목으로 해석
- iperf3가 낮으면 Ceph 성능 수치 해석 전 network부터 점검

### 6.6 캡처 기준

- `ethtool`
- `iperf3` 결과

---

## 7. Ceph RADOS/RBD 성능 측정

### 7.1 확인 목적

- HDD 기반 Ceph write path 병목 확인
- `35 MB/s`, `99 IOPS`, `1,700 IOPS` 참고값 최신화
- cache 포함/제외 결과 구분

### 7.2 사전 조건

- Ceph health 정상
- PG `active+clean`
- 테스트 전용 RBD image 준비
- 운영 PVC 직접 테스트 금지
- 업무 시간대 과도한 부하 테스트 지양

### 7.3 RADOS 4K write 측정

Ceph 노드:

```bash
rados bench -p <TEST_POOL> 60 write -b 4K -t 16 --no-cleanup
rados cleanup -p <TEST_POOL>
```

기록값:

- IOPS
- bandwidth
- average latency

발표 표현:

- `RADOS 4K write`
- `RADOS 4K randwrite` 표현 지양

### 7.4 RBD 4K randwrite cache on 측정

테스트 RBD image:

```bash
rbd create -p <RBD_POOL> perf-rbd-test --size 4096
```

fio:

```bash
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

기록값:

- IOPS
- bandwidth
- average latency
- p95/p99 latency

발표 표현:

- `RBD 4K randwrite cache 포함`
- cache 포함 수치임을 반드시 명시

### 7.5 RBD 4K randwrite cache off 측정

임시 설정:

```bash
cp /etc/ceph/ceph.conf /tmp/ceph-cache-off.conf
printf '\n[client]\nrbd cache = false\n' >> /tmp/ceph-cache-off.conf
```

fio:

```bash
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

주의:

- cluster 전역 설정 변경 금지
- 임시 config만 사용

### 7.6 RBD 1M seqwrite 측정

fio:

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
```

기록값:

- MB/s
- IOPS
- average latency
- p95/p99 latency

### 7.7 정리

Ceph 노드:

```bash
rbd rm -p <RBD_POOL> perf-rbd-test
```

### 7.8 발표용 표

| 항목                       | 기존 참고값  | 재측정값 | 발표 판단   |
| :------------------------- | :----------- | :------- | :---------- |
| 10G network                | 9.4 Gbps     |          | 조건부 사용 |
| RADOS 4K write             | 99 IOPS      |          | 조건부 사용 |
| RBD 4K randwrite cache on  | 1,700 IOPS   |          | 조건부 사용 |
| RBD 4K randwrite cache off | 100~200 IOPS |          | 조건부 사용 |
| RBD 1M seqwrite            | 35 MB/s      |          | 조건부 사용 |

### 7.9 발표 해석

- iperf3 높음 + RBD write 낮음: HDD write path 병목
- cache on/off 차이 큼: cache 포함 수치 과장 주의
- 1M seqwrite 낮음: sequential write도 HDD/replica/WAL 영향
- SSD WAL/DB 분리 개선 후보

---

## 8. RGW Endpoint HA 리스크 확인

### 8.1 확인 목적

- RGW 데이터 복제와 RGW service HA 구분
- RGW 단일 daemon 여부 확인
- 발표 리스크 근거 확보

### 8.2 실행

cephadm 환경:

```bash
ceph orch ps --daemon_type rgw
ceph orch ls --service_type rgw
```

systemd 환경:

```bash
systemctl list-units | grep radosgw
ss -lntp | grep 7480
```

Kubernetes 배포형 환경:

```bash
kubectl get pod -A | grep -i rgw
kubectl get svc -A | grep -i rgw
```

### 8.3 발표에 남길 값

| 발표 항목          | 기록값    |
| :----------------- | :-------- |
| RGW daemon 수      | 개수      |
| LB/VIP 존재        | 있음/없음 |
| 단일 endpoint 여부 | 있음/없음 |

### 8.4 발표 해석

- RGW daemon 1개면 S3 endpoint SPoF
- object data는 replica 대상
- S3 API endpoint HA는 별도 개선 과제

---

## 9. On-prem DB 경로 확인

### 9.1 확인 목적

- 앱이 ProxySQL을 통해 PXC에 접근하는지 확인
- PXC 직접 접속 지양 근거 확보
- 온프레 DB 담당 범위 검증

### 9.2 ProxySQL 확인

ProxySQL admin:

```sql
SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
SELECT username, default_hostgroup FROM mysql_users;
SELECT rule_id, active, match_pattern, destination_hostgroup FROM mysql_query_rules ORDER BY rule_id;
```

App 접근 경로:

```bash
mysql -h <PROXYSQL_ENDPOINT> -P 6033 -u <APP_USER> -p -e "SELECT @@hostname;"
```

### 9.3 발표에 남길 값

| 발표 항목          | 기록값                 |
| :----------------- | :--------------------- |
| App DB path        | App -> ProxySQL -> PXC |
| PXC 직접 접속 여부 | 지양/없음              |
| ProxySQL routing   | 정상                   |
| DB connection      | 측정값                 |

### 9.4 발표 해석

- ProxySQL은 DB endpoint 단순화 계층
- ProxySQL은 writer 경로와 connection 관리 계층
- DB endpoint/hostgroup 번호는 발표에서 생략

### 9.5 캡처 기준

- `mysql_servers`
- `mysql_users`
- app query 성공 화면

---

## 10. PXC Galera 상태 확인

### 10.1 확인 목적

- PXC 3 nodes 근거 확보
- Galera 동기 복제 상태 확인
- 운영 DB HA 설명 근거 확보

### 10.2 Kubernetes 확인

```bash
kubectl get sts,pod,pvc -A | grep -i pxc
```

### 10.3 DB 상태 확인

PXC node:

```sql
SHOW STATUS LIKE 'wsrep_cluster_status';
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_ready';
SHOW STATUS LIKE 'wsrep_connected';
SHOW STATUS LIKE 'Threads_connected';
SHOW PROCESSLIST;
```

### 10.4 발표에 남길 값

| 발표 항목      | 기록값            |
| :------------- | :---------------- |
| PXC node count | 3                 |
| cluster status | Primary           |
| wsrep ready    | ON                |
| DB connection  | Threads_connected |
| PVC type       | RBD RWO PVC       |

### 10.5 발표 해석

- PXC 3 nodes + Galera 동기 복제
- 각 DB Pod는 안정적 PVC 사용
- RBD PVC는 DB 저장소 계층
- DB backup은 별도 필요

---

## 11. DB Backup 근거 확인

### 11.1 확인 목적

- DB backup과 object backup 분리 근거 확보
- XtraBackup/binlog/restore 가능성 확인
- DB 복구성 발표 근거 확보

### 11.2 확인

백업 저장 위치:

```bash
ls -al <DB_BACKUP_DIR>
find <DB_BACKUP_DIR> -maxdepth 2 -type f | tail
```

DB:

```sql
SHOW VARIABLES LIKE 'log_bin';
SHOW BINARY LOGS;
```

### 11.3 발표에 남길 값

| 발표 항목        | 기록값      |
| :--------------- | :---------- |
| full backup      | 있음/없음   |
| backup timestamp | 최신 시각   |
| binlog           | 활성/비활성 |
| restore test     | 실행/미실행 |

### 11.4 발표 해석

- DB backup은 트랜잭션 일관성 기준 필요
- binlog는 특정 시점 복구 근거
- restore test 없으면 "백업 파일 존재"까지만 표현

---

## 12. Object Backup 근거 확인

### 12.1 확인 목적

- Ceph RGW object가 AWS S3로 복사되는지 확인
- copy-only 정책 근거 확보
- restore 가능성 근거 확보

### 12.2 원본 object 확인

Ceph/RGW:

```bash
radosgw-admin bucket stats --bucket <APP_BUCKET>
rclone size ceph:<APP_BUCKET> --config <RCLONE_CONFIG>
```

### 12.3 AWS S3 백업 확인

AWS CLI:

```bash
aws s3 ls s3://<BACKUP_BUCKET>/<PREFIX>/ --recursive --summarize
aws s3api get-bucket-lifecycle-configuration --bucket <BACKUP_BUCKET>
```

### 12.4 Restore dry-run 확인

```bash
rclone copy aws-s3:<BACKUP_PREFIX> ceph:<RESTORE_TEST_BUCKET> \
  --config <RCLONE_CONFIG> \
  --dry-run \
  --progress
```

### 12.5 발표에 남길 값

| 발표 항목         | 기록값    |
| :---------------- | :-------- |
| 원본 object count | 측정값    |
| 백업 object count | 측정값    |
| object size       | 측정값    |
| lifecycle         | 설정 여부 |
| restore dry-run   | 성공/실패 |

### 12.6 발표 해석

- Ceph replica는 운영 장애 대응
- AWS S3 backup은 삭제/오염/운영 실수 복구 대응
- copy-only는 원본 삭제 전파 방지 정책

---

## 13. Redis Sentinel HA 확인

### 13.1 확인 목적

- Redis 3 nodes 확인
- Sentinel quorum 2 확인
- failover 가능성 확인

### 13.2 구성 확인

Kubernetes:

```bash
kubectl get pod,svc,pvc -n redis
```

Sentinel:

```bash
kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel get-master-addr-by-name mymaster

kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel ckquorum mymaster
```

### 13.3 Failover 시험

주의:

- 발표 준비 시간대에만 수행
- 운영 영향 가능성 사전 공유
- 테스트 환경 우선

실행 후보:

```bash
kubectl delete pod -n redis <CURRENT_MASTER_POD>
sleep 30
kubectl exec -n redis <REDIS_POD> -c sentinel -- \
  redis-cli -p 26379 <AUTH_OPTION> sentinel get-master-addr-by-name mymaster
```

### 13.4 발표에 남길 값

| 발표 항목        | 기록값      |
| :--------------- | :---------- |
| Redis node count | 3           |
| Sentinel quorum  | 2           |
| usable Sentinels | 3           |
| failover time    | 초          |
| PVC type         | RBD RWO PVC |

### 13.5 발표 해석

- Redis Sentinel 3 nodes + quorum 2
- 1 node 장애 시 failover 가능
- failover 시험 없으면 "구성상 가능"으로 표현

---

## 14. Redis 기능/효과 확인

### 14.1 확인 목적

- Redis가 실제 queue/cache에 사용되는지 확인
- DB 부하 감소 지표 확보
- hit ratio와 DB connection 변화 비교

### 14.2 Redis key/command 확인

Redis:

```bash
redis-cli <AUTH_OPTION> INFO stats
redis-cli <AUTH_OPTION> INFO commandstats
redis-cli <AUTH_OPTION> INFO keyspace
redis-cli <AUTH_OPTION> --latency
```

### 14.3 Queue 기능 확인

앱 테스트:

```bash
curl -s <QUEUE_ENTER_API>
curl -s <QUEUE_STATUS_API>
```

Redis command 확인:

```bash
redis-cli <AUTH_OPTION> INFO commandstats | grep -E "lpush|rpop|llen"
```

### 14.4 Redis 유무 비교

테스트 전:

```bash
redis-cli <AUTH_OPTION> INFO stats | grep -E "keyspace_hits|keyspace_misses|total_commands_processed"
```

테스트:

```bash
k6 run <CACHE_ON_TEST>
k6 run <CACHE_OFF_TEST>
```

테스트 후:

```bash
redis-cli <AUTH_OPTION> INFO stats | grep -E "keyspace_hits|keyspace_misses|total_commands_processed"
```

DB/ProxySQL:

```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Questions';
```

### 14.5 발표에 남길 값

| 발표 항목       | 기록값          |
| :-------------- | :-------------- |
| total commands  | 전/후           |
| keyspace hits   | 전/후           |
| keyspace misses | 전/후           |
| hit ratio       | 계산값          |
| Redis latency   | ms              |
| DB connection   | Redis 없음/있음 |
| App p95 latency | Redis 없음/있음 |

### 14.6 hit ratio 계산

```text
hit_ratio = keyspace_hits / (keyspace_hits + keyspace_misses)
```

### 14.7 발표 해석

- hit ratio만으로 DB 부하 감소 단정 금지
- DB QPS 또는 connection 감소와 함께 제시
- queue는 LPUSH/RPOP/LLEN 증가로 설명
- Redis latency spike가 크면 cache 자체 병목 가능성 언급

---

## 15. Pod-to-Pod Network 참고 측정

### 15.1 확인 목적

- Calico/IPIP 경로가 1G보다 높은지 확인
- Redis/PXC/K8s 내부 통신 병목 여부 참고

### 15.2 실행 후보

테스트 Pod 2개:

```bash
kubectl run iperf-server --image=networkstatic/iperf3 --restart=Never -- -s
kubectl run iperf-client --image=networkstatic/iperf3 --restart=Never -- \
  -c <IPERF_SERVER_POD_IP> -t 30
```

정리:

```bash
kubectl delete pod iperf-server iperf-client
```

### 15.3 발표에 남길 값

| 발표 항목             | 기록값         |
| :-------------------- | :------------- |
| Pod-to-Pod throughput | Gbps           |
| CNI 경로              | Calico/IPIP 등 |

### 15.4 발표 해석

- 5Gbps 이상이면 일반 app/Redis traffic에는 충분하다고 설명 가능
- Ceph 10G 측정과 구분
- 참고값으로만 사용

---

## 16. 발표용 수치표 작성 순서

1. 기존 참고값 복사
2. 최신 재측정값 입력
3. 기존값과 차이 표시
4. 차이 원인 기록
5. 발표 가능 여부 결정
6. 캡처 파일명 연결
7. 민감 정보 마스킹 확인

### 16.1 최종 표 템플릿

| 영역   | 지표                       | 기존 참고값  | 최신 측정값 | 차이 원인 | 발표 여부 | 캡처 |
| :----- | :------------------------- | :----------- | :---------- | :-------- | :-------- | :--- |
| Ceph   | 10G network                | 9.4 Gbps     |             |           |           |      |
| Ceph   | RBD 1M seqwrite            | 35 MB/s      |             |           |           |      |
| Ceph   | RADOS 4K write             | 99 IOPS      |             |           |           |      |
| Ceph   | RBD 4K randwrite cache on  | 1,700 IOPS   |             |           |           |      |
| Ceph   | RBD 4K randwrite cache off | 100~200 IOPS |             |           |           |      |
| DB     | PXC node count             | 3            |             |           |           |      |
| DB     | Threads_connected          | 측정 필요    |             |           |           |      |
| Backup | object count match         | 측정 필요    |             |           |           |      |
| Redis  | Sentinel quorum            | quorum 2     |             |           |           |      |
| Redis  | usable Sentinels           | 3            |             |           |           |      |
| Redis  | failover time              | 약 30초      |             |           |           |      |
| Redis  | hit ratio                  | 측정 필요    |             |           |           |      |

---

## 17. 발표 전 최종 판정 기준

### 17.1 발표 가능

- 최신 캡처 존재
- 민감 정보 마스킹 완료
- 수치 의미 설명 가능
- 기존 참고값과 차이 원인 설명 가능
- 운영 영향 없는 검증 방식

### 17.2 발표 보류

- `HEALTH_ERR`
- PG not clean
- 성능 측정 중 운영 영향 발생
- 수치 출처 불명
- cache on/off 구분 불가
- DB backup restore 근거 없음
- Redis failover 시험 실패

### 17.3 발표 표현 조정

| 상황               | 표현                                      |
| :----------------- | :---------------------------------------- |
| 최신 재측정 완료   | "실측 결과"                               |
| 과거 문서값만 존재 | "기존 검증 기준 참고값"                   |
| 구성만 확인        | "구성상 가능"                             |
| 장애 시험 미수행   | "failover 검증은 추가 확인 필요"          |
| restore 미수행     | "백업 파일 존재, 복구 테스트는 후속 과제" |
