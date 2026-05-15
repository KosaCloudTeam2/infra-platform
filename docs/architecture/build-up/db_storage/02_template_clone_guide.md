# Cloud Image → Template → Clone 가이드 (RBD 등록 이후)

`ceph-rbd-team2`가 이미 등록되어 있다는 전제로, VM 템플릿/클론 생성 절차만 다룸.

---

## 1. 목표

- Ubuntu Cloud Image를 Ceph RBD로 import
- Cloud-Init/부팅 설정 완료
- Template 변환 후 Clone 생성

---

## 2. 입력값 기준

- Storage: `ceph-rbd-team2`
- VMID 예시: `9000`
- 이미지 예시: `noble-server-cloudimg-amd64.img`

---

## 3. 절차

### 3.1 Cloud Image 준비

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

### 3.2 VM 생성 (미디어 없이)

GUI에서 `Create VM` 진행 시 OS는 `Do not use any media` 선택.

또는 CLI:

```bash
qm create 9000 --name ubuntu-2404-template --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
```

### 3.3 Ceph RBD로 이미지 import

```bash
qm importdisk 9000 noble-server-cloudimg-amd64.img ceph-rbd-team2
```

### 3.4 디스크/부팅 설정

```bash
qm set 9000 --scsihw virtio-scsi-pci --scsi0 ceph-rbd-team2:vm-9000-disk-0
qm set 9000 --ide2 ceph-rbd-team2:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
```

### 3.5 Cloud-Init 설정

```bash
qm set 9000 --ciuser <USER>
qm set 9000 --cipassword <REDACTED_PASSWORD>
qm set 9000 --ipconfig0 ip=dhcp
```

필요 시 SSH key 기반으로 대체 권장.

### 3.6 Template 변환

```bash
qm template 9000
```

### 3.7 Clone 생성

- GUI: Template 우클릭 → `Clone`
- Full Clone: 독립 디스크(운영 권장)
- Linked Clone: 공간 절약(실습/임시 용도)

---

## 4. 검증

```bash
qm config 9000
rbd ls rbd-team2
```

확인 기준:

- `qm config`에 `scsi0`, `ide2(cloudinit)`, boot 설정 반영
- `rbd-team2`에 템플릿/클론 디스크 생성 확인

---

## 5. 운영 권장

- 템플릿은 수정 대신 버전 증가(`-v1`, `-v2`) 방식 권장
- `cipassword` 직접 저장보다 SSH key 우선
- Full Clone은 운영용, Linked Clone은 테스트용으로 분리

---

## 6. 문서 범위(중복 방지)

이 문서는 **이미지 import~clone** 절차만 다룸.

- Ceph 계정 생성
- RBD Storage 등록
- Keyring 오류 해결

위 3개는 `01_rbd_register_guide.md`에서 다룸.

---

## 7. 트러블슈팅 (Template/Clone 단계)

### 7.1 `Unused Disk`만 보이고 부팅 실패

원인:

- import된 디스크를 `scsi0`에 연결하지 않음

조치:

- `qm set ... --scsi0 ...` 또는 GUI Hardware에서 SCSI0 연결

### 7.2 Cloud-Init 설정이 반영되지 않음

원인:

- `ide2` cloudinit drive 미추가 또는 부팅 디스크 설정 불일치

조치:

- `--ide2 ceph-rbd-team2:cloudinit` 추가 후 `bootdisk=scsi0` 재확인

### 7.3 콘솔 출력 불가

원인:

- Serial/Console 설정 누락

조치:

- `--serial0 socket --vga serial0` 적용
