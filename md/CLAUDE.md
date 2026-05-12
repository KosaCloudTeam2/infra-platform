# KOSA 인프라 프로젝트 기본 구성

## 프로젝트 개요

- **팀 규모**: 4인 인프라 프로젝트
- **목표 아키텍처**: 온프레미스 + Ceph + AWS 하이브리드 클라우드 환경
- **메인 워크로드**: Kubernetes (K8s) — 온프레미스 운영의 핵심
- **CI/CD**: ArgoCD 기반 GitOps 파이프라인

## 물리 장비 구성

- 라우터 1대
- 관리형 스위치 1대(port2: proxmox4대, port5: 관리 노트북 4대)
- 비관리형 스위치 2대
- JTCOM JT-S508CL-8S L3 8포트 10G 매니지드 스위치 7대
  - Spine 스위치 2대
  - Leaf 스위치 5대
  - Ceph 클러스터링용 Spine-Leaf 패브릭 구성
- Ceph 노드 6대 (별도 클러스터)
  - 각 노드당 1TB HDD 1개 → 총 6TB Raw 용량
  - OSD 백엔드: BlueStore
  - 10GbE Spine-Leaf 패브릭으로 Public/Cluster Network 연결

## pfSense (방화벽 / 라우터 / VLAN 게이트웨이)

- **역할**: 메인 방화벽/라우터, VLAN 10~40 게이트웨이 및 라우팅
- **이중화**: HA(High Availability) 구성 — CARP + pfsync + XMLRPC Sync
- **실제 배치**: Proxmox 4대 중 2대 위에 pfSense VM으로 얹어서 운영
  - 하드웨어 4대 제약으로 인한 현실적 선택
- **발표용 시나리오**: pfSense를 별도 전용 어플라이언스 2대로 분리 배치한 것처럼 설명
  - 토폴로지 다이어그램은 실제용/발표용 두 버전으로 관리 권장
- **주의점**:
  - pfSense VM이 올라간 Proxmox 노드 2대의 부팅 순서/네트워크 의존성이 핵심
  - 해당 노드는 VM autostart, HA 정책, CPU/메모리 우선순위 설정 필요
  - 관리망(vmbr0)이 pfSense 의존하지 않도록 OOB 경로 확보 필요

## Proxmox 노드 사양 (kosa1 기준, 4대 동일 가정)

- **시스템**: LG B80LV.AP37B7E (TA001), 마더보드 MICRO-STAR MS-BA03L
- **OS/커널**: Debian 13 (Trixie) / Kernel 6.17.13-2-pve (Proxmox VE)
- **CPU**: Intel Core i7-13700 (13세대 Raptor Lake), 16코어 24스레드 (8P+8E), L3 30MiB, 최대 5.2GHz,
  VMX(가상화) 지원
- **메모리**: 32 GiB (현재 사용률 약 75%)
- **GPU**: Intel UHD Graphics 770 (내장, i915 드라이버) — 헤드리스 운영
- **네트워크**:
  - eno1: Intel I219-V 1GbE (관리/업링크용 추정)
  - enp1s0f0: Intel 82599ES 10GbE SFP+ (up, 10Gbps) — Ceph/스토리지망 추정
  - enp1s0f1: Intel 82599ES 10GbE SFP+ (down, 예비 또는 미연결)
  - 브리지: vmbr0, vmbr1 (10Gbps), 다수의 fwbr/fwln/fwpr/tap 인터페이스 → 이미 VM 6대 정도 운영 중
    (VMID 103, 104, 107, 111, 124, 127)
- **스토리지**:
  - NVMe: Solidigm SSDPFKNU512GZ 476.94 GiB (시스템 디스크, LVM `pve-root` 93.93 GiB / EFI / swap
    8GiB)
  - HDD: Toshiba DT01ACA100 931.51 GiB (보조)
  - 총 1.38 TiB, 사용 9.5 GiB (0.7%)
- **가동 시간**: 16일 18시간 (안정 운영 중)

## Ceph 클러스터 구성

- **노드 수**: 6대 (Proxmox 4대와 분리된 별도 물리 클러스터)
- **OSD 디스크**: 노드당 1TB HDD × 1 = 총 6 OSD / 6TB Raw
- **OSD 백엔드**: BlueStore (XFS/FileStore가 아닌 차세대 백엔드)
  - WAL/DB는 동일 HDD에 함께 배치된 것으로 가정 (별도 SSD 분리 시 성능 향상 가능)
