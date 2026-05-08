# Proxmox 관리 페이지에서 외부 Ceph RBD Storage 연결하기

이 문서는 `10.10.10.12`가 별도 Ceph 클러스터의 노드(`ceph2`)이고, Proxmox
클러스터(`kosa1`~`kosa4`)에서 해당 Ceph 클러스터의 RBD pool을 외부 Storage로 등록하는 GUI 기준
절차를 정리한다.

CLI 중심 절차는 `external-ceph-rbd-proxmox-guide.md`를 참고한다.

주의:

- 이 문서는 Proxmox 웹 관리 페이지 기준이다.
- 실제 설정값은 Ceph 클러스터에서 확인한 값을 사용한다.
- keyring, access key, secret key는 Git 저장소에 커밋하지 않는다.

---

## 1. 전체 구성 개념

```text
Proxmox Cluster
- kosa1, kosa2, kosa3, kosa4
- Proxmox 웹 관리 페이지에서 Storage 등록

        RBD 접속

External Ceph Cluster
- ceph1, ceph2, ceph3, ceph4
- ceph2 = 10.10.10.12
- RBD pool 예: rbd-team1
```

Proxmox는 외부 Ceph 클러스터를 `RBD` 타입 Storage로 등록한다.

---

## 2. GUI 설정 전에 Ceph 쪽에서 준비할 값

Proxmox 관리 페이지에서 입력할 값은 Ceph 노드에서 먼저 확인해야 한다.

### 2.1 Ceph MON IP 확인

Ceph 노드(`ceph1` 또는 `ceph2`)에서 실행:

```bash
ceph mon dump
```

확인할 값:

- `ceph1` MON IP
- `ceph2` MON IP
- `ceph3` MON IP
- `ceph4` MON IP

예시:

```text
10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14
```

주의:

- 위 IP는 예시다.
- 실제 입력값은 반드시 `ceph mon dump` 결과 기준으로 사용한다.

### 2.2 RBD pool 확인

예: `rbd-team1`을 Proxmox Storage로 사용할 경우

```bash
ceph osd pool ls detail | grep rbd-team1
ceph osd pool application get rbd-team1
rbd ls rbd-team1
```

정상 기준:

- `rbd-team1` pool 존재
- application이 `rbd`
- `rbd ls` 실행 가능

### 2.3 Proxmox용 Ceph user/keyring 준비

예: `rbd-team1` 전용 사용자 `client.pve-team1`

```bash
ceph auth get-or-create client.pve-team1 \
  mon 'profile rbd' \
  osd 'profile rbd pool=rbd-team1' \
  mgr 'profile rbd pool=rbd-team1' \
  -o /etc/ceph/ceph.client.pve-team1.keyring
```

keyring 내용 확인:

```bash
cat /etc/ceph/ceph.client.pve-team1.keyring
```

예상 형태:

```text
[client.pve-team1]
    key = 실제_KEY_값
    caps mgr = "profile rbd pool=rbd-team1"
    caps mon = "profile rbd"
    caps osd = "profile rbd pool=rbd-team1"
```

GUI에서 필요한 값:

| 항목       | 값 예시                            | 설명                             |
| :--------- | :--------------------------------- | :------------------------------- |
| ID         | `ceph-rbd-team1`                   | Proxmox Storage 이름             |
| Pool       | `rbd-team1`                        | Ceph RBD pool 이름               |
| Monitor(s) | `10.10.10.11 10.10.10.12 ...`      | Ceph MON IP 목록                 |
| Username   | `pve-team1`                        | `client.`를 제외한 사용자명      |
| Keyring    | `key = ...` 또는 keyring 전체 내용 | Proxmox UI 입력 방식에 따라 입력 |
| Content    | `Disk image`, `Container`          | VM/LXC 사용 범위                 |

---

## 3. Proxmox 웹 관리 페이지 접속

브라우저에서 Proxmox 관리 페이지 접속:

```text
https://<Proxmox-관리-IP>:8006
```

예시:

```text
https://172.16.23.2:8006
```

로그인 후 다음 경로로 이동한다.

```text
Datacenter → Storage → Add → RBD
```

---

