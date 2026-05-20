# Ceph 검증 가이드

> Status: Unverified 목적: Ceph 클러스터 상태, 3-Replica, CRUSH 분산, 네트워크, RBD/PVC, RGW/Harbor
> 연동, 장애 내성을 검증함.

---

## 0. 검증 전 주의사항

- 장애 테스트(`systemctl stop ceph.target`, `shutdown now`)는 발표/운영 영향이 있으므로 반드시 팀
  동의 후 수행함.
- 운영 데이터가 있는 Pool, PVC, Bucket을 삭제하지 않음.
- RGW Access Key/Secret Key, Kubernetes Secret 값은 문서/저장소/채팅에 평문으로 남기지 않음.
- 명령 실행 위치를 구분함.
  - Ceph 노드: `ceph -s`, `radosgw-admin`, `rbd` 명령 실행
  - Bastion 또는 kubectl 가능 노드: `kubectl --context kubernetes-admin@kubernetes ...` 실행

---

## 1. Ceph 전체 상태 확인

### 목적

- Cluster 정상 여부 확인
- OSD/MON/MGR 상태 확인
- PG 상태 확인
- 경고 여부 확인

### 명령어

Ceph 노드에서 실행:

```bash
ceph -s
```

### 정상 기준

가장 좋은 상태:

```text
health: HEALTH_OK
```

`HEALTH_WARN`은 운영상 허용 가능한 경고일 수도 있지만, **정상으로 단정하지 않고 반드시 상세 원인을
확인**함.

```bash
ceph health detail
```

### 중요 확인 포인트

OSD:

```text
12 osds: 12 up, 12 in
```

- `up`: OSD 프로세스가 살아 있음
- `in`: OSD가 클러스터 데이터 배치에 참여 중

PG:

```text
active+clean
```

- 가장 중요한 정상 상태
- 데이터가 정상 배치되고 복구/재균형 작업이 없음을 의미

### 추가 상태 확인

`ceph -s`는 요약 화면이므로, 아래 명령으로 각 구성요소를 분리해서 확인함.

| 명령            | 확인할 수 있는 것                    | 정상/확인 기준                                                                              |
| :-------------- | :----------------------------------- | :------------------------------------------------------------------------------------------ |
| `ceph osd stat` | 전체 OSD 개수, `up/in` 상태          | `N osds: N up, N in` 형태여야 함. `down`, `out` OSD가 있으면 원인 확인                      |
| `ceph mon stat` | MON(Monitor) quorum 상태             | MON quorum에 필요한 노드가 참여 중이어야 함. quorum이 깨지면 클러스터 맵 합의 불가          |
| `ceph mgr stat` | 활성 MGR(Manager)와 standby MGR 상태 | `active` MGR 1개와 standby가 확인되면 좋음. MGR 장애 시 대시보드/메트릭/일부 관리 기능 영향 |
| `ceph df`       | 전체/Pool별 사용량, 가용 용량        | 특정 Pool 사용률이 과도하게 높거나 nearfull/full 경고가 없는지 확인                         |
| `ceph osd perf` | OSD별 apply/commit latency           | 특정 OSD의 지연이 다른 OSD보다 과도하게 높으면 디스크/네트워크/OSD 병목 의심                |

명령어:

```bash
ceph osd stat
ceph mon stat
ceph mgr stat
ceph df
ceph osd perf
```

확인 예시:

```text
# ceph osd stat
12 osds: 12 up, 12 in

# ceph mon stat
quorum ceph1,ceph2,ceph3

# ceph mgr stat
active: ceph1, standbys: ceph2, ceph3

# ceph osd perf
osd  commit_latency(ms)  apply_latency(ms)
0    1                   1
```

판단 기준:

