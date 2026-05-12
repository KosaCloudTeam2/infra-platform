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

## 5. 등록 검증 (Verification)

### 5.1 호스트 레벨 마운트 상태 확인

- **명령어 실행**:
  ```bash
  mount | grep cephfs
  df -h | grep cephfs
  ```
- **확인 사항**:
  - `/mnt/pve/cephfs-team2` 경로 마운트 여부
  - 전체 CephFS 용량 정상 표시 여부

### 5.2 읽기/쓰기 권한 테스트

- **절차**:
  ```bash
  # 1. 파일 생성
  touch /mnt/pve/cephfs-team2/test_file
  # 2. 생성 확인
  ls -l /mnt/pve/cephfs-team2/test_file
  # 3. 파일 삭제
  rm /mnt/pve/cephfs-team2/test_file
  ```
- **결과**: Permission Denied 없이 수행 완료 시 성공

### 5.3 Proxmox UI 정합성 검토

- **Active 상태**: 트리 메뉴 `cephfs-team2` 옆 체크 표시(활성) 확인
- **Resource Summary**: 'Summary' 탭의 용량 정보가 Ceph 클러스터 현황과 일치하는지 확인
- **Content Access**: 'Content' 탭 진입 시 오류 없이 파일 리스트가 로딩되는지 확인

### 5.4 다중 노드 데이터 동기화 검증

- **교차 확인**:

  ```bash
  # Node A: 테스트 파일 생성
  echo "sync-ok" > /mnt/pve/cephfs-team2/sync_test

  # Node B: 동일 경로에서 파일 내용 확인
  cat /mnt/pve/cephfs-team2/sync_test
  ```

- **확인**: 노드 간 데이터 즉시 동기화 확인 후 파일 삭제

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