## 4. RBD Storage 추가 화면 입력값

`Add → RBD`를 선택하면 RBD Storage 추가 창이 열린다.

입력 예시는 다음과 같다.

| Proxmox GUI 항목 | 입력 예시                                         | 설명                                   |
| :--------------- | :------------------------------------------------ | :------------------------------------- |
| ID               | `ceph-rbd-team1`                                  | Proxmox에서 보일 Storage 이름          |
| Pool             | `rbd-team1`                                       | 외부 Ceph의 RBD pool 이름              |
| Monitor(s)       | `10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14` | `ceph mon dump`에서 확인한 MON IP 목록 |
| Username         | `pve-team1`                                       | `client.pve-team1`에서 `client.` 제외  |
| Keyring          | keyring 내용 또는 key 값                          | Ceph에서 생성한 client keyring         |
| Content          | `Disk image`, 필요 시 `Container`                 | VM 디스크, LXC rootdir 사용 여부       |
| Nodes            | 비워두거나 전체 노드 선택                         | 특정 노드만 사용할 경우만 제한         |
| KRBD             | 기본값 유지                                       | 특별한 이유 없으면 기본값 유지         |

주의:

- `Username`에는 `client.pve-team1`이 아니라 `pve-team1`을 입력한다.
- `Monitor(s)`에는 Ceph MON IP를 공백으로 구분해 입력한다.
- `Pool`에는 Ceph pool 이름인 `rbd-team1`을 입력한다.
- VM 디스크만 사용할 경우 Content에서 `Disk image`만 선택한다.
- LXC까지 사용할 경우 `Container`도 선택한다.

---

## 5. Keyring 입력 방식

Proxmox 버전/화면에 따라 keyring 입력 방식이 조금 다를 수 있다.

### 5.1 keyring 전체 내용을 입력하는 경우

Ceph 노드에서 확인한 내용을 그대로 입력한다.

```text
[client.pve-team1]
    key = 실제_KEY_값
```

### 5.2 key 값만 입력하는 경우

아래 명령으로 key 값만 확인한다.

```bash
ceph auth get-key client.pve-team1
```

출력 예시:

```text
AQDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx==
```

GUI의 Keyring 또는 Key 입력란에 이 값을 넣는다.

정확한 입력 방식은 현재 Proxmox 화면의 필드명에 맞춘다.

---

## 6. 등록 후 GUI에서 확인

Storage 추가 후 다음 위치에서 확인한다.

```text
Datacenter → Storage
```

확인 항목:

- `ceph-rbd-team1` Storage가 목록에 보이는지
- Type이 `RBD`인지
- Content가 `Disk image` 또는 `Container`로 표시되는지
- Nodes 제한이 의도한 대로 되어 있는지

각 노드 화면에서도 확인한다.

```text
Node 선택 → Storage 목록 → ceph-rbd-team1
```

정상이라면 용량 정보와 사용량이 표시된다.

---

## 7. VM 생성 화면에서 RBD Storage 사용 확인

Proxmox GUI에서 새 VM을 만들 때 확인한다.

```text
Create VM → Hard Disk → Storage
```

Storage 목록에 아래 항목이 보여야 한다.

```text
ceph-rbd-team1
```

테스트 방법:

1. 테스트 VM 생성
2. Hard Disk Storage를 `ceph-rbd-team1`로 선택
3. VM 생성 완료
4. Ceph 쪽에서 RBD 이미지 생성 여부 확인

Ceph 노드에서 확인:

```bash
rbd ls rbd-team1
ceph -s
```

정상 기준:

- `vm-<VMID>-disk-0` 형태의 이미지가 보임
- `ceph -s`가 `HEALTH_OK` 또는 사유 파악 가능한 상태

---

## 8. LXC Container에서 사용할 경우

LXC root disk까지 RBD에 저장하려면 Storage Content에 `Container`가 포함되어야 한다.

GUI 경로:

```text
Datacenter → Storage → ceph-rbd-team1 → Edit
```

Content에서 다음 항목을 확인한다.

- `Disk image`
- `Container`

LXC 생성 시:

```text
Create CT → Root Disk → Storage → ceph-rbd-team1
```

---