- OSD는 `up`과 `in` 숫자가 전체 OSD 수와 일치해야 함.
- MON은 quorum이 유지되어야 함.
- MGR은 active가 있어야 하며, standby가 있으면 장애 전환에 유리함.
- `ceph df`에서 nearfull/full 경고가 없어야 함.
- `ceph osd perf`에서 특정 OSD만 latency가 높으면 해당 디스크/네트워크 상태를 추가 확인함.

---

## 2. 3-Replica 확인

### 목적

- 데이터 3중 복제 여부 확인
- 장애 허용 기준 확인

### 명령어

```bash
ceph osd pool ls detail
```

### 확인 포인트

```text
replicated size 3 min_size 2
```

의미:

| 항목         | 의미                                    |
| :----------- | :-------------------------------------- |
| `size 3`     | 데이터를 3개 replica로 저장             |
| `min_size 2` | replica 2개 이상이 살아 있으면 I/O 가능 |

> `min_size 2`는 장애 중에도 write 가능성을 높이지만, replica가 줄어든 상태에서는 추가 장애에
> 취약하므로 장기 운영 상태로 방치하지 않음.

### 특정 Pool 확인

Pool 이름은 환경마다 다를 수 있으므로 먼저 목록을 확인함.

```bash
ceph osd pool ls
ceph osd pool get <POOL_NAME> size
ceph osd pool get <POOL_NAME> min_size
```

예:

```bash
ceph osd pool get team2-k8s-pvc-rbd size
ceph osd pool get team2-k8s-pvc-rbd min_size
```

---

## 3. CRUSH 알고리즘 검증

### 목적

- Replica가 서로 다른 Host에 분산되는지 확인
- 장애 도메인(host) 단위 분산 구조 확인

### 명령어

```bash
ceph osd tree
ceph osd crush tree
```

### 확인 포인트

예:

```text
host ceph1
host ceph2
host ceph3
```

OSD가 여러 host 아래에 분산되어 있어야 함.

### 실제 placement 확인

특정 object가 어느 OSD에 배치되는지 확인하려면 다음을 사용함.

```bash
ceph osd map <POOL_NAME> <OBJECT_NAME>
```

예:

```bash
ceph osd map team2-k8s-pvc-rbd test-object
```

정상 기대:

```text
acting [1,5,8]
```

`acting` OSD들이 서로 다른 host에 위치하는지 `ceph osd tree`와 대조함.

### 결론 기준

- CRUSH map에 host bucket이 구성되어 있음
- replicated pool의 acting set이 host 단위로 분산됨
- 특정 host 장애 시에도 replica가 다른 host에 남음

---

## 4. Erasure Coding(EC) 사용 여부 확인

### 목적

- EC Pool 사용 여부 확인
- 현재 Pool이 Replica 기반인지 확인

### 명령어

```bash
ceph osd pool ls detail
```

### Replica Pool 예

```text
replicated size 3
```

### EC Pool이면 보이는 값

```text
erasure
```

또는:

```text
erasure_code_profile
```

### 현재 결론 작성 기준

- `replicated size 3`만 존재하면 Replica Pool 중심 구성으로 기록
- EC Pool이 있으면 해당 Pool의 용도, k/m 값, 장애 허용 범위를 별도 기록

---

## 5. 네트워크 구조 검증

### 목적

- Public/Cluster Network 분리 여부 확인
- Jumbo Frame 적용 여부 확인
- 10G NIC 또는 Bond 구성 확인

### Ceph Network 확인

```bash
cat /etc/ceph/ceph.conf
```

확인 예:

```ini
public_network = 10.10.10.0/24
cluster_network = 10.10.20.0/24
```

의미:

| 항목              | 역할                                          |
| :---------------- | :-------------------------------------------- |
| `public_network`  | Client traffic, RGW, Kubernetes/Ceph CSI 접근 |
| `cluster_network` | OSD replication, recovery, rebalance          |

### MTU 확인

```bash
ip a
```

확인 포인트:

```text
mtu 9000
```

### NIC 속도 확인

