# RGW Endpoint 고정 및 Team2 S3 테스트 가이드

Team2 기준으로 RGW endpoint를 고정하고 S3 동작을 검증하는 절차를 정리함.

---

## 1. 목적

- RGW endpoint를 단일 기준으로 고정해 운영 혼선을 줄임
- Team2 계정으로 S3 API 업로드/조회 동작을 검증함
- 이후 HTTPS 전환 전에 최소 동작 경로를 확정함

---

## 2. 현재 상태 요약

- CephFS는 정상(`ceph fs ls`, `ceph fs status`, `ceph mds stat` 확인)
- `ceph2`에는 `radosgw` 바이너리가 없음 (`/usr/bin/radosgw` 미존재)
- RGW는 `ceph1` 단일 데몬으로 동작 중
- `ceph1`에서 `172.16.53.110:7480`, `10.10.10.11:7480` 모두 응답 확인
- `ceph2`에서도 `10.10.10.11:7480` 응답 확인

---

## 3. RGW endpoint 고정 절차

> 실행 위치: `ceph1`

```bash
radosgw-admin zonegroup modify \
  --rgw-zonegroup=default \
  --endpoints=http://10.10.10.11:7480

radosgw-admin zone modify \
  --rgw-zone=default \
  --endpoints=http://10.10.10.11:7480

radosgw-admin period update --commit
```

검증:

```bash
radosgw-admin period get | grep -A3 endpoints
```

기준:

- zonegroup/zone endpoint가 모두 `http://10.10.10.11:7480`로 표시되어야 함

---

## 4. 네트워크 접근 검증

> 실행 위치: `ceph1`, `ceph2` 모두

```bash
curl -I http://10.10.10.11:7480
```

기준:

- `HTTP/1.1 200 OK`
- `Server: Ceph Object Gateway (squid)`

---

## 5. Team2 S3 테스트

> 실행 위치: AWS CLI가 설치된 테스트 노드

```bash
export AWS_ACCESS_KEY_ID="<TEAM2_ACCESS_KEY>"
export AWS_SECRET_ACCESS_KEY="<TEAM2_SECRET_KEY>"
export AWS_DEFAULT_REGION="us-east-1"
export RGW_EP="http://10.10.10.11:7480"

aws --endpoint-url=$RGW_EP s3 ls
aws --endpoint-url=$RGW_EP s3 mb s3://team2-bucket || true

echo "team2-test $(date)" > team2-test.txt
aws --endpoint-url=$RGW_EP s3 cp team2-test.txt s3://team2-bucket/
aws --endpoint-url=$RGW_EP s3 ls s3://team2-bucket

aws --endpoint-url=$RGW_EP s3 cp s3://team2-bucket/team2-test.txt ./team2-test-down.txt
cat team2-test-down.txt
```

기준:

- 버킷 생성/조회 성공
- 업로드/다운로드 파일 내용 일치

---

## 6. 키 회전 가이드(추후)

```bash
# 1) 새 키 발급
radosgw-admin key create --uid=team2-admin --key-type=s3

# 2) 새 키 확인
radosgw-admin user info --uid=team2-admin

# 3) 앱/CI Secret 교체 후, 기존 키 삭제
radosgw-admin key rm --uid=team2-admin --access-key <OLD_ACCESS_KEY>
```

운영 메모:

- 키 교체 시점에는 앱/CI의 Secret을 먼저 새 키로 교체한 뒤 구 키를 제거함

---

## 7. HTTPS 전환(현 단계 제외)

현 단계는 HTTP endpoint 동작 검증까지만 수행함. HTTPS는 이후 단계에서 아래 둘 중 하나로 전환함.

- 방법 A: HAProxy 앞단 TLS 종료(권장)
- 방법 B: RGW 자체 TLS 설정

---

## 8. 현 시점에서 이어서 진행할 작업

1. `ceph1`에서 endpoint 고정 명령 실행
2. `period get`으로 endpoint 고정 결과 확인
3. `ceph1/ceph2`에서 `curl -I http://10.10.10.11:7480` 재확인
4. Team2 S3 업로드/다운로드 테스트 실행
5. 테스트 완료 후 팀 문서에 endpoint/버킷명/검증 결과 캡처 정리
6. 다음 단계에서 HTTPS 전환 방식(A/B) 확정