## 9. 설정값 확인 방법

GUI 등록 후에도 CLI로 설정을 확인할 수 있다.

Proxmox 노드에서:

```bash
cat /etc/pve/storage.cfg
pvesm status
pvesm config ceph-rbd-team1
```

예상 형태:

```text
rbd: ceph-rbd-team1
        content images,rootdir
        monhost 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14
        pool rbd-team1
        username pve-team1
```

Proxmox에서 keyring은 보통 다음 계열 위치에 저장된다.

```text
/etc/pve/priv/ceph/<STORAGE_ID>.keyring
```

예시:

```text
/etc/pve/priv/ceph/ceph-rbd-team1.keyring
```

주의:

- 이 파일은 민감 정보다.
- 내용을 Git 저장소에 복사하지 않는다.

---

## 10. 네트워크 문제 확인

Proxmox 노드에서 Ceph MON IP로 통신되는지 확인한다.

```bash
ping 10.10.10.12
ping -M do -s 8972 10.10.10.12
```

정상 기준:

- packet loss `0%`
- jumbo frame ping 성공

만약 GUI에서 Storage 추가는 되었지만 용량이 보이지 않거나 오류가 나면 다음을 확인한다.

- Proxmox 노드에서 Ceph MON IP로 ping 가능한지
- `10.10.10.0/24` 대역이 Proxmox와 Ceph 양쪽에서 라우팅 가능한지
- MTU `9000` 경로가 중간 스위치까지 일치하는지
- 방화벽에서 Ceph MON/OSD 통신을 막고 있지 않은지

---

## 11. 오류 발생 시 점검 순서

### 11.1 Proxmox GUI에서 Storage가 inactive로 보이는 경우

Ceph 노드에서:

```bash
ceph -s
ceph mon dump
ceph auth get client.pve-team1
ceph osd pool application get rbd-team1
```

Proxmox 노드에서:

```bash
pvesm status
pvesm config ceph-rbd-team1
ping 10.10.10.12
```

확인할 부분:

- MON IP 오타
- Username에 `client.`를 붙였는지 여부
- keyring 값 오류
- pool 이름 오타
- Ceph user 권한 부족

### 11.2 VM 생성 시 disk 생성 실패

Ceph 노드에서:

```bash
rbd -p rbd-team1 ls
ceph health detail
```

Proxmox 노드에서:

```bash
journalctl -xe
pvesm list ceph-rbd-team1
```

확인할 부분:

- `rbd-team1` pool이 RBD application으로 설정되어 있는지
- `rbd pool init rbd-team1`이 수행되었는지
- `client.pve-team1`이 해당 pool에 `profile rbd` 권한을 갖는지

---

## 12. 권장 체크리스트

- [ ] Ceph 상태 `HEALTH_OK`
- [ ] `ceph mon dump`로 MON IP 확인
- [ ] `rbd-team1` pool 생성
- [ ] `ceph osd pool application enable rbd-team1 rbd` 완료
- [ ] `rbd pool init rbd-team1` 완료
- [ ] `client.pve-team1` 생성
- [ ] Proxmox에서 `10.10.10.12` ping 성공
- [ ] Proxmox GUI `Datacenter → Storage → Add → RBD` 등록
- [ ] `Datacenter → Storage`에서 RBD Storage 표시 확인
- [ ] VM 생성 화면의 Storage 목록에서 `ceph-rbd-team1` 확인
- [ ] 테스트 VM 디스크 생성 후 Ceph에서 `rbd ls rbd-team1` 확인

---

## 13. 참고: GUI 입력값 예시 정리

| 항목       | 값 예시                                           |
| :--------- | :------------------------------------------------ |
| ID         | `ceph-rbd-team1`                                  |
| Pool       | `rbd-team1`                                       |
| Monitor(s) | `10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14` |
| Username   | `pve-team1`                                       |
| Content    | `Disk image`, 필요 시 `Container`                 |
| Keyring    | `client.pve-team1`의 keyring 또는 key 값          |

최종적으로 VM 생성 화면에서 `ceph-rbd-team1`이 디스크 저장소로 선택 가능하면 GUI 기준 RBD Storage
연결은 완료된 것이다.
