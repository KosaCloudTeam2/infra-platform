# Storage Platform 검증 기반 이미지 프롬프트

> 목적: 이미지 모델용 구조도 프롬프트 기준: 2026-05-25 실환경 조회 담당 범위: Ceph, 온프레미스 DB,
> Backup, Redis 제외 범위: AWS RDS, OLAP, 데이터 워크로드 상세

---

## 1. 검증 반영 사실

| 영역                | 확인값                                                  | 이미지 반영                                             |
| :------------------ | :------------------------------------------------------ | :------------------------------------------------------ |
| Ceph                | host 6대, HDD OSD 12개                                  | `Ceph Cluster: 6 hosts / 12 HDD OSDs`                   |
| Ceph replica        | pool size 3, min_size 2                                 | `Replica size 3`                                        |
| Ceph network        | 10G storage network                                     | `10G Storage Network`                                   |
| RGW                 | 1 daemon active                                         | `RGW/S3 API: 1 daemon`                                  |
| RBD                 | `team2-rbd-block` PVC                                   | Kubernetes PVC, Proxmox VM disk 연결                    |
| RGW bucket          | `harbor-registry`, `team2-bucket`, `team2-photo-bucket` | Harbor image blob, App object 연결                      |
| Harbor metadata     | Harbor DB/Redis/Trivy/Jobservice PVC                    | Ceph RBD 연결                                           |
| Redis PVC           | Redis data PVC                                          | Ceph RBD 연결, RGW/S3 아님                              |
| Harbor image mirror | Ceph RGW/S3 -> AWS ECR image mirror visual path         | image mirror는 Ceph RBD가 아니라 RGW/S3 쪽에서 표현     |
| PXC                 | 의도 3노드, 검증 시점 cluster size 2                    | 정상 구조도에는 3노드, 검증 오버레이에는 1개 recovering |
| ProxySQL            | 의도 2개, 검증 시점 active endpoint 1개                 | 정상 구조도에는 2개, 검증 오버레이에는 1개 active       |
| Redis               | 의도 3노드 Sentinel, 검증 시점 2개 reachable            | 정상 구조도에는 3개, 검증 오버레이에는 1개 recovering   |
| Backup              | RGW -> AWS S3 copy-only                                 | App object backup arrow                                 |

Copy-only 표기 기준:

- 의미: 원본 삭제를 백업 삭제로 즉시 동기화하지 않는 백업 방식
- 이유: 사용자 실수, 앱 오류, 악성 삭제 발생 시 백업본 보존
- 그림 표현: 화살표는 `object backup`으로 표기, 세부 정책 노트에만 `copy-only` 사용

---

## 2. DB 상세 구조도 프롬프트

