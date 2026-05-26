# Ceph Settings

Ceph 초기 설정용 스크립트 모음.

- 목적: 팀별 블록 스토리지(RADOS Block Device/RBD) pool, 파일 시스템(Ceph File System/CephFS),
  오브젝트 게이트웨이(RADOS Gateway/RGW/S3), S3 user/bucket 생성
- 실행 위치: Ceph admin keyring과 Ceph CLI 사용 가능한 Ceph node
- 대상 환경: bash, systemd, `ceph`, `rbd`, `radosgw-admin`, `jq`, `aws` CLI 사용 가능 환경
- 주의: 운영 자동화 스크립트가 아니라 초기 구축/실습용 스크립트

## 파일 구성

| 파일                     | 역할                     | 생성/변경 대상                                                                    | 주의                                     |
| ------------------------ | ------------------------ | --------------------------------------------------------------------------------- | ---------------------------------------- |
| `00_cleanup_all.sh`      | Ceph 설정 초기화         | RGW process/service, RGW user, pool, CephFS, RGW auth/config 삭제                 | 전체 pool 삭제 포함. 운영 환경 실행 금지 |
| `01_create_rbd_pools.sh` | 팀별 RBD pool 생성       | `rbd-team1` ~ `rbd-team4`, PG 32, RBD application enable                          | 기존 pool 존재 시 실패 가능              |
| `02_create_cephfs.sh`    | CephFS 생성              | `cephfs_metadata`, `cephfs_data`, filesystem `cephfs`                             | 기존 CephFS/pool 존재 시 실패 가능       |
| `03_create_rgw.sh`       | RGW S3 endpoint 생성     | RGW auth keyring, default realm/zonegroup/zone, endpoint `:7480`, systemd service | host IP 첫 번째 값 사용                  |
| `04_create_s3_users.sh`  | 팀별 S3 user/bucket 생성 | `team1-admin` ~ `team4-admin`, `team1-bucket` ~ `team4-bucket`                    | access/secret key 출력. 외부 공유 금지   |
| `s3-users/template.txt`  | S3 접속 정보 기록 템플릿 | user, access key, secret key, endpoint, region, bucket                            | 실제 secret 입력본 commit 금지           |

## 실행 순서

초기 생성 기준.

```bash
cd ceph-settings
bash 01_create_rbd_pools.sh
bash 02_create_cephfs.sh
bash 03_create_rgw.sh
bash 04_create_s3_users.sh
```

전체 초기화가 필요한 경우.

```bash
cd ceph-settings
bash 00_cleanup_all.sh
```

## 스크립트별 상세

### `00_cleanup_all.sh`

- 목적: Ceph test 설정 초기화
- 수행 작업:
  - `radosgw` process 강제 종료
  - `ceph-radosgw@ceph1` service stop/disable
  - 전체 RGW user 삭제 및 data purge
  - `.mgr` 제외 전체 pool 삭제
  - `cephfs` filesystem 및 CephFS pool 삭제
  - `client.rgw.ceph1` auth/config 삭제
  - `/etc/systemd/system/ceph-radosgw@.service` 삭제
- 위험도: 매우 높음
- 주의:
  - 모든 pool 삭제 가능성
  - S3 user data purge 포함
  - 현재 cleanup 대상 RGW 이름이 `ceph1`로 고정
  - `03_create_rgw.sh`는 실제 hostname 기준 service 생성
  - cleanup 실행 전 실제 RGW hostname 확인 필요

### `01_create_rbd_pools.sh`

- 목적: 팀별 RBD(Block Device) pool 생성
- 생성 대상:
  - `rbd-team1`
  - `rbd-team2`
  - `rbd-team3`
  - `rbd-team4`
- 주요 작업:
  - `ceph osd pool create ${POOL} 32`
  - `rbd pool init ${POOL}`
  - `ceph osd pool application enable ${POOL} rbd`
- 확인 명령:

```bash
ceph osd pool ls detail
rbd pool stats rbd-team2
```

### `02_create_cephfs.sh`

- 목적: CephFS(File System) 생성
- 생성 대상:
  - metadata pool: `cephfs_metadata`
  - data pool: `cephfs_data`
  - filesystem: `cephfs`
- 주요 작업:
  - metadata pool PG 32
  - data pool PG 64
  - `ceph fs new cephfs cephfs_metadata cephfs_data`
- 확인 명령:

```bash
ceph fs ls
ceph osd pool ls | grep cephfs
```

### `03_create_rgw.sh`

- 목적: RGW(RADOS Gateway) S3 endpoint 구성
- 생성 대상:
  - `client.rgw.${HOST}` auth keyring
  - default realm
  - default zonegroup
  - default zone
  - RGW endpoint `http://${IP}:7480`
  - systemd service `ceph-radosgw@${HOST}`
- endpoint 산정:
  - `HOST=$(hostname -s)`
  - `IP=$(hostname -I | awk '{print $1}')`
- 확인 명령:

```bash
systemctl status ceph-radosgw@$(hostname -s)
ss -tulnp | grep 7480
radosgw-admin realm list
radosgw-admin zonegroup list
radosgw-admin zone list
```

### `04_create_s3_users.sh`

- 목적: 팀별 S3 user와 bucket 생성
- 생성 대상:
  - user: `team1-admin` ~ `team4-admin`
  - bucket: `team1-bucket` ~ `team4-bucket`
- 주요 작업:
  - `radosgw-admin user create`
  - `radosgw-admin user info`에서 access/secret key 추출
  - AWS CLI로 RGW endpoint에 bucket 생성
- 확인 명령:

```bash
radosgw-admin user list
radosgw-admin bucket list
aws --endpoint-url=http://$(hostname -I | awk '{print $1}'):7480 s3 ls
```

## 사전 확인

실행 전 확인 항목.

```bash
ceph status
ceph osd tree
ceph osd pool ls
which ceph rbd radosgw-admin jq aws
hostname -s
hostname -I
```

확인 기준.

- Ceph cluster 접근 가능
- admin 권한 keyring 존재
- OSD 상태 정상
- `jq`, `aws` CLI 설치
- RGW endpoint port `7480` 사용 가능

## 보안 주의

- `04_create_s3_users.sh` 실행 결과에 access key와 secret key 출력
- 실제 key가 입력된 파일 commit 금지
- `s3-users/template.txt`는 빈 템플릿만 유지
- 공유 필요 시 secret manager 또는 별도 안전 채널 사용

## 운영 주의

- `00_cleanup_all.sh`는 운영 환경 실행 금지
- pool 삭제 전 snapshot, backup, 사용자 데이터 존재 여부 확인
- RGW service 이름은 실제 hostname 기준 확인
- bucket/user 재생성 시 기존 application 연결 정보 영향 확인
- 운영 자동화 전 idempotency, error handling, dry-run 절차 보강 필요