현재 `ceph2` 기준 인터페이스 구조는 다음과 같음.

| 인터페이스             | 역할                          | IP/상태                               | MTU  |
| :--------------------- | :---------------------------- | :------------------------------------ | :--- |
| `enp1s0f0`, `enp1s0f1` | 10G 물리 NIC, `bond0` slave   | `SLAVE, UP, LOWER_UP`                 | 9000 |
| `bond0`                | 10G Bond master               | `MASTER, UP, LOWER_UP`                | 9000 |
| `vmbr1`                | `bond0` 위 Proxmox bridge     | IP 없음, Ceph VLAN 상위 bridge        | 9000 |
| `bond0.10`             | Ceph public/client VLAN       | `10.10.10.12/24`                      | 9000 |
| `bond0.20`             | Ceph cluster/replication VLAN | `10.10.20.12/24`                      | 9000 |
| `vmbr0`, `eno1`        | 관리망 bridge/NIC             | `172.16.52.109/24`, 현재 `NO-CARRIER` | 1500 |

따라서 이 환경에서는 `bond0` 확인이 맞음. 다만 실제 물리 링크 상태까지 보려면 slave NIC도 함께
확인함.

```bash
ethtool bond0
ethtool enp1s0f0
ethtool enp1s0f1
```

Bond 구성 상세:

```bash
cat /proc/net/bonding/bond0
```

VLAN/MTU 확인:

```bash
ip -d link show bond0
ip -d link show bond0.10
ip -d link show bond0.20
ip -d link show vmbr1
```

확인 포인트:

```text
Speed: 10000Mb/s
Link detected: yes
mtu 9000
```

판단 기준:

- `bond0`, `enp1s0f0`, `enp1s0f1` 모두 10G 링크로 인식되어야 함.
- `bond0.10`과 `bond0.20`이 각각 `10.10.10.0/24`, `10.10.20.0/24`에 있어야 함.
- Ceph public/cluster network 경로의 MTU가 모두 9000이어야 함.
- `vmbr0`/`eno1`은 Ceph 10G 경로가 아니므로 10G 검증 대상이 아님.

### 네트워크 검증 기준

- Ceph client/public traffic과 replication traffic이 분리되어 있음
- Ceph 전용 NIC 또는 Bond에 MTU 9000 적용
- 모든 관련 노드의 MTU가 일관됨
- 10G 링크가 정상 협상됨

---

## 6. Harbor + Ceph RGW 연동 검증

### 목적

- Harbor가 Ceph RGW(S3 API)를 registry backend로 사용하는지 확인
- RGW bucket 접근 가능 여부 확인

### Harbor Secret 확인

Bastion 또는 kubectl 가능 노드에서:

```bash
kubectl --context kubernetes-admin@kubernetes get secret -n harbor
```

확인 포인트:

```text
harbor-s3-secret
```

### Harbor Pod 확인

```bash
kubectl --context kubernetes-admin@kubernetes get pod -n harbor
```

### RGW Bucket 확인

Ceph 노드에서:

```bash
radosgw-admin bucket list
```

예상 bucket:

```text
harbor-registry
```

### S3 환경변수 확인

Harbor core pod 이름 확인 후:

```bash
kubectl --context kubernetes-admin@kubernetes -n harbor get pod | grep harbor-core
kubectl --context kubernetes-admin@kubernetes -n harbor exec -it <HARBOR_CORE_POD> -- env | grep -i s3
```

### Secret 상세 확인

```bash
kubectl --context kubernetes-admin@kubernetes get secret harbor-s3-secret -n harbor -o yaml
```

Base64 decode는 필요한 키만 로컬에서 확인하고, 결과를 저장하지 않음.

```bash
echo '<BASE64_VALUE>' | base64 -d
```

확인 포인트:

| 항목       | 기대값                                        |
| :--------- | :-------------------------------------------- |
| endpoint   | `http://<RGW_IP>:7480` 또는 내부 RGW endpoint |
| bucket     | `harbor-registry`                             |
| access key | Secret에 존재                                 |
| secret key | Secret에 존재                                 |

