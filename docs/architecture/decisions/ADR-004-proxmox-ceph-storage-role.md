# ADR-004: Proxmox 기반 Ceph 스토리지 역할 분리

## 상태

Accepted

## 날짜

2026-05-03

## 배경

온프레미스 장비는 Proxmox로 구성할 예정임. Proxmox는 VM/LXC와 Ceph 운영에 적합하지만, AWS burst 앱의
블록 스토리지 계층으로 직접 연결하면 네트워크 지연과 운영 복잡도가 커짐.

## 결정

Proxmox는 온프레미스 VM/LXC 및 Ceph 운영 플랫폼으로 사용함. AWS 앱과 PXC 백업은 Ceph RGW의 S3 호환
API로만 연동함. Ceph RBD는 Proxmox VM 디스크 또는 온프레미스 Kubernetes 볼륨에 사용하고, AWS burst
앱 또는 ECS fallback에서는 직접 사용하지 않음.

## 대안

- AWS burst 앱에서 Ceph RBD 직접 사용
- PXC 실시간 데이터 디스크를 온프레미스 Ceph에 배치
- DB를 Proxmox VM으로 이동하고 AWS 앱과 VPN으로 연결
- AWS S3만 백업 저장소로 사용

## 영향

장점:

- AWS와 온프레미스 역할 경계가 명확함
- Ceph RGW를 통해 S3 호환 백업과 파일 업로드 시나리오를 설명 가능
- Proxmox/Ceph 관리망을 외부에 노출하지 않는 보안 경계를 만들 수 있음

감수할 점:

- 온프레미스 RGW endpoint 접근 경로를 VPN 또는 제한된 IP 기반 HTTPS로 결정해야 함
- Proxmox VM 백업과 PXC 논리 백업을 혼동하지 않도록 설명해야 함
- Ceph RBD/CephFS 고급 활용은 선택 확장으로 남김

## 관련 문서

- [Ceph Usage Strategy](../../13_ceph_usage_strategy.md)
- [Architecture](../../01_architecture.md)
- [Database Storage Runbook](../../runbooks/database_storage.md)
