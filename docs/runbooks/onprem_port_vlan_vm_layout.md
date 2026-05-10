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

## 3. 미정(TBD) 항목

아래 항목은 실제 반영 전에 확정 필요:

1. 관리형 스위치 실제 포트 번호 매핑(업링크/노드1~4/비관리형 업링크)
2. VLAN별 최종 CIDR/GW/DHCP 범위
3. 온프레미스↔AWS 연결 방식(IPsec/WireGuard/제한 HTTPS) 최종 1안
4. pfSense HA 세부값(CARP VIP, VHID, pfsync 전용 인터페이스)

## 4. 물리 포트 배치 실행안

비관리형 스위치는 운영자 단말용 단일 Access VLAN(관리망) 용도로만 사용함.

| 구분        | 연결 대상                | 스위치 포트 모드            | VLAN 설정                           | 비고               |
| :---------- | :----------------------- | :-------------------------- | :---------------------------------- | :----------------- |
| Uplink      | Router ↔ 관리형 스위치   | Trunk 또는 Routed 포트(TBD) | VLAN10(외부), 필요 VLAN만 허용      | 인터넷/WAN 경계    |
| Host1       | Proxmox Node1            | Trunk                       | VLAN 10/20/30/40 허용               | pfSense-A + K8s VM |
| Host2       | Proxmox Node2            | Trunk                       | VLAN 10/20/30/40 허용               | pfSense-B + K8s VM |
| Host3       | Proxmox Node3            | Trunk                       | VLAN 20/30/40 (VLAN10 필요 시 허용) | K8s VM 중심        |
| Host4       | Proxmox Node4            | Trunk                       | VLAN 20/30/40 (VLAN10 필요 시 허용) | K8s VM 중심        |
| Edge-Access | 관리형 ↔ 비관리형 스위치 | Access                      | VLAN40 고정                         | 노트북 1~4 관리망  |

> 노드4는 노드1~3과 동일하게 **관리형 스위치 트렁크 포트**에 연결함.

## 5. VLAN / 서브넷 / 게이트웨이 실행안

아래 CIDR은 제안값이며, 확정 전까지 `TBD`로 유지 가능.

| VLAN | 용도                | 제안 CIDR               | GW 주체         | 기본 정책                   |
| :--- | :------------------ | :---------------------- | :-------------- | :-------------------------- |
| 10   | 외부/WAN            | `192.168.10.0/24` (TBD) | pfSense WAN     | 외부 연결 전용              |
| 20   | DMZ/Ingress         | `192.168.20.0/24` (TBD) | pfSense LAN/DMZ | 외부 노출 컴포넌트 최소화   |
| 30   | 내부 서비스/DB 경유 | `192.168.30.0/24` (TBD) | pfSense LAN     | 앱↔ProxySQL↔PXC 내부 트래픽 |
| 40   | 관리망(운영 단말)   | `192.168.40.0/24` (TBD) | pfSense LAN     | 관리자 접근 전용            |

## 6. VM 배치 실행안 (4대 Proxmox)

Ceph는 별도 구성으로 제외.

| 물리 호스트 | VM 배치(권장)                                 | 네트워크 비고               |
| :---------- | :-------------------------------------------- | :-------------------------- |
| Node1       | pfSense-A, k8s-control-plane-1                | WAN/DMZ/내부/관리 VLAN 연결 |
| Node2       | pfSense-B, k8s-control-plane-2                | pfSense HA 동기화 대상      |
| Node3       | k8s-control-plane-3, k8s-worker-1             | 내부 서비스 중심            |
| Node4       | k8s-worker-2, k8s-worker-3(또는 운영 보조 VM) | 내부/관리망 중심            |

## 7. ACL/방화벽 최소 허용 정책 (초안)

| 출발지       | 목적지                      | 포트                | 정책          | 비고                |
| :----------- | :-------------------------- | :------------------ | :------------ | :------------------ |
| VLAN40(관리) | Proxmox/pfSense 관리면      | HTTPS/SSH(TBD)      | 허용(제한 IP) | 운영자 단말만       |
| VLAN20/30 앱 | ProxySQL                    | `6033/TCP`          | 허용          | DB 접속 단일화      |
| ProxySQL     | PXC                         | `3306/TCP`          | 허용          | DB 쿼리             |
| PXC 노드 간  | PXC 노드 간                 | `4567/4568/4444`    | 허용          | Galera 복제         |
| Any          | PXC/ProxySQL Admin 포트     | `6032`, DB 관리포트 | 기본 차단     | SSM/VPN 경유만 허용 |
| Internet     | Proxmox/Ceph/pfSense 관리면 | 관리 포트 전부      | 차단          | 공개 금지           |

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
- [ ] 노드1~4 트렁크/액세스 정책이 표와 일치함
- [ ] 비관리형 스위치 구간은 VLAN40 Access 전용임
- [ ] 앱->ProxySQL(`6033`) 경유만 허용됨
- [ ] PXC/ProxySQL 관리면 인터넷 비공개 확인
- [ ] pfSense 2대 장애 전환 테스트 기록 확보
- [ ] `uv run mkdocs build` 통과
