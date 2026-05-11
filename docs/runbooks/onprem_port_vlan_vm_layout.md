# 온프레미스 포트 / VLAN / VM 배치 실행안

## 1. 목적

온프레미스 4대 Proxmox 호스트 기준으로, 스위치 포트/VLAN/VM 배치를 실행 가능한 형태로 정리함.

- 물리 노드 4대는 모두 Proxmox 호스트로 사용
- 역할은 VM으로 분리(control-plane / worker / pfSense)
- Ceph는 별도 구성(본 문서 범위 밖)
- pfSense 2대 구성은 MVP에 포함

## 2. 전제 및 경계

- 앱 실행 기본 경로는 온프레미스 Kubernetes임.
- AWS는 burst 영역이며 온프레미스 CIDR은 AWS `10.20.0.0/16`과 중첩되면 안 됨.
- DB 접근은 앱 -> ProxySQL endpoint 경로만 허용.
- Proxmox/pfSense/DB 관리면은 인터넷에 직접 공개하지 않음.

## 3. 확정값(2026-05 기준)

아래 항목은 현재 팀 합의 기준으로 고정함.

1. 관리형 스위치 포트 1~5는 trunk 유지
2. 스위치 VLAN 설정
   - VLAN1: untagged(Access) 포트 1~5
   - VLAN10/20/30/40: tagged(Trunk) 포트 1~5
3. 물리 단말(Proxmox PC/노트북)은 `192.168.21.0/24` 유지
4. VM VLAN 태깅 대역은 `172.16.21.0/24` ~ `172.16.24.0/24` 사용
5. VLAN20(DMZ)에 HAProxy 배치
6. VLAN10~40 라우팅/DHCP 게이트웨이 주체는 pfSense로 고정

## 4. 물리 포트 배치 실행안

| 포트 | 연결 대상                   | 포트 모드 | VLAN 동작                               | 비고                       |
| :--- | :-------------------------- | :-------- | :-------------------------------------- | :------------------------- |
| 1    | Router ↔ 관리형 스위치      | Trunk     | VLAN1 untagged + VLAN10/20/30/40 tagged | 업링크                     |
| 2    | 관리형 ↔ 비관리형 스위치(A) | Trunk     | VLAN1 untagged + VLAN10/20/30/40 tagged | Proxmox PC 4대 연결 스위치 |
| 3    | Proxmox Node1               | Trunk     | VLAN1 untagged + VLAN10/20/30/40 tagged | pfSense-A + K8s VM         |
| 4    | Proxmox Node2               | Trunk     | VLAN1 untagged + VLAN10/20/30/40 tagged | pfSense-B + K8s VM         |
| 5    | 관리형 ↔ 비관리형 스위치(B) | Trunk     | VLAN1 untagged + VLAN10/20/30/40 tagged | 노트북(Proxmox 접속)       |

운영 메모:

- 비관리형 스위치 뒤 단말은 일반적으로 untagged 트래픽만 사용하므로, 기본적으로
  VLAN1(`192.168.21.0/24`)로 동작함.
- VM 네트워크 분리는 Proxmox VM NIC의 VLAN tag(10/20/30/40) 설정으로 적용함.

## 5. VLAN / 서브넷 / 게이트웨이 실행안

| VLAN | 용도                        | CIDR              | GW/DHCP 주체      | 기본 정책                     |
| :--- | :-------------------------- | :---------------- | :---------------- | :---------------------------- |
| 1    | 물리 단말 관리망            | `192.168.21.0/24` | Router(기존 유지) | Proxmox PC/노트북 기본 접속망 |
| 10   | VM 태그망-A(외부 연계)      | `172.16.21.0/24`  | pfSense           | VM 태깅 사용                  |
| 20   | VM 태그망-B(DMZ)            | `172.16.22.0/24`  | pfSense           | DMZ + HAProxy 배치            |
| 30   | VM 태그망-C(내부 서비스/DB) | `172.16.23.0/24`  | pfSense           | 앱↔ProxySQL↔PXC 내부 트래픽   |
| 40   | VM 태그망-D(관리형 VM 전용) | `172.16.24.0/24`  | pfSense           | 운영 보조 VM 전용             |