- **네트워크**: Spine 2 / Leaf 5 의 10GbE 패브릭에 연결
  - Public Network / Cluster(Replication) Network 분리 권장
- **예상 가용 용량**:
  - 3-replica 풀 사용 시: 6TB / 3 ≈ 2TB 가용
  - EC(Erasure Coding) 4+2 구성 시: 약 4TB 가용 (단, 6노드는 EC 최소 권장 수준)
- **활용 형태 (예정)**:
  - Kubernetes PV(PersistentVolume) 백엔드 — RBD(Block) / CephFS(File)
  - S3 호환 오브젝트 스토리지 — RGW(Rados Gateway)
  - Proxmox VM 디스크 백엔드 (선택)

## 주목할 포인트 / 고려사항

- **메모리 제약**: Proxmox 노드 32GB에 사용률 75% — VM 추가 시 여유가 빡빡함. (Ceph는 별도 6대
  클러스터에 분리되어 있어 Proxmox 메모리 부담은 줄어듦)
- **Ceph 노드 메모리**: BlueStore OSD는 일반적으로 OSD당 4~8GB RAM 권장 → Ceph 노드당 최소 8GB 이상
  확보 필요. (Ceph 노드 사양 별도 확인 필요)
- **네트워크 활용**: 10GbE 포트가 Proxmox 노드당 2개(SFP+) → Spine-Leaf 구조에서 Ceph public/cluster
  network 분리 또는 LACP 본딩 설계 가능. 현재 enp1s0f1이 down 상태인데, 활용 계획 필요(pfsync 전용
  링크 등).
- **Ceph HDD 한계**: 1TB HDD × 6 = 6TB Raw로 본격적인 대용량 워크로드는 어려움 → SSD 추가 시
  BlueStore WAL/DB 분리로 성능 보완 가능. 발표 시 "확장 시 SSD 캐시 티어/DB 분리" 로드맵 명시 권장.
- **중첩 가상화**: CPU에 VMX 플래그 있음 → Proxmox 위에 K8s, OpenStack 등 올릴 때 유용.

## 진행 가능한 다음 단계

- 네트워크 토폴로지 다이어그램 작성 (실제용 / 발표용 두 버전)
- VLAN 설계서 (10~40 용도 분배) 작성
- Spine-Leaf 패브릭 설계 문서 (BGP/EVPN 등)
- Ceph 클러스터 구성도
- AWS 하이브리드 연동 설계 (Site-to-Site VPN, Direct Connect 등)
- Proxmox 클러스터 구성 계획
- Kubernetes 클러스터 설계 (컨트롤플레인/워커 노드 배치, CNI, 스토리지 클래스)
- ArgoCD 기반 GitOps 파이프라인 설계
- pfSense HA 구성 설계 (CARP/pfsync 인터페이스 할당)

라우터 ip: 192.168.21.1 proxmox ip: 192.168.21.2 kosa1.team2 kosa1 192.168.21.3 kosa2.team2 kosa2
192.168.21.4 kosa3.team2 kosa3 192.168.21.5 kosa4.team2 kosa4

ceph(10G): 10.10.10.12

10G IP(팀원):

- kosa1 10.10.10.35
- kosa2 10.10.10.36
- kosa3 10.10.10.37
- kosa4 10.10.10.38

pfsense:

- vlan10 Subnet 172.16.21.0/24 Subnet Range 172.16.21.1 - 172.16.21.254
- vlan20 Subnet 172.16.22.0/24 Subnet Range 172.16.22.1 - 172.16.22.254
- vlan30(dhcp) Subnet 172.16.23.0/24 Subnet Range 172.16.23.1 - 172.16.23.254 Address Pool Range
  172.16.23.100 - 172.16.23.200
- vlan40(dhcp) Subnet 172.16.24.0/24 Subnet Range 172.16.24.1 - 172.16.24.254 Address Pool Range
  172.16.24.100 - 172.16.24.200

- 기술스택 Proxmox, Kubernetes, ceph, pfsense, HAproxy+keepalive, redis, proxySQL, percona xtraDB
  cluster, prometeus+grafana, terraform, ansible, AWS, github action, argoCD, jmeter, iperfs

AWS 비용 무관하지만 50만원 내외로 현재 데모로 fastapi/python으로 코딩된 회원정보 등록/출력 이
있음(유지 or 확장 or 새로 바이브코딩)