### RGW S3 API 직접 검증

```bash
AWS_ACCESS_KEY_ID=<ACCESS_KEY> \
AWS_SECRET_ACCESS_KEY=<SECRET_KEY> \
AWS_DEFAULT_REGION=default \
aws s3 ls --endpoint-url http://<RGW_IP>:7480
```

---

## 7. RBD 검증

### 목적

- Kubernetes PVC가 Ceph RBD를 사용하는지 확인
- 실제 RBD Image와 PV/PVC 매핑을 확인

### Pool 목록

Ceph 노드에서:

```bash
ceph osd pool ls
ceph osd pool ls detail | grep application
```

확인 예:

```text
application rbd
team2-k8s-pvc-rbd
```

### 실제 RBD Image 확인

```bash
rbd ls -p team2-k8s-pvc-rbd
rbd info -p team2-k8s-pvc-rbd <IMAGE_NAME>
```

### Kubernetes PVC/PV 확인

```bash
kubectl --context kubernetes-admin@kubernetes get pvc -A
kubectl --context kubernetes-admin@kubernetes get pv
kubectl --context kubernetes-admin@kubernetes describe pv <PV_NAME>
```

확인 포인트:

```text
rbd.csi.ceph.com
```

또는:

```text
csi-rbdplugin
```

---

## 8. RBD 영속성 테스트

### 목적

- Pod 삭제/재생성 후에도 RBD PVC 데이터가 유지되는지 확인

### 8.1 StorageClass 확인

```bash
kubectl --context kubernetes-admin@kubernetes get sc
```

`storageClassName`은 실제 출력값에 맞춤. 아래 예시는 `ceph-rbd` 기준임.

### 8.2 테스트 Namespace 생성

```bash
kubectl --context kubernetes-admin@kubernetes create namespace ceph-validation
```

### 8.3 PVC 생성

`pvc-test.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rbd-test-pvc
  namespace: ceph-validation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
```

적용:

```bash
kubectl --context kubernetes-admin@kubernetes apply -f pvc-test.yaml
kubectl --context kubernetes-admin@kubernetes -n ceph-validation get pvc
```

### 8.4 Pod 생성

`pod-test.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rbd-test-pod
  namespace: ceph-validation
spec:
  containers:
    - name: test
      image: busybox
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - mountPath: /data
          name: rbd-storage
  volumes:
    - name: rbd-storage
      persistentVolumeClaim:
        claimName: rbd-test-pvc
```

적용:

```bash
kubectl --context kubernetes-admin@kubernetes apply -f pod-test.yaml
kubectl --context kubernetes-admin@kubernetes -n ceph-validation get pod -o wide
```

### 8.5 데이터 생성

```bash
kubectl --context kubernetes-admin@kubernetes -n ceph-validation exec -it rbd-test-pod -- sh
```

Pod 내부:

```bash
echo "hello-ceph" > /data/test.txt
cat /data/test.txt
exit
```

### 8.6 Pod 삭제 후 재생성

```bash
kubectl --context kubernetes-admin@kubernetes -n ceph-validation delete pod rbd-test-pod
kubectl --context kubernetes-admin@kubernetes apply -f pod-test.yaml
```

### 8.7 데이터 유지 확인

```bash
kubectl --context kubernetes-admin@kubernetes -n ceph-validation exec -it rbd-test-pod -- cat /data/test.txt
```

정상 결과:

```text
hello-ceph
```

### 8.8 정리

```bash
kubectl --context kubernetes-admin@kubernetes delete namespace ceph-validation
```

---

## 9. RGW 검증

### 목적

- Ceph RGW 데몬과 S3 API 정상 동작 확인
- Harbor/Thanos 같은 S3 클라이언트가 사용할 endpoint 검증