## 6. VM 배치 실행안 (4대 Proxmox)

Ceph는 별도 구성으로 제외.

### 6.0 VM 역할 분리 원칙

- 기본 원칙: **VM 1대 = 1역할**
- 이유: 장애 영향 범위 축소, 보안 경계 분리, 성능 병목 원인 파악 단순화
- 예외: 13일 MVP 일정에서 불가피한 경우에만 임시 통합하고, 발표/문서에 한계를 명시

### 6.1 VM별 vCPU/RAM/디스크 권장값 (4노드 공통 사양 기준)

기준 사양(노드당): 24 vCPU / 31.08 GiB RAM / 93.93 GiB 로컬 디스크

| VM 역할           | 권장 vCPU | 권장 RAM | 권장 디스크 | 비고                         |
| :---------------- | --------: | -------: | ----------: | :--------------------------- |
| pfSense           |         2 |    2 GiB |      16 GiB | HA 구성 시 2대               |
| k8s Control Plane |         4 |    6 GiB |      60 GiB | etcd 포함, 3대 권장          |
| k8s Worker        |         4 |    8 GiB |      80 GiB | 앱 워크로드 기준(Flask 포함) |
| PXC Node          |         4 |    8 GiB |      40 GiB | Ceph RBD 사용, MVP 최소 기준 |
| ProxySQL          |         2 |    4 GiB |      20 GiB | MVP 1대, 확장 2대            |
| HAProxy           |         1 |    2 GiB |      10 GiB | MVP 1대, 확장 2대            |
| 운영 Bastion      |         1 |    2 GiB |      16 GiB | 운영 보조용                  |

> 디스크는 Ceph RBD thin provisioning 기준 권장값임. 로컬 디스크(93.93 GiB)에 직접 적재하는 방식은
> 권장하지 않음.

### 6.2 최소 배치안(필수 VM만)

| 물리 호스트 | 최소 VM 배치(필수)                           | 합계(vCPU/RAM)   | 비고                |
| :---------- | :------------------------------------------- | :--------------- | :------------------ |
| Node1       | pfSense-A, k8s-control-plane-1, PXC-1        | 10 vCPU / 16 GiB | 네트워크/DB 분산    |
| Node2       | pfSense-B, k8s-control-plane-2, PXC-2        | 10 vCPU / 16 GiB | pfSense HA 페어     |
| Node3       | k8s-control-plane-3, k8s-worker-1, PXC-3     | 12 vCPU / 22 GiB | K8s + DB 분산       |
| Node4       | k8s-worker-2, ProxySQL-1, HAProxy-1, Bastion | 8 vCPU / 16 GiB  | 접속 경계/운영 집중 |

### 6.3 Flask 테스트 웹 3개 배치안(Kubernetes 기본)

Flask 테스트 웹은 **별도 VM을 만들지 않고**, Kubernetes Worker 위에 Pod/Deployment로 배치함.

| 물리 호스트 | 배치 대상    | 권장 수량     | 네트워크 |
| :---------- | :----------- | :------------ | :------- |
| Node3       | k8s-worker-1 | Flask Pod 1개 | VLAN 30  |
| Node4       | k8s-worker-2 | Flask Pod 2개 | VLAN 30  |

운영 메모:

- Flask 테스트 웹 3개는 Deployment replicas=3으로 관리함.
- 외부 접근이 필요하면 HAProxy/Ingress를 통해 DMZ(VLAN20)에서 내부 Worker(VLAN30)로 전달함.
- 앱 런타임(Flask 포함)은 Worker에서 실행하고, 별도 앱 VM은 만들지 않음.

### 6.4 VM별 VLAN tag 정리

