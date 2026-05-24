# Storage Platform Real Slides 발표자 노트

> 대상: `docs/presentation/storage-platform-real-slides.md` 목적: 실제 발표 시 그대로 읽거나 참고할
> 수 있는 발표 대본

---

## 1. 티켓팅 피크 트래픽을 받치는 저장소 플랫폼

### 발표 문장

안녕하세요. 제가 맡은 부분은 티켓팅 서비스의 화면 기능이 아니라, 그 뒤에서 트래픽을 받쳐 주는
저장소와 이미지 저장소, 캐시, 백업 계층입니다.

이번 시나리오는 공연 기획 회사가 티켓팅 서비스를 운영하는 상황입니다. 이런 서비스는 공연 포스터,
좌석도, 홍보 이미지, 영상 같은 정적 자원이 많고, 예매 오픈 시점에는 짧은 시간에 트래픽이 집중됩니다.

그래서 단순히 앱 서버만 늘리는 것으로는 부족합니다. 컨테이너 이미지를 빠르게 가져오는 구조, 공연
자원을 안정적으로 저장하는 구조, 예매 상태를 AWS와 온프레미스가 같은 기준으로 보는 구조, 그리고
장애나 삭제에 대비한 백업 구조가 같이 필요합니다.

오늘 설명할 핵심은 Ceph RBD, Ceph RGW, Harbor와 ECR, Redis, AWS S3 Backup입니다.

### 보충 설명

- 발표 첫 장에서는 기술 이름보다 "왜 이 파트가 필요한가"를 먼저 전달함.
- "트래픽 외 인프라 계층"이라는 표현을 사용하면 담당 범위가 명확해짐.
- Redis는 단순 캐시가 아니라 예매 상태 기준점이라는 점을 뒤에서 다시 강조함.

### 다음 슬라이드 전환

먼저 이 구조가 필요한 서비스 상황부터 정리하겠습니다.

---

## 2. 시나리오

### 발표 문장

이 프로젝트의 서비스 전제는 공연 기획 회사의 티켓팅 서비스입니다.

공연 서비스는 일반 CRUD 서비스와 다르게 정적 자원이 많습니다. 공연 포스터, 좌석 배치도, 상세 페이지
이미지, 홍보 영상 같은 파일이 계속 쌓입니다. 이런 데이터를 DB에 직접 넣으면 DB가 불필요하게 커지고,
백업과 이관도 어려워집니다.

또 하나의 특징은 트래픽 패턴입니다. 평소에는 온프레미스 Kubernetes에서 운영해도 충분하지만, 인기
공연 예매가 열리는 시점에는 갑자기 요청이 몰립니다. 이때 AWS cloud bursting으로 앱 실행 영역을
확장할 수 있어야 합니다.

다만 앱만 AWS로 늘리면 끝나는 문제가 아닙니다. AWS에서 이미지 pull이 느리면 scale-out이 늦어지고,
AWS와 온프레미스가 서로 다른 DB 상태를 보면 예매 정보가 어긋날 수 있습니다. 그래서 저장소, 이미지
pull, 예매 상태 일관성까지 같이 설계했습니다.

### 보충 설명

- "공연 이미지/영상"은 Ceph RGW 선택 이유와 연결됨.
- "예매 오픈 트래픽"은 Redis와 ECR mirror 선택 이유와 연결됨.
- "평상시 온프레, 피크 시 AWS"는 비용/성능 균형 논리임.

### 예상 질문 대응

왜 처음부터 전부 AWS로 운영하지 않았는가?

평상시에는 온프레미스 자원을 활용해 비용을 줄이고, 피크 시점에만 AWS를 확장 구간으로 쓰는
전략입니다. 이번 프로젝트의 기준도 운영용 풀 클라우드 전환이 아니라 온프레 기반 Kubernetes와 AWS
burst의 하이브리드 구조입니다.

### 다음 슬라이드 전환

이 시나리오를 기준으로 설계 원칙을 세 가지로 잡았습니다.

---

## 3. 설계 원칙

### 발표 문장

설계 원칙은 세 가지입니다.

