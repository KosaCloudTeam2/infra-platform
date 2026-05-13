# Team2 RGW/S3 설정 및 등록 가이드 (AWS CLI 미사용)

Team2 기준으로 RGW endpoint를 고정하고, **AWS CLI 없이** `radosgw-admin` + `python(boto3)`로 Ceph S3
동작을 검증하는 절차임.

---

## 1. 목적

- RGW endpoint 단일 기준 고정
- Team2 S3 사용자/버킷 준비
- Python(boto3)로 업로드/다운로드 검증
- FlaskApp에서 Ceph S3 연동 확인

---

## 2. 실행 위치

- Ceph 제어 명령: `ceph1`
- S3 데이터 동작 테스트: `python3` + `boto3`가 있는 노드(예: FlaskApp 테스트 노드)

---

## 3. 테스트 VM 네트워크 준비 (Proxmox + Ubuntu)

S3 검증을 Bastion/테스트 VM에서 수행할 때, Ceph 망(`10.10.10.0/24`)으로 접근 가능한 NIC를 추가함.

### 3.1 Proxmox UI에서 NIC 추가

경로:

```text
Proxmox UI -> 대상 VM 선택 -> Hardware -> Add -> Network Device
```

설정값(예시):

- Bridge: `vmbr1` (Ceph망)
- Model: `VirtIO`
- VLAN tag: 없음(환경에서 `vmbr1`이 Ceph 전용 브리지인 경우)

> 권장: VM 종료 후 NIC 추가/부팅 (hot-add 가능하지만 안정성 우선)

### 3.2 Ubuntu(netplan)에서 IP 설정

기존 관리망 NIC(`eth0`)는 유지하고, Ceph망 NIC(`eth1`)를 추가함.

```yaml
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: "bc:24:11:ab:f0:1f"
      set-name: "eth0"
      addresses:
        - "172.16.24.10/24"
      routes:
        - to: "default"
          via: "172.16.24.1"
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
        search: [team2]

    eth1:
      addresses:
        - "10.10.10.100/24"
      mtu: 9000
```

적용:

```bash
sudo netplan try
sudo netplan apply
ip -br addr
ip route
```

### 3.3 Ceph RGW 접근 확인

```bash
curl -I http://10.10.10.11:7480
```

정상 기준:

- `HTTP/1.1 200 OK`

---

## 4. RGW 기본 상태 확인

```bash
ceph -s
curl -I http://10.10.10.11:7480
radosgw-admin realm list
radosgw-admin zonegroup list
radosgw-admin zone list
```

정상 기준:

- `ceph -s`에 `rgw: 1 daemon active`
- `curl` 응답 `HTTP/1.1 200 OK`

---

## 5. RGW endpoint 고정 (필요 시)

먼저 현재 endpoint 확인:

```bash
radosgw-admin period get | grep -A3 endpoints
```

- 이미 `http://10.10.10.11:7480`이면 **고정 작업 생략**
- 다르면 아래 실행:

```bash
radosgw-admin zonegroup modify \
  --rgw-zonegroup=default \
  --endpoints=http://10.10.10.11:7480

radosgw-admin zone modify \
  --rgw-zone=default \
  --endpoints=http://10.10.10.11:7480

radosgw-admin period update --commit
```

재확인:

```bash
radosgw-admin period get | grep -A3 endpoints
```

---

## 6. Region/Location 기준 확인 (중요)

`api_name`이 버킷 `LocationConstraint` 기준이므로 먼저 확인:

```bash
radosgw-admin zonegroup get --rgw-zonegroup=default
```

확인 포인트:

- `api_name: "default"`이면 버킷 생성 시 location은 `default`를 사용
- 문서/스크립트에서 `us-east-1` 고정 사용하지 않음

---

## 7. Team2 S3 사용자 등록/확인

```bash
radosgw-admin user create --uid=team2-admin --display-name="Team2 Admin" || true
radosgw-admin user info --uid=team2-admin
```

출력의 `access_key`, `secret_key`를 아래 Python 테스트에 사용.

---

## 8. 버킷 생성 + S3 동작 검증 (Python/boto3)

### 7.1 실행 전 환경변수

```bash
export S3_ENDPOINT_URL="http://10.10.10.11:7480"
export S3_ACCESS_KEY="<TEAM2_ACCESS_KEY>"
export S3_SECRET_KEY="<TEAM2_SECRET_KEY>"
export S3_REGION="default"
export S3_LOCATION_CONSTRAINT="default"
export BUCKET="team2-photo-bucket"
```

