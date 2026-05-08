# 외부 Ceph 클러스터를 Proxmox RBD Storage로 연결하는 절차

이 문서는 `10.10.10.12`가 단순 RBD 클라이언트가 아니라, 별도 Ceph 클러스터의 노드(`ceph2`)인
상황에서 Proxmox 클러스터(`kosa1`~`kosa4`)가 해당 Ceph 클러스터의 RBD pool을 외부 Storage로 사용하는
절차를 정리한다.

파일에 포함된 명령은 실제 Proxmox/Ceph 장비에서 실행하는 기준이며, 현재 문서 저장소가 있는 로컬
PC에서 실행하는 절차가 아니다.

---

## 1. 구성 개념

```text
Proxmox Cluster
- kosa1, kosa2, kosa3, kosa4
- 예: 10.10.10.35~38 등

        RBD client 접속

External Ceph Cluster
- ceph1, ceph2, ceph3, ceph4
- ceph2 = 10.10.10.12
- MON 4개, OSD 12개, HEALTH_OK
```

현재 `10.10.10.12`의 상태 예시는 다음과 같다.

```text
cluster health: HEALTH_OK
mon: 4 daemons
mgr: ceph2 active
mds: 1/1 up
osd: 12 osds up/in
rgw: 1 daemon active
```

이 상태라면 RBD backend로 사용할 기본 조건은 양호하다.

---

## 2. Ceph 쪽에서 먼저 확인할 설정값

아래 명령은 `ceph1` 또는 `ceph2` 같은 Ceph 관리 노드에서 실행한다.

### 2.1 MON IP 확인

```bash
ceph mon dump
```

확인할 값:

- `mon.ceph1` IP
- `mon.ceph2` IP
- `mon.ceph3` IP
- `mon.ceph4` IP

Proxmox에서 RBD storage를 추가할 때 `--monhost`에 이 IP들을 넣는다.

예시:

```text
10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14
```

실제 값은 반드시 `ceph mon dump` 결과 기준으로 사용한다.

### 2.2 Ceph FSID 확인

```bash
ceph fsid
```

### 2.3 Ceph 네트워크 확인

```bash
ceph config get mon public_network
ceph config get global public_network
ceph config get global cluster_network
```

확인 기준:

- Proxmox가 접근할 수 있는 public network가 `10.10.10.0/24` 계열인지 확인
- `10.10.10.12`의 RBD 접근 인터페이스는 `bond0.10`, IP는 `10.10.10.12/24`
- MTU는 `9000` 기준으로 구성되어 있음

### 2.4 Ceph 전체 상태 확인

```bash
ceph -s
ceph osd tree
ceph osd stat
ceph df
```

정상 기준:

- `HEALTH_OK`
- OSD `up/in`
- PG `active+clean`

---

## 3. RBD pool 생성 및 초기화

팀별 pool 예시:

- `rbd-team1`
- `rbd-team2`
- `rbd-team3`
- `rbd-team4`

공식 Ceph RBD 권장 흐름은 다음 순서다.

1. Ceph pool 생성
2. pool application을 `rbd`로 연결
3. `rbd pool init <pool-name>`으로 RBD용 초기화

### 3.1 단일 pool 생성 예시

```bash
POOL=rbd-team1

ceph osd pool create ${POOL} 32
ceph osd pool application enable ${POOL} rbd
rbd pool init ${POOL}
```

이미 pool이 있을 수 있는 실습 환경에서는 다음처럼 사용할 수 있다.

```bash
POOL=rbd-team1

ceph osd pool create ${POOL} 32 || true
ceph osd pool application enable ${POOL} rbd || true
rbd pool init ${POOL} || true
```

### 3.2 팀별 pool 생성 스크립트 예시

```bash
#!/bin/bash
set -e

for TEAM in 1 2 3 4
 do
  POOL=rbd-team${TEAM}

  ceph osd pool create ${POOL} 32 || true
  ceph osd pool application enable ${POOL} rbd || true
  rbd pool init ${POOL} || true

done

ceph osd pool ls detail
```

주의:

- 기존 스크립트에서 `rbd pool init` 후 `ceph osd pool application enable`을 수행하고 있었다면, 공식
  절차와 맞추기 위해 application enable을 먼저 수행하는 편이 명확하다.
- `32` PG는 소규모 실습 기준 예시다. 운영 전에는 OSD 수, pool 수, 예상 사용량 기준으로 PG autoscaler
  또는 PG 계산기를 통해 재검토한다.

### 3.3 pool 확인