첫 번째는 역할 분리입니다. VM과 Pod의 block volume은 Ceph RBD로 처리하고, 공연 이미지나 Harbor image
blob 같은 object 데이터는 Ceph RGW로 처리합니다. 컨테이너 image pull은 Harbor와 ECR로 나누고, 예매
상태는 Redis를 기준으로 봅니다. 백업은 AWS S3로 분리합니다.

두 번째는 피크 대응입니다. 예매 오픈 시점에는 AWS로 앱을 늘릴 수 있어야 합니다. 이때 AWS 노드가
온프레 Harbor를 직접 pull하면 WAN이나 VPN 지연이 생길 수 있기 때문에, AWS에서는 ECR mirror를
사용합니다. 예매 상태는 AWS와 온프레미스가 Redis 하나를 기준으로 판단하도록 합니다.

세 번째는 한계 명시입니다. 현재 Ceph 노드 간 연결은 10G이지만 디스크는 HDD입니다. 10G는 네트워크
병목을 줄여 주지만, HDD의 random write 성능까지 보장하지는 않습니다. 그래서 HDD 쓰기 IOPS와 RBD
latency는 반드시 측정해야 하는 항목으로 남겼습니다.

### 보충 설명

- 역할 분리: RBD/RGW/Harbor/ECR/Redis/S3의 책임 경계를 명확히 함.
- 피크 대응: 앱 서버 확장만이 아니라 image pull과 상태 기준점까지 포함.
- 한계 명시: 전문가 앞에서는 과장보다 검증 기준 제시가 신뢰도를 높임.

### 다음 슬라이드 전환

이 원칙을 전체 아키텍처에 배치하면 다음과 같습니다.

---

## 4. 전체 아키텍처

### 발표 문장

전체 구조는 세 개의 흐름으로 볼 수 있습니다.

첫 번째는 앱과 Redis 흐름입니다. 기본 앱은 온프레미스에서 동작하고, 피크 시점에는 AWS burst app이
같이 요청을 처리합니다. 이때 두 앱은 예매 상태를 Redis 기준으로 봅니다. 예매 상태가 서로 다른 DB
replica에서 몇 초 차이로 다르게 보이는 상황을 줄이기 위한 구조입니다.

두 번째는 block storage 흐름입니다. Kubernetes PVC와 Proxmox VM 디스크는 Ceph RBD를 사용합니다. VM과
Pod의 저장소 운영을 한 계층으로 묶고, 노드 장애나 이동성 측면에서 이점을 가져갑니다.

세 번째는 object와 image 흐름입니다. Harbor의 image blob과 앱의 object 데이터는 Ceph RGW에
저장합니다. Harbor image는 AWS burst 환경에서 빠르게 pull할 수 있도록 ECR로 mirror합니다. 정적 자원
백업은 AWS S3로 보냅니다.

중요한 예외도 있습니다. Kubernetes 제어 평면의 etcd는 Ceph에 두지 않고 control-plane local disk에
둡니다. 제어 평면 장애와 스토리지 장애를 결합하지 않기 위한 선택입니다.

### 보충 설명

- 이 슬라이드에서는 흐름을 설명하고, 세부 기술 설명은 다음 슬라이드로 넘김.
- Redis를 "캐시"라고만 하지 말고 "예매 상태 기준점"이라고 함께 말함.
- etcd 예외는 설계 판단 포인트로 짚음.

### 다음 슬라이드 전환

먼저 Ceph부터 보겠습니다. Ceph는 하나의 저장소처럼 보이지만 실제로는 두 가지 역할로 나눠
사용했습니다.

---

## 5. Ceph: 하나의 저장소, 두 가지 역할

### 발표 문장

Ceph는 이번 구조에서 두 가지 역할을 합니다.

첫 번째는 Ceph RBD입니다. RBD는 block device를 제공하기 때문에 Kubernetes PVC와 Proxmox VM 디스크에
적합합니다. Pod가 재생성돼도 데이터를 유지해야 하거나, VM 디스크를 노드에 묶지 않고 운영하고 싶을 때
유리합니다.

