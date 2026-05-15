# TS-05 ceph-endpoint-ip-mismatch

- Status: **Resolved**
- Date: 2026-05-15

## 증상

- Ceph RGW endpoint 호출 시 timeout 또는 연결 실패 발생
- FlaskApp S3 업로드/조회가 실패함

## 원인

- endpoint가 과거 네트워크 대역(`172.16.x.x`)으로 설정되어 있었음
- 실제 Ceph public network는 `10.10.10.x` 대역으로 운영 중이었음

## 해결

- `S3_ENDPOINT_URL` 및 RGW endpoint를 `10.10.10.11:7480` 기준으로 정렬함
- 앱/테스트 환경변수도 동일 대역으로 갱신함

## 검증

```bash
curl -I http://10.10.10.11:7480
python - <<'PY'
import os, boto3
from botocore.config import Config
s3=boto3.client('s3',endpoint_url=os.environ['S3_ENDPOINT_URL'],region_name=os.environ.get('S3_REGION','default'),aws_access_key_id=os.environ['S3_ACCESS_KEY'],aws_secret_access_key=os.environ['S3_SECRET_KEY'],config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))
print(s3.list_buckets())
PY
```