### 7.2 테스트 스크립트 실행

```bash
python3 - <<'PY'
import os, datetime
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

endpoint = os.environ['S3_ENDPOINT_URL']
access_key = os.environ['S3_ACCESS_KEY']
secret_key = os.environ['S3_SECRET_KEY']
region = os.environ.get('S3_REGION', 'default')
location = os.environ.get('S3_LOCATION_CONSTRAINT', 'default')
bucket = os.environ.get('BUCKET', 'team2-photo-bucket')

s3 = boto3.client(
    's3',
    endpoint_url=endpoint,
    region_name=region,
    aws_access_key_id=access_key,
    aws_secret_access_key=secret_key,
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)

# 버킷 존재 확인 -> 없으면 생성
exists = True
try:
    s3.head_bucket(Bucket=bucket)
except ClientError:
    exists = False

if not exists:
    s3.create_bucket(
        Bucket=bucket,
        CreateBucketConfiguration={'LocationConstraint': location}
    )

# put/get 검증
key = 'team2-test.txt'
body = f"team2-test {datetime.datetime.utcnow().isoformat()}".encode()
s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType='text/plain')
obj = s3.get_object(Bucket=bucket, Key=key)
downloaded = obj['Body'].read()
assert downloaded == body, '업로드/다운로드 불일치'

print('OK: bucket/head/create/put/get 검증 완료')
PY
```

---

## 9. FlaskApp 연동 테스트 (DynamoDB 미사용)

FlaskApp은 `DYNAMO_MODE`가 설정되면 Dynamo 경로를 타므로, Dynamo를 안 쓸 경우 반드시 해제해야 함.
또한 `DYNAMO_MODE`를 끄면 MySQL 경로를 사용하므로 `DATABASE_*` 값이 필요함.

### 8.1 앱 준비

```bash
cd FlaskApp
pip install -r requirements.txt
```

### 8.2 S3 endpoint 반영 코드(필수)

현재 `application.py`의 `boto3.client('s3')` 호출(4곳)을 아래 팩토리 함수로 교체:

```python
from botocore.config import Config
import os


def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=os.environ.get('S3_ENDPOINT_URL'),
        region_name=os.environ.get('S3_REGION', 'default'),
        aws_access_key_id=os.environ.get('S3_ACCESS_KEY'),
        aws_secret_access_key=os.environ.get('S3_SECRET_KEY'),
        config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
    )
```

그리고 `boto3.client('s3')` -> `get_s3_client()`로 변경.

### 8.3 실행 환경변수

```bash
export PHOTOS_BUCKET="team2-photo-bucket"
export S3_ENDPOINT_URL="http://10.10.10.11:7480"
export S3_ACCESS_KEY="<TEAM2_ACCESS_KEY>"
export S3_SECRET_KEY="<TEAM2_SECRET_KEY>"
export S3_REGION="default"

# DynamoDB 미사용
unset DYNAMO_MODE

# MySQL(Percona/ProxySQL) 사용
export DATABASE_HOST="<DB_HOST>"
export DATABASE_USER="<DB_USER>"
export DATABASE_PASSWORD="<DB_PASSWORD>"
export DATABASE_DB_NAME="<DB_NAME>"

FLASK_APP=application.py /usr/local/bin/flask run --host=0.0.0.0 --port=80
```

검증:

- `/add`에서 이미지 포함 사용자 저장
- 버킷 `team2-photo-bucket`에 `employee_pic/*.png` 객체 생성 확인
- 목록/상세 화면 이미지 렌더링 확인

---

## 10. 키 회전 가이드(추후)

```bash
radosgw-admin key create --uid=team2-admin --key-type=s3
radosgw-admin user info --uid=team2-admin
radosgw-admin key rm --uid=team2-admin --access-key <OLD_ACCESS_KEY>
```

---

## 11. 다음 작업

1. endpoint 고정 결과 캡처/기록
2. `api_name` 기준(region/location) 팀 표준값 확정
3. FlaskApp `get_s3_client()` 코드 반영 커밋
4. 버킷 정책(공개 금지, 필요 CIDR만 허용) 적용
5. HTTPS 전환 방식(HAProxy TLS 종료 vs RGW TLS) 확정