두 번째는 Ceph RGW입니다. RGW는 S3 호환 Object Storage입니다. 여기에는 Harbor image blob과 앱
Object를 저장합니다.

공연 기획 회사 시나리오에서는 포스터, 좌석도, 영상 자료가 많기 때문에 앱 Object 저장소로 Ceph RGW를
사용하는 가치가 있습니다.

_참고: 발표 중 구두 표현은 Harbor image로 단순화 가능. 저장소 구조를 정확히 설명할 때는 Harbor image
blob 표현 사용. registry는 이미지 레이어와 manifest 같은 blob 저장 구조._

### 보충 설명

- `Harbor image blob`: 저장소 구조 설명용 표현.
- `Harbor image`: 발표 중 흐름 설명용 표현.
- RBD와 RGW를 섞어 말하면 혼동이 커지므로 반드시 분리함.

### 예상 질문 대응

왜 CephFS가 아니라 RBD인가?

VM 디스크와 일반적인 Kubernetes PVC는 block volume 모델이 더 직접적입니다. 공유 파일시스템이 필요한
workload라면 CephFS를 검토할 수 있지만, 현재 발표 범위에서는 K8s PVC와 VM 디스크를 RBD 기준으로
설명하는 것이 맞습니다.

### 다음 슬라이드 전환

그럼 왜 공연 서비스에서 Ceph, 특히 S3 호환 Object Storage가 의미 있는지 보겠습니다.

---

## 6. Ceph를 선택한 이유

### 발표 문장

Ceph를 선택한 이유는 공연 서비스의 데이터 특성과 맞기 때문입니다.

공연 서비스에는 포스터, 좌석도, 상세 페이지 이미지, 홍보 영상, 썸네일 같은 파일이 많습니다. 이런
파일을 DB에 직접 저장하면 DB 백업과 성능, 이관이 모두 부담스러워집니다. 대신 앱은 DB에 object key만
저장하고, 실제 파일은 Object Storage에 두는 구조가 더 적합합니다.

Ceph RGW는 S3 API를 제공하기 때문에 앱 입장에서는 S3와 유사한 방식으로 접근할 수 있습니다. 나중에
AWS S3로 백업하거나 일부 자원을 이전할 때도 key 구조를 유지하면 복구와 전환이 단순해집니다.

또 Ceph는 RBD와 RGW를 함께 제공하므로 VM/PVC용 block storage와 앱 자원용 object storage를 한 운영
체계 안에서 설명할 수 있습니다. 이것이 단순히 "스토리지를 하나 더 붙였다"가 아니라 플랫폼 계층으로
의미를 갖는 지점입니다.

### 보충 설명

- DB blob 저장 회피.
- object key 중심 설계.
- Ceph RGW -> AWS S3 backup 흐름의 근거.

### 다음 슬라이드 전환

다만 현재 Ceph 구성은 성능을 해석할 때 주의가 필요합니다.

---

## 7. 현재 Ceph 구성의 성능 해석

### 발표 문장

현재 Ceph 구성에서 노드 간 연결은 10G입니다. 이 점은 분명한 장점입니다. Ceph replication traffic,
Harbor image blob read, Object Storage read, 백업 원본 읽기에는 네트워크 대역폭이 중요합니다.

하지만 디스크는 HDD입니다. 10G 네트워크가 있다고 해서 HDD의 random write IOPS가 좋아지는 것은
아닙니다. 특히 RBD를 VM 디스크나 PVC로 사용할 때 random write가 많으면 HDD seek latency가 병목이 될
수 있습니다.

그래서 성능은 두 가지로 분리해서 봐야 합니다. 네트워크 전송 경로는 10G로 확보했습니다. 다만 HDD 기반
쓰기 성능은 fio와 rados bench로 확인해야 하는 영역입니다. 실제 운영에서 고 IOPS가 필요한 hot path나
DB성 workload는 SSD/NVMe OSD 또는 별도 고성능 디스크 구성을 전제로 검토하는 것이 맞습니다.

### 보충 설명

- 과장 금지: "10G니까 빠르다"가 아니라 "네트워크 병목은 줄였고, 디스크 쓰기는 검증 대상".
- 캡처가 있다면 `iperf3`, `fio`, `rados bench`, `ceph osd perf`.

