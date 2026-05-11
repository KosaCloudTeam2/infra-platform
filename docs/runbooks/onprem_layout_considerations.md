# 온프레미스 VM 배치 개선 및 고려사항 (임시)

본 문서는 `docs/runbooks/onprem_port_vlan_vm_layout.md` 실행안에 대한 분석 결과와 가용성 및 자원
효율화를 위한 개선 제안을 정리한 임시 문서입니다.

## 1. 가용성(Availability) 관점 개선사항

- **Node 4 SPoF(단일 장애 지점) 해소**
  - 현상: 접속 입구(HAProxy), DB 중계(ProxySQL), 운영 거점(Bastion)이 Node 4에 집중됨.
  - 위험: Node 4 장애 시 서비스 접속, DB 연결, 긴급 복구 경로가 동시에 차단됨.
  - 제안: ProxySQL을 Node 2로, Bastion을 Node 1로 분산 배치하여 장애 영향도 최소화.

- **App-DB 경로(Path) 이중화 고려**
  - 현상: ProxySQL이 1대(Node 4)만 배치되어 있음.
  - 위험: ProxySQL VM 장애 시 k8s-worker와 PXC 노드가 정상이어도 DB 접속 불가.
  - 제안: MVP 이후 ProxySQL을 2대로 확장하고 가상 IP(Keepalived) 또는 HAProxy 뒷단에 배치하는 방안
    검토.

## 2. 자원 밸런스(Resource Balance) 관점 개선사항

- **Node 3 부하 과집중 완화**
  - 현상: Node 3에 k8s Control Plane, Worker, PXC 노드가 모두 배치되어 RAM 점유율(22 GiB)이 가장
    높음.
  - 위험: DB(PXC)와 앱 워크로드(Worker)가 동일 물리 노드에서 자원 경합 발생 가능.
  - 제안: PXC-3 노드를 Node 4로 이동하여 전체적인 RAM 사용량 평탄화(Node 3: 14 GiB, Node 4: 18 GiB).

- **스토리지 오버프로비저닝 주의**
  - 현상: 개별 노드 로컬 디스크(93.93 GiB) 대비 할당된 VM 디스크 합계(최대 180 GiB)가 큼.
  - 위험: Ceph RBD 연결 전 로컬 테스트 시 디스크 풀(Full)로 인한 노드 정지 가능성.
  - 제안:
    - 로컬 디스크 사용 시 반드시 Thin Provisioning 적용.
    - MVP 단계에서는 VM별 디스크 할당량을 필수 최소 용량으로 하향 조정 검토.

## 3. 관리 효율성 관점 개선사항

- **Bastion 위치 최적화**
  - 현상: 방화벽(pfSense)은 Node 1/2에 있으나 관리 거점(Bastion)은 Node 4에 위치.
  - 제안: Bastion을 pfSense-A가 있는 Node 1에 배치하여 관리 트래픽 동선 단축 및 pfSense 장애 시에도
    관리 접근성 확보.

## 4. 제안하는 수정 배치안 (요약)

| 물리 호스트 | 권장 VM 배치 (수정안)                      | 비고                  |
| :---------- | :----------------------------------------- | :-------------------- |
| **Node 1**  | pfSense-A, k8s-cp-1, PXC-1, **Bastion**    | 관리/DB 분산          |
| **Node 2**  | pfSense-B, k8s-cp-2, PXC-2, **ProxySQL-1** | 네트워크/DB 중계 분산 |
| **Node 3**  | k8s-cp-3, k8s-worker-1                     | 앱 워크로드 집중      |
| **Node 4**  | k8s-worker-2, HAProxy-1, **PXC-3**         | 접속 입구/DB 분산     |

---

**작성일:** 2026-05-12 **관련 문서:** `docs/runbooks/onprem_port_vlan_vm_layout.md`