```bash
ceph osd pool ls detail | grep rbd-team
ceph osd pool application get rbd-team1
rbd pool stats rbd-team1
rbd ls rbd-team1
```

정상 기준:

- `rbd-team1` pool 존재
- application에 `rbd` 표시
- `rbd ls` 실행 가능

---

## 4. Proxmox용 Ceph client 계정 생성

Proxmox가 RBD pool에 접근할 전용 Ceph 계정을 만든다.

예: `rbd-team1` pool만 접근 가능한 `client.pve-team1`

```bash
ceph auth get-or-create client.pve-team1 \
  mon 'profile rbd' \
  osd 'profile rbd pool=rbd-team1' \
  mgr 'profile rbd pool=rbd-team1' \
  -o /etc/ceph/ceph.client.pve-team1.keyring
```

확인:

```bash
ceph auth get client.pve-team1
cat /etc/ceph/ceph.client.pve-team1.keyring
```

기대 형태:

```text
[client.pve-team1]
    key = ...
    caps mgr = "profile rbd pool=rbd-team1"
    caps mon = "profile rbd"
    caps osd = "profile rbd pool=rbd-team1"
```

보안 주의:

- keyring은 저장소에 커밋하지 않는다.
- 팀별로 pool을 나누는 경우 client도 팀별로 분리한다.
- Proxmox에 등록할 때 `username`은 `client.`를 제외한 값인 `pve-team1`을 사용한다.

---

## 5. Proxmox 노드에서 Ceph 접근 확인

Proxmox 노드 중 하나에서 먼저 네트워크를 확인한다.

예: `kosa3`

```bash
ping 10.10.10.12
ping -M do -s 8972 10.10.10.12
```

정상 기준:

- packet loss `0%`
- jumbo frame ping 응답 성공

Ceph client 명령 확인:

```bash
ceph --version
rbd --version
```

없으면 Proxmox 노드에서 설치한다.

```bash
apt update
apt install -y ceph-common
```

---

## 6. Ceph 설정 파일과 keyring 복사

Ceph 노드에서 Proxmox 노드로 `ceph.conf`와 keyring을 복사한다.

예: Ceph 노드에서 `kosa3`로 복사

```bash
scp /etc/ceph/ceph.conf root@10.10.10.37:/etc/ceph/ceph.conf
scp /etc/ceph/ceph.client.pve-team1.keyring root@10.10.10.37:/etc/ceph/
```

Proxmox 노드에서 권한 설정:

```bash
chmod 600 /etc/ceph/ceph.client.pve-team1.keyring
```

Proxmox 노드에서 Ceph 상태 조회 테스트:

```bash
ceph -n client.pve-team1 \
  -k /etc/ceph/ceph.client.pve-team1.keyring \
  -s
```

RBD pool 조회 테스트:

```bash
rbd -n client.pve-team1 \
  -k /etc/ceph/ceph.client.pve-team1.keyring \
  -p rbd-team1 ls
```

여기까지 성공하면 Proxmox 노드가 외부 Ceph RBD에 접근 가능한 상태다.

---

## 7. Proxmox에 외부 RBD Storage 추가

Proxmox 노드 하나에서 실행하면 `/etc/pve/storage.cfg`에 클러스터 공통으로 반영된다.

먼저 `ceph mon dump`에서 확인한 실제 MON IP들을 사용한다.

```bash
pvesm add rbd ceph-rbd-team1 \
  --monhost "10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14" \
  --pool rbd-team1 \
  --content images,rootdir \
  --username pve-team1 \
  --keyring /etc/ceph/ceph.client.pve-team1.keyring
```

옵션 설명:

- `ceph-rbd-team1`: Proxmox Storage ID
- `--monhost`: Ceph MON IP 목록
- `--pool`: 사용할 RBD pool
- `--content images,rootdir`: VM 디스크와 LXC rootdir 사용
- `--username pve-team1`: `client.`를 제외한 Ceph 사용자명
- `--keyring`: Proxmox 노드에 복사한 keyring 경로

VM 디스크만 사용할 경우:

```bash
--content images
```

LXC까지 사용할 경우:

```bash
--content images,rootdir
```

---

## 8. Proxmox 등록 확인

Proxmox 노드에서 확인:

```bash
pvesm status
pvesm config ceph-rbd-team1
cat /etc/pve/storage.cfg
```

정상 기준:

- `pvesm status`에 `ceph-rbd-team1` 표시
- storage type이 `rbd`
- pool이 `rbd-team1`
- monhost가 외부 Ceph MON IP로 표시

---

## 9. 최종 RBD 테스트