### 예상 질문 대응

HDD 기반 Ceph가 실서비스에 적합한가?

Object 중심 workload나 read 비중이 높은 자원 저장에는 설명 가능하지만, random write가 많은 DB성
workload는 반드시 측정이 필요합니다. 운영 전제라면 SSD/NVMe 또는 tiering을 검토해야 합니다.

### 다음 슬라이드 전환

다음은 컨테이너 이미지 저장과 AWS burst 시 image pull 경로입니다.

---

## 8. Harbor / ECR: 실행 위치별 image pull 최적화

### 발표 문장

Harbor와 ECR은 실행 위치별로 image pull 경로를 최적화하기 위해 나눴습니다.

온프레미스 Kubernetes는 내부 Harbor에서 이미지를 가져옵니다. 이렇게 하면 외부 registry 의존도를
줄이고, 내부망에서 빠르게 pull할 수 있습니다. Harbor의 storage backend는 Ceph RGW를 사용해 Harbor
image blob을 object 형태로 저장합니다.

반대로 AWS burst 환경에서는 ECR을 사용합니다. AWS 노드가 온프레 Harbor를 직접 pull하면 WAN이나 VPN
경로를 지나야 해서 scale-out 시점에 지연이 생길 수 있습니다. 그래서 Harbor에서 ECR로 image를
mirror하고, AWS에서는 같은 리전의 ECR에서 pull하도록 구성합니다.

이 ECR mirror는 Harbor 전체 백업이 아닙니다. 목적은 AWS burst 시 image pull 속도와 cold start를
줄이는 것입니다. Harbor project, user, robot account, replication policy 같은 metadata는 별도 백업
대상입니다.

### 보충 설명

- Harbor: 온프레 원본 registry.
- ECR: AWS 실행 환경용 mirror.
- ECR mirror를 백업으로 과장하지 않음.

### 다음 슬라이드 전환

이미지 pull 경로와 별도로, 공연 이미지와 영상 같은 정적 자원은 백업 정책이 필요합니다.

---

## 9. Backup: 복제와 백업을 분리

### 발표 문장

백업 구조의 핵심은 Ceph replica와 AWS S3 backup을 분리하는 것입니다.

Ceph replica는 디스크나 노드 장애에 대응하기 위한 구조입니다. 예를 들어 OSD 하나가 죽어도 replica가
남아 있으면 서비스 중단을 줄일 수 있습니다. 하지만 사용자가 파일을 잘못 삭제하거나, 애플리케이션
버그로 object가 오염되거나, 운영자가 잘못 덮어쓴 경우에는 replica도 같은 상태가 될 수 있습니다.

그래서 정적 자원은 Ceph RGW를 운영 원본으로 두고, AWS S3에 copy-only 방식으로 2차 백업합니다.
초기에는 원본 삭제를 전파하지 않는 것이 안전합니다. object key를 동일하게 유지하면 복구할 때 DB의
object key를 그대로 사용할 수 있어 복구 절차가 단순해집니다.

S3 Lifecycle은 장기 보관 비용을 줄이기 위한 수단입니다. 다만 Glacier로 이동한 객체는 즉시 조회
대상이 아니므로, 서비스에서 바로 읽는 active object와 archive object를 구분해야 합니다.

### 보충 설명

- replica != backup.
- copy-only는 발표에서 안정적인 선택으로 설명.
- Harbor image mirror와 앱 Object backup은 별도 경로.

### 다음 슬라이드 전환

다음은 이번 구조에서 Redis가 왜 단순 캐시 이상의 의미를 갖는지 설명하겠습니다.

---

## 10. Redis: 캐시를 넘어 예매 상태 기준점

### 발표 문장

Redis는 DB 부하 감소를 위한 캐시 역할도 하지만, 이번 시나리오에서는 더 중요한 역할이 있습니다. 바로
예매 상태의 기준점입니다.

