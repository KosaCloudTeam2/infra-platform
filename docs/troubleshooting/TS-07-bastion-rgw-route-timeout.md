# TS-07 bastion-rgw-route-timeout

- Status: **Resolved**
- Date: 2026-05-15

## 증상

- Bastion VM에서 `10.10.10.11:7480` 접속 timeout
- Ceph 클러스터 자체는 HEALTH_OK인데 S3 테스트만 실패

## 원인

- Ceph NIC 인터페이스명이 `eth1`에서 `ens19`로 변경되었는데, netplan/라우팅 설정이 구 인터페이스
  기준으로 남아 있었음

## 해결

- Bastion VM에 Ceph 네트워크 NIC(`vmbr1`)를 추가
- netplan 설정을 실제 인터페이스명(`ens19`) 기준으로 수정 후 apply

## 검증

```bash
ip a
ip route
curl -I http://10.10.10.11:7480
```

- 이후 `S3 put_object OK`, `DB write OK` 확인
