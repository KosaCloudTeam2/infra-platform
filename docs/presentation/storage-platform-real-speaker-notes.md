# Storage Platform Real Slides 발표자 노트

> 대상 슬라이드: `docs/presentation/storage-platform-real-slides.md` 목적: 전문가/면접관 앞 발표용
> 구두 설명 보조 자료

---

## 1. 티켓팅 피크 트래픽을 받치는 저장소 플랫폼

- 이 파트가 사용자 화면이나 앱 기능 구현이 아니라, 그 뒤에서 피크 트래픽을 받치는
  저장소/이미지/캐시/백업 계층임을 먼저 정의함.
- 핵심 키워드는 Ceph RBD, Ceph RGW, Harbor/ECR, Redis, AWS S3 Backup임.
- "기술을 많이 썼다"가 아니라 "각 계층의 병목을 분리했다"는 메시지로 시작함.

발표 문장:

- "제가 설명할 부분은 티켓팅 요청 뒤에서 저장소, 컨테이너 이미지, 예매 상태, 백업을 담당하는
  계층입니다."
- "공연 기획 회사라는 시나리오에서는 이미지와 영상이 많고, 예매 오픈 시점에 트래픽이 짧게 몰립니다."

---

## 2. 시나리오

- 공연 기획 회사는 정적 자원이 많다는 점을 강조함.
- 일반 게시판보다 포스터, 좌석도, 상세 이미지, 영상이 많아 Object Storage 가치가 높음.
- 티켓팅 피크에는 앱 서버를 AWS로 늘릴 수 있지만, image pull과 예매 상태 일관성이 같이 해결되어야
  함.

질문 대비:

- "왜 AWS만 쓰지 않았는가" 질문에는 평상시 온프레 자원 활용, 비용 통제, burst만 AWS 사용이라고 답함.

---

## 3. 설계 원칙

- 역할 분리는 발표 전체의 기준임.
- Block은 RBD, Object는 RGW, image pull은 Harbor/ECR, 예매 상태는 Redis, 장기 백업은 AWS S3로 나눔.
- HDD 기반 Ceph는 한계를 숨기지 않고 검증 대상으로 명시함.

발표 문장:

- "네트워크는 10G로 구성되어 있지만, 디스크가 HDD이므로 쓰기 성능은 별도 검증 대상입니다."

---

## 4. 전체 아키텍처

- App, Redis, Ceph, Harbor/ECR, S3의 전체 흐름을 설명함.
- Redis는 양쪽 앱이 같이 보는 실시간 상태 기준점임.
- etcd는 일부러 Ceph에 올리지 않았음을 언급함.

주의:

- Redis를 "DB 대체"라고 말하지 않음.
- Ceph를 "모든 데이터를 다 해결하는 저장소"라고 말하지 않음.

---

## 5. Ceph: 하나의 저장소, 두 가지 역할

- RBD와 RGW를 구분해서 설명함.
- RBD는 block volume이고 K8s PVC/Proxmox VM에 적합함.
- RGW는 S3 API를 제공하며 Harbor image blob과 앱 Object 저장에 적합함.

표현 기준:

- 저장소 구조 설명: `Harbor image blob`
- 간단한 구두 설명: `Harbor image`

---

## 6. Ceph를 선택한 이유

- 공연 서비스의 이미지/영상 데이터 특성을 Ceph S3와 연결함.
- DB에 이미지/영상을 넣지 않고 object key만 저장하는 구조가 확장과 백업에 유리함.
- AWS S3와 같은 S3 API 계열이라 백업/이관 설명이 쉬움.

질문 대비:

- "Ceph가 꼭 필요한가" 질문에는 RBD와 RGW를 동시에 제공해 VM/PVC와 Object 저장을 한 운영 체계로 묶을
  수 있다는 점을 답함.

---

## 7. 현재 Ceph 구성의 성능 해석

- 10G 전송선의 장점과 HDD의 한계를 분리해서 말함.
- 10G는 replication/read/object transfer에 도움이 됨.
- HDD는 random write IOPS와 latency에서 병목이 될 수 있음.
- 수치가 없으면 성능 향상을 단정하지 않음.

검증 자료:

- `iperf3`: 네트워크 대역폭
- `fio`: RBD 쓰기 지연
- `rados bench`: pool read/write throughput
- `ceph osd perf`: OSD별 latency

---

## 8. Harbor / ECR

- Harbor는 온프레 Kubernetes의 내부 registry임.
- ECR은 AWS burst 환경의 pull 최적화 경로임.
- AWS 노드가 온프레 Harbor를 직접 pull하면 WAN/VPN 지연과 장애 영향이 생김.
- ECR mirror는 백업이라기보다 burst scale-out 속도 최적화임.

주의:

- ECR mirror가 Harbor metadata 백업을 대체한다고 말하지 않음.
- Harbor project/user/robot/policy는 별도 backup 대상임.

---

## 9. Backup

- Ceph replica와 backup은 목적이 다름.
- Ceph replica는 디스크/노드 장애 대응.
- AWS S3 backup은 삭제, 오염, 운영 실수 복구.
- 초기 정책은 copy-only가 안전함.

발표 문장:

- "원본 삭제가 전파되는 sync-delete 방식보다, 초기에는 같은 key 구조로 copy-only 백업을 두는 것이
  복구 검증에 안전합니다."

---

## 10. Redis: 캐시를 넘어 예매 상태 기준점

- Redis의 핵심을 DB 부하 감소에서 한 단계 더 올려 설명함.
- AWS app과 온프레 app이 서로 다른 DB replica를 보면 수초 차이로 예매 상태가 다르게 보일 수 있음.
- 좌석 hold, 예매 진행 상태, 대기열 token은 Redis 단일 기준으로 판단함.

발표 문장:

- "예매 상태는 단순 조회 캐시가 아니라, AWS와 온프레 앱이 같은 판단을 내리기 위한 기준점입니다."

---

## 11. Redis 일관성 모델

- Redis와 DB의 책임을 분리함.
- Redis: 실시간 판단, TTL, 중복 요청 방지
- DB: 최종 확정, 정산, 이력, 복구
- Redis 장애 시 정책이 필요함을 인정함.

질문 대비:

- "Redis가 죽으면 어떻게 되는가" 질문에는 Sentinel/Replica, degrade mode, DB fallback 정책을 후속
  과제로 답함.

---

## 12. etcd는 Ceph에 두지 않음

- etcd는 Kubernetes 제어 평면 핵심 데이터임.
- Ceph 장애가 Kubernetes API 장애로 확산되면 복구가 복잡해짐.
- 그래서 etcd는 local disk 유지가 더 보수적이고 안정적임.

발표 문장:

- "저장소 통합보다 장애 격리가 더 중요한 영역은 예외로 뒀습니다."

---

## 13. 검증 증거

- 이 슬라이드는 실제 캡처 삽입용임.
- 캡처가 없으면 발표에서 주장으로만 보이므로 최소 4개 이상 확보 권장.

우선순위:

1. `ceph -s`, `ceph osd tree`
2. `fio` 또는 `rados bench`
3. Harbor replication 성공 화면
4. Redis key/TTL 또는 `INFO stats`
5. AWS S3 object count
6. `findmnt /var/lib/etcd`

---

## 14. 운영상 남는 리스크

- 전문가 앞에서는 리스크를 숨기지 않는 편이 낫음.
- HDD 성능, Redis HA, Harbor metadata backup을 명확히 남겨야 함.
- 대신 각각의 대응 방향까지 같이 제시함.

발표 문장:

- "이번 구성에서 네트워크 경로는 확보했지만, HDD 기반 Ceph의 쓰기 성능은 반드시 수치로 확인해야
  합니다."

---

## 15. 결론

- 마지막은 기술명 나열보다 설계 의도를 반복함.
- 저장소, image pull, 예매 상태, 백업을 분리해 피크 시간의 병목을 줄이는 구조임.
- Ceph/Harbor/Redis/AWS S3가 각각 다른 문제를 해결한다는 점을 강조함.

마무리 문장:

- "결론적으로 이 구조는 티켓팅 피크 시간에 앱 서버만 늘리는 것이 아니라, 저장소와 image pull, 예매
  상태 기준점까지 같이 확장 가능하게 분리한 설계입니다."