피크 시간에는 온프레미스 앱과 AWS burst 앱이 동시에 요청을 처리합니다. 이때 한쪽은 온프레 DB를 보고,
다른 한쪽은 RDS Read Replica를 본다고 가정하면 몇 초 차이의 복제 지연이 생길 수 있습니다.
티켓팅에서는 이 몇 초 차이가 같은 좌석을 다르게 판단하는 문제로 이어질 수 있습니다.

그래서 좌석 hold, 예매 진행 상태, 대기열 token, idempotency key 같은 중요한 예매 정보는 Redis 단일
endpoint를 기준으로 봅니다. AWS 앱과 온프레 앱이 같은 Redis key를 보고 판단하면, 서로 다른 DB
replica를 보는 것보다 일관성을 더 강하게 통제할 수 있습니다.

다만 Redis가 DB를 대체하는 것은 아닙니다. Redis는 실시간 판단 경로이고, 최종 예매 확정과 정산,
이력은 DB에 저장합니다.

### 보충 설명

- DB 부하 감소 + 상태 일관성 두 축.
- RDS Read Replica는 비동기 지연 가능성 때문에 예매 상태 판단 경로에서 제외.
- Redis HA는 후속 리스크로 남김.

### 예상 질문 대응

Redis 하나만 보면 단일 장애점 아닌가?

맞습니다. 그래서 운영 구조에서는 Sentinel/Replica 또는 managed Redis HA가 필요합니다. 현재 설계에서
중요한 점은 예매 상태의 기준점을 여러 DB replica로 분산하지 않고 하나로 통일한다는 것입니다.

### 다음 슬라이드 전환

Redis와 DB의 책임을 조금 더 구체적으로 나누면 다음과 같습니다.

---

## 11. Redis 일관성 모델

### 발표 문장

Redis와 DB의 책임은 명확히 나눕니다.

Redis는 실시간 판단에 사용합니다. 좌석 hold 상태, 예매 진행 상태, 대기열 token, 중복 요청 방지를
위한 idempotency key가 여기에 해당합니다. 이런 값들은 TTL이 중요합니다. 예를 들어 좌석 hold는 일정
시간이 지나면 자동으로 풀려야 합니다.

DB는 최종 확정과 이력을 담당합니다. 결제가 완료되고 예매가 확정되면 DB에 영속 저장하고, 정산과 감사,
복구 기준 데이터로 사용합니다.

따라서 Redis는 DB를 대체하는 저장소가 아니라, 피크 시간에 빠르고 일관된 판단을 내리기 위한 실시간
상태 계층입니다. DB commit 이후에는 관련 Redis key를 갱신하거나 삭제해서 stale 상태가 오래 남지
않도록 해야 합니다.

### 보충 설명

- Redis: 빠른 판단, TTL, 중복 방지.
- DB: 확정 저장, 정산, 이력.
- cache-aside보다 예매 상태 key 설계가 더 중요한 메시지.

### 다음 슬라이드 전환

다음은 저장소를 통합하면서도 일부러 Ceph에 두지 않은 영역입니다.

---

## 12. etcd는 Ceph에 두지 않음

### 발표 문장

Ceph를 저장소 플랫폼으로 사용한다고 해서 모든 데이터를 Ceph에 올리는 것은 아닙니다. 대표적인 예외가
Kubernetes의 etcd입니다.

etcd는 Kubernetes 제어 평면의 핵심 데이터입니다. API Server와 cluster state가 여기에 의존합니다.
만약 etcd까지 Ceph RBD에 올리면, Ceph 장애가 Kubernetes 제어 평면 장애로 이어질 수 있습니다. 더 나쁜
경우 Kubernetes가 Ceph 복구를 도와야 하는데, 그 Kubernetes 제어 평면이 Ceph에 의존하는 순환 구조가
될 수 있습니다.

그래서 etcd는 control-plane local disk에 유지합니다. 이 결정은 저장소 통합보다 장애 격리를 우선한
선택입니다.

### 보충 설명

- "모든 것을 Ceph로"가 아니라 "적절한 것만 Ceph로".
- 전문가 앞에서 설계 경계가 있는 점을 보여주는 슬라이드.

### 다음 슬라이드 전환

지금까지 설명한 구조는 실제 검증 자료가 있어야 설득력이 생깁니다.