```text
Create a clean 16:9 technical architecture diagram for the DB / Redis / Ceph storage path.

Canvas:
- background color: #0A1224
- use exactly #0A1224 as the full canvas/background color
- do not shift, lighten, darken, gradient, vignette, blur, or texture the background
- no alternate navy/blue/black background; only solid #0A1224
- widescreen 16:9
- professional infrastructure diagram
- sharp vector-like boxes
- use transparent-background cutout/icon style assets
- place recognizable icons/logos when possible: Kubernetes, Ceph, Redis, Percona/PXC, ProxySQL, Harbor, Proxmox
- minimal labels only
- no explanatory paragraphs inside the diagram
- no decorative gradients
- no mascots
- no IP addresses
- no secrets

Title:
DB / Redis / Storage Architecture

Layout:
- left to right flow
- four grouped sections
  1. App Access
  2. On-prem Kubernetes Data Path
  3. Ceph Storage Backend
  4. AWS Burst Read Edge

Section 1: App Access
- On-prem App
- AWS Burst App
- place On-prem App near the upper-left
- place AWS Burst App near the lower-left
- use two separate lanes:
  - upper DB lane: On-prem App -> ProxySQL Service -> ProxySQL x2 Pod -> PXC Service -> PXC x3
  - lower Redis state lane: On-prem App and AWS Burst App -> Redis HA area
- arrows:
  - On-prem App -> ProxySQL Service, green line, label "DB read/write"
  - ProxySQL Service -> ProxySQL x2 Pod, green line
  - ProxySQL x2 Pod -> PXC Service, green line
  - PXC Service -> PXC x3, green line
  - On-prem App -> Redis HA area, cyan line, label "reservation state"
  - AWS Burst App -> Redis HA area, cyan line, label "reservation state"
  - AWS Burst App -> RDS Read Replica, green line, label "non-reservation read"
- draw the AWS Burst App -> RDS Read Replica arrow as a fully isolated bottom-edge route
- the AWS Burst App -> RDS Read Replica arrow must stay outside the Kubernetes data path boxes
- the AWS Burst App -> RDS Read Replica arrow must stay outside the Ceph Storage Backend section
- the AWS Burst App -> RDS Read Replica arrow must not touch, overlap, or pass through App image/video object
- the AWS Burst App -> RDS Read Replica arrow must not touch, overlap, or pass through Harbor image blob
- the AWS Burst App -> RDS Read Replica arrow must not touch, overlap, or pass through Ceph RGW / S3
- if needed, route the AWS Burst App -> RDS Read Replica arrow below all other boxes with right-angle bends
- do not connect the cyan Redis arrow from On-prem App to ProxySQL Service
- do not connect the cyan Redis arrow from On-prem App to PXC Service
- do not connect the cyan Redis arrow from On-prem App to PXC x3
- do not connect the cyan Redis arrow from On-prem App to any DB component
- the On-prem App reservation state arrow must land on the outer boundary of the Redis HA area box
- the On-prem App reservation state arrow must not touch or pass through PXC Service
- both reservation state arrows must terminate at the same Redis HA area that contains Redis Sentinel x3 and Redis x3
- draw Redis Sentinel x3 and Redis x3 inside one grouped box named "Redis HA area"
- On-prem App and AWS Burst App must point to the same Redis HA area for reservation state
- route the AWS Burst App -> RDS Read Replica green arrow along the bottom lane to avoid crossing Kubernetes or Ceph boxes

Section 2: On-prem Kubernetes Data Path
- ProxySQL Service
- ProxySQL x2 Pod
- ProxySQL PVC
- PXC Service
- PXC x3
- PXC PVC
- Redis HA area
  - Redis Sentinel x3, quorum 2
  - Redis x3
- Redis PVC
- Harbor
- Harbor metadata PVC
- Harbor image blob
- labels:
  - ProxySQL Service: "ProxySQL Service" only
  - ProxySQL PVC: "ProxySQL PVC"
  - PXC Service: "PXC Service" only
  - PXC PVC: "PXC PVC"
  - Redis: "reservation state / DB load reduction"
  - Redis PVC: "Redis PVC"
  - Harbor: "registry service"
  - Harbor metadata PVC: "metadata PVC"
  - Harbor image blob: "Harbor image blob"
- do not label PXC as "Galera Cluster"
- draw Harbor metadata PVC and Harbor image blob as two separate items
- do not merge Harbor metadata PVC with Harbor image blob
- do not place any helper subtitle under ProxySQL Service
- do not place any helper subtitle under PXC Service
- ProxySQL Service must connect to ProxySQL x2 Pod
- ProxySQL x2 Pod must connect to PXC Service
- PXC Service must connect to PXC x3
- ProxySQL x2 Pod must have a visible relation to ProxySQL PVC
- ProxySQL PVC must have a blue RBD storage arrow to Ceph RBD

Section 3: Ceph Storage Backend
- Ceph Cluster
- 6 Ceph hosts
- 12 HDD OSDs
- 10G Storage Network
- Replica size 3
- Ceph RBD
- Ceph RGW / S3
- draw Ceph RBD and Ceph RGW / S3 as two clearly separate boxes inside the Ceph Storage Backend section
- place Ceph RBD above or left, and Ceph RGW / S3 below or right, with enough visual gap between them
- arrows:
  - PXC PVC -> Ceph RBD
  - ProxySQL PVC -> Ceph RBD
  - Redis PVC -> Ceph RBD
  - Harbor metadata PVC -> Ceph RBD
  - Harbor image blob -> Ceph RGW / S3, label "Harbor image blob"
  - App image/video object -> Ceph RGW / S3
- Redis PVC belongs to Ceph RBD, never Ceph RGW / S3
- Ceph RBD has only inbound block-volume arrows from PVC items
- do not draw any external arrow from Ceph RBD
- Harbor metadata PVC belongs to Ceph RBD only
- Harbor metadata PVC must have exactly one storage arrow: Harbor metadata PVC -> Ceph RBD
- do not draw any arrow from Harbor metadata PVC to Ceph RGW / S3
- Harbor metadata PVC must be visually closer to Ceph RBD than to Ceph RGW / S3
- draw the Harbor metadata PVC -> Ceph RBD arrow as a direct blue RBD storage arrow
- do not route the Harbor metadata PVC arrow near, into, or across Ceph RGW / S3
- Harbor image blob belongs to Ceph RGW / S3
- Harbor image blob must have exactly one storage arrow: Harbor image blob -> Ceph RGW / S3
- do not draw Harbor metadata and Harbor image blob into the same storage target
- Ceph RBD is for block PVC only
- Ceph RGW / S3 is for object storage only
- App image/video object belongs to Ceph RGW / S3 only
- App image/video object must not connect to Ceph RBD

Section 4: AWS Burst Read Edge
- RDS Read Replica
- place RDS Read Replica at the very bottom of this section, horizontally aligned with AWS Burst App if possible
- only draw the AWS Burst App -> RDS Read Replica arrow in this section
- do not draw any other AWS service in this section
- do not draw any external arrow from Ceph RBD
- do not draw any external arrow from Ceph RGW / S3

Visual rules:
- Use green lines for DB path
- Use cyan lines for Redis state path
- Use blue lines for RBD block storage
- Use teal lines for RGW object storage
- Keep text short inside boxes
- Keep the bottom green non-reservation read arrow separated from all Kubernetes and Ceph arrows
- Keep App image/video object away from the bottom AWS read lane
- Do not use a generic registry-blob label; use "Harbor image blob" only
- Do not add warning icons, alert badges, caution triangles, or caveat badges
- Do not include the labels "HDD write path check" or "RGW API HA separate"
- If there is any conflict, storage arrows must follow this priority:
  1. Harbor metadata PVC -> Ceph RBD
  2. Harbor image blob -> Ceph RGW / S3
  3. Redis PVC -> Ceph RBD
  4. ProxySQL PVC -> Ceph RBD
- Never draw Harbor metadata PVC -> Ceph RGW / S3
- Never draw Redis PVC -> Ceph RGW / S3
- Never draw any external arrow from Ceph RBD
- Never draw any external arrow from Ceph RGW / S3
- The only arrow entering section 4 is AWS Burst App -> RDS Read Replica
```