### RGW endpoint 확인

Ceph 노드 또는 RGW 접근 가능한 노드에서:

```bash
curl -I http://10.10.10.11:7480
```

정상 예:

```text
HTTP/1.1 200 OK
Server: Ceph Object Gateway
```

### RGW daemon 위치 확인

cephadm 환경:

```bash
ceph orch ps | grep rgw
ceph orch ls | grep rgw
```

systemd 환경:

```bash
systemctl list-units | grep -E 'rgw|radosgw'
ss -ntlp | grep 7480
```

### Bucket 목록 확인

```bash
radosgw-admin bucket list
```

### S3 API 확인

```bash
AWS_ACCESS_KEY_ID=<ACCESS_KEY> \
AWS_SECRET_ACCESS_KEY=<SECRET_KEY> \
AWS_DEFAULT_REGION=default \
aws s3 ls --endpoint-url http://10.10.10.11:7480
```

> AWS/EKS에서 RGW를 사용할 때는 `10.10.10.11`을 직접 라우팅하지 않고, 필요 시 MetalLB bridge
> IP(`172.16.23.x`)를 사용함.

---

## 10. 무중단 장애 테스트

### 목적

- Ceph node 1대 장애 시 서비스 유지 여부 확인
- 3-Replica와 CRUSH host 분산 효과 검증

### 사전 조건

- `ceph -s`가 `HEALTH_OK` 또는 원인이 명확한 경미한 WARN 상태
- 모든 PG가 `active+clean`
- 테스트 대상 node가 MON quorum을 깨지 않는지 확인
- Harbor/RBD/RGW 사용자에게 영향 가능성을 공지

### 현재 상태 확인

```bash
ceph -s
ceph osd tree
```

### 장애 유발 방법

강한 테스트:

```bash
systemctl stop ceph.target
```

또는 node 전원 종료:

```bash
shutdown now
```

> 위 명령은 해당 node의 Ceph 데몬을 중단하므로 실제 운영 중에는 신중히 수행함.

### 상태 확인

다른 Ceph node에서:

```bash
ceph -s
ceph health detail
```

예상 상태:

```text
HEALTH_WARN
degraded
```

정상 기대:

- 클러스터가 완전히 중단되지 않음
- OSD 일부 down/out 또는 degraded 상태가 표시됨
- PVC를 사용하는 Pod가 계속 동작하거나, 영향 범위가 제한됨
- RGW endpoint 접근이 유지되거나, 단일 RGW 구성이라면 RGW SPOF 위험이 확인됨

### Kubernetes 확인

```bash
kubectl --context kubernetes-admin@kubernetes get pod -A -o wide
kubectl --context kubernetes-admin@kubernetes get pvc -A
```

### 복구

중단한 node에서:

```bash
systemctl start ceph.target
```

복구 확인:

```bash
ceph -s
ceph health detail
```

최종 기대:

```text
active+clean
HEALTH_OK
```

---

## 11. 검증 결과 기록 양식

| 항목            | 결과      | 근거/출력                       | 비고 |
| :-------------- | :-------- | :------------------------------ | :--- |
| `ceph -s`       | Pass/Fail | `HEALTH_OK`, `active+clean`     |      |
| OSD 상태        | Pass/Fail | `N up, N in`                    |      |
| 3-Replica       | Pass/Fail | `size 3 min_size 2`             |      |
| CRUSH host 분산 | Pass/Fail | `ceph osd tree`, `ceph osd map` |      |
| RBD PVC         | Pass/Fail | PVC Bound, PV CSI driver        |      |
| RBD 영속성      | Pass/Fail | `hello-ceph` 유지               |      |
| RGW S3 API      | Pass/Fail | `aws s3 ls` 성공                |      |
| Harbor RGW 연동 | Pass/Fail | bucket/secret/env 확인          |      |
| 장애 테스트     | Pass/Fail | degraded 후 복구                |      |