---

## 13. 검증 증거

### 발표 문장

이 구조는 주장만으로 끝나면 설득력이 약합니다. 그래서 각 설계 포인트를 실제 명령 결과와 운영
화면으로 검증합니다.

Ceph는 `ceph -s`, `ceph osd tree`, pool detail, RBD image 확인으로 상태를 보여줄 수 있습니다. 10G와
HDD 성능은 `iperf3`, `fio`, `rados bench`로 네트워크와 디스크 쓰기를 분리해서 검증합니다.

Harbor와 ECR은 replication execution 성공 화면과 ECR image tag 목록으로 확인합니다. 백업은 AWS S3
object count와 Lifecycle 설정, Redis는 key TTL이나 `INFO stats`, etcd는 `findmnt /var/lib/etcd`로
local disk 사용을 확인합니다.

이 캡처들이 있으면 단순 설계 발표가 아니라 실제 구현과 검증에 기반한 발표가 됩니다.

### 캡처 우선순위

1. `ceph -s`, `ceph osd tree`
2. `fio` 또는 `rados bench`
3. Harbor replication 성공 화면
4. Redis key/TTL 또는 `INFO stats`
5. AWS S3 object count
6. `findmnt /var/lib/etcd`

### 다음 슬라이드 전환

마지막으로, 현재 구조에서 남는 운영 리스크를 숨기지 않고 정리하겠습니다.

---

## 14. 운영상 남는 리스크

### 발표 문장

현재 구조에서 남는 리스크도 명확합니다.

첫 번째는 HDD 기반 Ceph의 쓰기 성능입니다. 네트워크는 10G로 확보했지만, random write IOPS는 HDD
특성상 한계가 있을 수 있습니다. 이 부분은 fio와 rados bench로 수치화해야 합니다.

두 번째는 Redis의 단일 장애점입니다. 예매 상태를 Redis 기준으로 통일하는 대신 Redis의 가용성이
중요해집니다. 운영 단계에서는 Sentinel, Replica, 또는 managed Redis HA 구성이 필요합니다.

세 번째는 Harbor metadata 백업입니다. ECR mirror는 image pull 가능성을 높이지만 Harbor의 project,
user, robot account, replication policy까지 백업하는 것은 아닙니다. Harbor DB와 설정 백업은 별도
운영 항목으로 분리해야 합니다.

이렇게 리스크를 분리해서 말하는 이유는, 현재 구조가 완성형이라는 주장이 아니라 어떤 부분을 검증하고
강화해야 하는지 분명한 구조라는 점을 보여주기 위해서입니다.

### 보충 설명

- 리스크만 나열하지 말고 대응 방향까지 같이 말함.
- HDD, Redis HA, Harbor metadata가 핵심.

### 다음 슬라이드 전환

이제 전체 결론을 정리하겠습니다.

---

## 15. 결론

### 발표 문장

정리하면, 이 구조의 목표는 단순히 여러 기술을 붙이는 것이 아닙니다. 티켓팅 피크 시간에 병목이 생길
수 있는 영역을 분리해서 처리하는 것입니다.

Ceph RBD는 Kubernetes PVC와 Proxmox VM 디스크를 담당합니다. Ceph RGW는 Harbor image blob과 앱
Object를 저장합니다. Harbor와 ECR은 실행 위치에 따라 image pull 경로를 나누어 AWS burst scale-out
지연을 줄입니다.

Redis는 DB 부하를 줄이는 동시에 AWS와 온프레미스가 같은 예매 상태를 보도록 하는 기준점입니다. AWS
S3는 Ceph RGW의 정적 자원을 2차 백업하고 장기 보관하는 역할을 합니다.

결국 이 설계는 앱 서버만 늘리는 구조가 아니라, 저장소, image pull, 예매 상태, 백업까지 함께 분리해
티켓팅 피크 상황을 견디기 위한 인프라 구조입니다.

### 마무리 문장

저는 이 파트의 핵심을 "공연 자원 저장, image pull 최적화, 예매 상태 기준점 통일, 백업 경로 분리"로
정리하겠습니다.
