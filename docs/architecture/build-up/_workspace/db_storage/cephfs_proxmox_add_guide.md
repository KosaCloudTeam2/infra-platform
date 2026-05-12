# CephFS Proxmox UI 등록 가이드 (Team2)

Team2 기준으로 CephFS를 Proxmox Storage에 추가하는 절차를 정리함.

---

## 1. 목적

- CephFS 파일시스템(`cephfs`)을 Proxmox UI에서 Storage로 등록
- Team2 전용 계정(`client.cephfs-team2`)으로 접근 권한 분리

---

## 2. 사전 확인

```bash
ceph fs ls
ceph fs status
ceph mds stat
ceph mon dump
```

확인 기준:

- FS Name: `cephfs`
- MDS 상태: `up:active`
- Monitor IP 목록 확인 가능

---

## 3. Team2 CephFS 사용자 생성

```bash
ceph auth get-or-create client.cephfs-team2 \
  mon 'allow r' \
  mds 'allow rw path=/' \
  osd 'allow rw tag cephfs data=cephfs'

ceph auth get-key client.cephfs-team2
```

- `get-key` 출력값은 Proxmox UI `Secret Key`에 입력함.

---

## 4. Proxmox UI 등록

경로:

```text
Datacenter -> Storage -> Add -> CephFS
```

입력값(Team2 권장):

- **ID**: `cephfs-team2`
- **Monitor(s)**: `10.10.10.11;10.10.10.12;10.10.10.13;10.10.10.14` (환경에 맞게)
- **User name**: `cephfs-team2` (`client.` 제외)
- **FS Name**: `cephfs`
- **Secret Key**: `ceph auth get-key client.cephfs-team2` 결과값

---

## 5. 등록 검증

1. Proxmox Storage 목록에 `cephfs-team2`가 표시되는지 확인
2. 상태가 `active`인지 확인
3. Proxmox 노드에서 CephFS 접근 오류가 없는지 확인

필요 시 권한 확인:

```bash
ceph auth get client.cephfs-team2
```

---

## 6. 트러블슈팅

### 6.1 Permission denied

원인:

- `mds` 또는 `osd` cap 누락

조치:

- `client.cephfs-team2` 권한 재생성 후 Secret Key 재등록

### 6.2 FS Name mismatch

원인:

- UI의 FS Name 입력값이 실제 FS와 다름

조치:

- `ceph fs ls` 결과의 이름(`cephfs`)으로 재입력

### 6.3 Monitor 연결 실패

원인:

- Monitor IP 오타 또는 라우팅 불가

조치:

- `ceph mon dump`로 모니터 목록 재확인 후 세미콜론(`;`) 구분 입력