Proxmox에서 테스트 디스크를 생성한다.

```bash
pvesm alloc ceph-rbd-team1 999 vm-999-disk-0 1G
pvesm list ceph-rbd-team1
```

Ceph 쪽에서 확인:

```bash
rbd ls rbd-team1
rbd info rbd-team1/vm-999-disk-0
ceph -s
```

테스트 디스크 삭제:

```bash
pvesm free ceph-rbd-team1:vm-999-disk-0
```

---

## 10. 전체 진행 순서 요약

### 10.1 Ceph MON IP 확인

```bash
ceph mon dump
```

### 10.2 RBD pool 생성

```bash
ceph osd pool create rbd-team1 32
ceph osd pool application enable rbd-team1 rbd
rbd pool init rbd-team1
```

### 10.3 Proxmox용 client 생성

```bash
ceph auth get-or-create client.pve-team1 \
  mon 'profile rbd' \
  osd 'profile rbd pool=rbd-team1' \
  mgr 'profile rbd pool=rbd-team1' \
  -o /etc/ceph/ceph.client.pve-team1.keyring
```

### 10.4 Proxmox 노드로 설정 복사

```bash
scp /etc/ceph/ceph.conf root@10.10.10.37:/etc/ceph/ceph.conf
scp /etc/ceph/ceph.client.pve-team1.keyring root@10.10.10.37:/etc/ceph/
```

### 10.5 Proxmox에서 Ceph 조회 테스트

```bash
ceph -n client.pve-team1 -k /etc/ceph/ceph.client.pve-team1.keyring -s
rbd -n client.pve-team1 -k /etc/ceph/ceph.client.pve-team1.keyring -p rbd-team1 ls
```

### 10.6 Proxmox Storage 추가

```bash
pvesm add rbd ceph-rbd-team1 \
  --monhost "실제_MON_IP들" \
  --pool rbd-team1 \
  --content images,rootdir \
  --username pve-team1 \
  --keyring /etc/ceph/ceph.client.pve-team1.keyring
```

### 10.7 최종 확인

```bash
pvesm status
pvesm config ceph-rbd-team1
pvesm alloc ceph-rbd-team1 999 vm-999-disk-0 1G
pvesm list ceph-rbd-team1
pvesm free ceph-rbd-team1:vm-999-disk-0
```

---

## 11. 주의 사항

### 11.1 cleanup 스크립트 주의

현재 Ceph 장비에 있는 `00_cleanup_all.sh`는 pool, RGW 사용자, CephFS, auth 등을 삭제하는 위험한
스크립트다.

특히 아래 로직은 `.mgr`을 제외한 대부분의 pool을 삭제할 수 있다.

```bash
POOLS=$(ceph osd pool ls)

for p in $POOLS; do
  if [[ "$p" != ".mgr" ]]; then
    ceph osd pool delete $p $p --yes-i-really-really-mean-it || true
  fi
done
```

현재 클러스터가 `HEALTH_OK`이고 RGW/CephFS도 활성화되어 있으므로, 실수로 실행하지 않도록 파일명을
바꾸거나 별도 보관하는 것이 좋다.

### 11.2 keyring 관리

- `/etc/ceph/ceph.client.pve-team1.keyring`은 민감 정보다.
- Git 저장소에 커밋하지 않는다.
- Proxmox 노드에서는 `chmod 600` 권한을 적용한다.

### 11.3 MON IP는 실제 값 기준

문서의 `10.10.10.11`, `10.10.10.13`, `10.10.10.14`는 예시다.

반드시 아래 명령 결과 기준으로 입력한다.

```bash
ceph mon dump
```

### 11.4 Proxmox username 입력 주의

Ceph auth entity는 `client.pve-team1`이지만, Proxmox `pvesm add rbd`의 `--username`에는 보통
`client.`를 제외한 값을 입력한다.

```bash
--username pve-team1
```

---

## 12. 문제 발생 시 확인 명령

### Ceph 쪽

```bash
ceph -s
ceph health detail
ceph mon dump
ceph osd pool ls detail
ceph auth get client.pve-team1
rbd -p rbd-team1 ls
```

### Proxmox 쪽

```bash
ping 10.10.10.12
ping -M do -s 8972 10.10.10.12
ceph -n client.pve-team1 -k /etc/ceph/ceph.client.pve-team1.keyring -s
rbd -n client.pve-team1 -k /etc/ceph/ceph.client.pve-team1.keyring -p rbd-team1 ls
pvesm status
pvesm config ceph-rbd-team1
journalctl -xe
```
