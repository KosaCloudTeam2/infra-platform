# Proxmox-Ceph RBD 등록 가이드 (TEAM2 전용)

> Status: Verified

`rbd-team2` 풀을 Proxmox Storage로 등록하는 **선행 단계 전용** 문서임.

---

## 1. 목표

- Proxmox에서 `ceph-rbd-team2` Storage를 추가함
- 사용자 계정은 `client.TEAM2` 기준으로 통일함
- Content는 `Disk image`만 사용함

---

## 2. 사전 확인

### 2.1 Ceph 상태

```bash
ceph -s
ceph mon dump
ceph osd pool ls
```

확인 기준:

- monitor quorum 정상
- `rbd-team2` 풀 존재
- monitor IP 목록 확보

예시 monitor 입력값:

```text
10.10.10.14;10.10.10.11;10.10.10.12;10.10.10.13
```

---

## 3. TEAM2 계정 생성/확인

```bash
ceph auth get-or-create client.TEAM2 \
  mon 'profile rbd' \
  osd 'profile rbd pool=rbd-team2' \
  mgr 'profile rbd pool=rbd-team2'

ceph auth get client.TEAM2
ceph auth get-key client.TEAM2
```

---

## 4. Proxmox UI 등록

경로:

```text
Datacenter → Storage → Add → RBD
```

입력값:

- **ID**: `ceph-rbd-team2`
- **Monitor(s)**: `10.10.10.14;10.10.10.11;10.10.10.12;10.10.10.13`
- **Pool**: `rbd-team2`
- **Username**: `TEAM2` (`client.` 제외)
- **Keyring**: 아래 형식 사용
- **Content**: `Disk image`

Keyring 형식 예시(민감값 마스킹):

```ini
[client.TEAM2]
    key = <REDACTED_KEY>
```

---

## 5. 등록 검증

1. Proxmox Storage 목록에서 `ceph-rbd-team2` 상태 확인
2. VM 생성 화면에서 Disk Storage로 `ceph-rbd-team2` 선택 가능 여부 확인
3. Ceph에서 이미지 확인

```bash
rbd ls rbd-team2
```

`vm-xxx-disk-0` 형태가 보이면 정상 연결임.

---

## 6. 문서 범위(중복 방지)

이 문서는 **RBD 등록/인증**까지만 다룸.

- Cloud Image import
- Template 변환
- Clone 생성

위 3개는 `02_template_clone_guide.md`에서 다룸.

---

## 7. 트러블슈팅 (RBD 등록 단계)

### 7.1 `Not a proper rbd authentication file` 오류

원인:

- Keyring 칸에 raw key 문자열만 넣은 경우

조치:

- 아래 형식으로 입력

```ini
[client.TEAM2]
    key = <REDACTED_KEY>
```

### 7.2 Username 입력 오류

원인:

- `client.TEAM2`를 그대로 입력

조치:

- Proxmox Username은 `TEAM2`로 입력 (`client.` 제거)

### 7.3 Monitor 일부만 입력

원인:

- 단일 monitor만 입력해 장애 시 연결 불안정

조치:

- quorum monitor 전체를 `;`로 구분해 입력