---

## 3. 발표용 정상 구조도 프롬프트

```text
Create a clean 16:9 technical architecture diagram for an on-prem storage and data platform.

Style:
- professional infrastructure architecture diagram
- background color: #0A1224
- use exactly #0A1224 as the full canvas/background color
- do not shift, lighten, darken, gradient, vignette, blur, or texture the background
- no alternate navy/blue/black background; only solid #0A1224
- dark background, no gradients
- sharp vector-like shapes
- use transparent-background cutout/icon style assets
- place recognizable icons/logos when possible: Proxmox, Kubernetes, Ceph, Redis, Percona/PXC, Harbor, AWS ECR, AWS S3
- minimal labels only
- no explanatory paragraphs inside the diagram
- no decorative gradients, no mascots, no marketing illustration
- use clear arrows and grouped sections

Main title:
On-prem Storage / DB / Redis / Backup Architecture

Left section: On-prem compute
- Proxmox VM
- Kubernetes cluster
- etcd Local Disk, shown separately with a dashed boundary and label "etcd local disk, not Ceph"

Kubernetes workloads:
- PXC 3 nodes
- ProxySQL 2 pods
- Redis 3 nodes with Sentinel
- Harbor metadata

Center section: Ceph Cluster
- label: "Ceph Cluster"
- label: "6 Ceph hosts"
- label: "12 HDD OSDs"
- label: "10G Storage Network"
- label: "Replica size 3 / min_size 2"
- show two internal services:
  1. "RBD Pool - block volume"
  2. "RGW / S3 - object storage"

RBD arrows:
- Proxmox VM disk -> RBD Pool
- Kubernetes PVC -> RBD Pool
- PXC PVC, Redis PVC, Harbor metadata PVC -> RBD Pool

RGW/S3 arrows:
- Harbor -> RGW/S3, label "Harbor image blob"
- App Object -> RGW/S3, label "image / video object"
- RGW/S3 -> AWS S3 backup bucket, label "object backup"
- must include the RGW/S3 -> AWS S3 backup arrow
- do not draw RGW/S3 -> AWS ECR

Backup section:
- AWS S3 bucket
- RGW/S3 object -> AWS S3 backup
- Harbor image -> AWS ECR, label "image mirror"
- show backup as a separate recovery layer, not as Ceph replica

Redis consistency section:
- On-prem app and AWS burst app both point to one Redis service for critical reservation state
- label: "single reservation state cache"
- do not draw AWS RDS read replica

Important caveats to visualize with small labels only:
- RGW API: 1 daemon
- Ceph object data: replicated by pool
- Backup: separate from replica

Do not include:
- AWS RDS
- OLAP/admin data workload
- full terminal output
- IP addresses
- passwords or secret names
- multiple RGW daemons
- etcd on Ceph
- Ceph RGW/S3 as the source of the ECR image mirror
```