| VM 역할                                        | 권장 VLAN tag | 용도                             |
| :--------------------------------------------- | :------------ | :------------------------------- |
| pfSense NIC(각 VM 공통): WAN/DMZ/Internal/Mgmt | 10/20/30/40   | pfSense-A, pfSense-B에 동일 적용 |
| HAProxy                                        | 20            | DMZ Reverse Proxy                |
| Flask Test Web(Pod)                            | 30            | k8s Worker 내부 앱 런타임        |
| k8s Control Plane                              | 30            | 내부 클러스터                    |
| k8s Worker                                     | 30            | 내부 앱 런타임                   |
| ProxySQL                                       | 30            | 앱-DB 중계                       |
| PXC Node                                       | 30            | DB 내부 통신                     |
| Bastion                                        | 40            | 운영 접속 경계                   |

HAProxy 운영 기준:

- MVP 기본: 1대(단일 구성)
- 선택 확장: 2대(이중화)로 전환
- MVP 1대 운영 시 SPoF와 이중화 필요 사항을 문서/발표에 명시

## 7. ACL/방화벽 최소 허용 정책 (초안)

| 출발지            | 목적지                      | 포트                | 정책          | 비고                    |
| :---------------- | :-------------------------- | :------------------ | :------------ | :---------------------- |
| VLAN1(물리 단말)  | Proxmox 관리면              | HTTPS/SSH(TBD)      | 허용(제한 IP) | 노트북/운영 단말 접속   |
| VLAN40(관리형 VM) | 내부 관리 대상 VM           | HTTPS/SSH(TBD)      | 허용(제한 IP) | 운영 보조 VM 전용       |
| VLAN20/30 앱      | ProxySQL                    | `6033/TCP`          | 허용          | DB 접속 단일화          |
| ProxySQL          | PXC                         | `3306/TCP`          | 허용          | DB 쿼리                 |
| PXC 노드 간       | PXC 노드 간                 | `4567/4568/4444`    | 허용          | Galera 복제             |
| Any               | PXC/ProxySQL Admin 포트     | `6032`, DB 관리포트 | 기본 차단     | Bastion/VPN 경유만 허용 |
| Internet          | Proxmox/Ceph/pfSense 관리면 | 관리 포트 전부      | 차단          | 공개 금지               |

## 8. pfSense 2대(MVP) 운영 체크포인트

- 서로 다른 물리 호스트(Node1/Node2)에 배치
- CARP VIP 구성(TBD), pfsync 동기화 인터페이스 분리
- XMLRPC 설정 동기화 범위 확정
- 장애 전환 리허설(Primary down → Secondary 승격) 결과 기록

## 9. 온프레미스 ↔ AWS 연결 방식 비교

| 방식            | 장점                 | 단점                          | MVP 권장도    |
| :-------------- | :------------------- | :---------------------------- | :------------ |
| IPsec VPN       | 표준적, 장비 친화적  | 설정 복잡, 트러블슈팅 시간 큼 | 중            |
| WireGuard       | 설정 단순, 성능 우수 | 조직 표준과 불일치 가능       | 중상          |
| 제한 HTTPS 공개 | 빠른 시연            | 보안 경계 약함, 운영 부담     | 하(데모 한정) |

> 최종 1안은 `TBD`로 남기고, 선택 이유/허용 포트를 함께 기록해야 함.

## 10. 검증 체크리스트

- [ ] VLAN/CIDR이 AWS `10.20.0.0/16`과 중첩되지 않음
- [ ] 포트 1~5 trunk + VLAN1 untagged, VLAN10/20/30/40 tagged 설정이 일치함
- [ ] Proxmox PC/노트북이 `192.168.21.0/24`(VLAN1)로 정상 접속됨
- [ ] VM VLAN tag 10~40 대역(`172.16.21~24.0/24`)이 pfSense 라우팅/DHCP 기준과 일치함
- [ ] VLAN20(DMZ) HAProxy 배치 상태(2대 또는 1대+한계 명시)가 문서와 일치함
- [ ] 앱->ProxySQL(`6033`) 경유만 허용됨
- [ ] PXC/ProxySQL 관리면 인터넷 비공개 확인
- [ ] pfSense 2대 장애 전환 테스트 기록 확보
- [ ] `uv run mkdocs build` 통과