---

## 4. 현재 검증 상태 오버레이 프롬프트

```text
Create a 16:9 technical verification overlay diagram for the same architecture.

Base diagram:
- use the same layout as the normal architecture diagram
- keep labels short
- no long explanations inside the image

Show verified current state badges:
- Ceph: "Verified: 6 hosts, 12 HDD OSDs, replica size 3"
- RGW: "Verified: 1 active daemon"
- RBD: "Verified: Kubernetes PVCs bound to team2-rbd-block"
- Harbor: "Verified: registry storage provider S3, bucket harbor-registry"
- Backup: "Verified: AWS S3 object count exists, latest scheduled run needs DNS/AWS endpoint check"
- PXC: "Current capture: cluster size 2, one node recovering"
- ProxySQL: "Current capture: one active endpoint, second pod recovering"
- Redis: "Current capture: two nodes reachable, one node recovering"

Visual treatment:
- green badge for verified normal storage facts
- amber badge for degraded or recovering DB/Redis facts
- no red outage icon unless drawing a separate incident slide

Do not draw:
- fully healthy 3-node Redis without caveat
- fully healthy 2-pod ProxySQL without caveat
- RGW as highly available multi-daemon service
- Ceph replica as backup replacement
```

---

## 5. 이미지 아래 설명 문구

- Ceph: 6 hosts, 12 HDD OSD, replica size 3 기반 분산 저장소
- RBD: Proxmox VM disk, Kubernetes PVC block volume
- RGW: Harbor image blob, 앱 object 저장소
- RGW API: 현재 1 daemon, object data replica와 별도 HA 고려사항
- DB: PXC/ProxySQL HA 설계, 캡처 시점 1개 노드 재합류 중
- Redis: 예매 중요 상태 통일 목적, 캡처 시점 1개 노드 복구 중
- Backup: Ceph replica와 별도인 AWS S3 copy-only 복구 계층
