---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: "Noto Sans KR", "Malgun Gothic", Arial, sans-serif;
    color: #1f2933;
  }
  h1 {
    font-size: 44px;
    color: #0f172a;
  }
  h2 {
    font-size: 34px;
    color: #0f172a;
  }
  h3 {
    font-size: 26px;
    color: #1e3a5f;
  }
  ul, ol {
    font-size: 24px;
    line-height: 1.42;
  }
  table {
    font-size: 18px;
  }
  code {
    font-size: 18px;
  }
  .lead {
    font-size: 30px;
    line-height: 1.45;
    color: #334155;
  }
  .small {
    font-size: 18px;
    color: #475569;
  }
  .two-col {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 28px;
    align-items: start;
  }
  .three-col {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 20px;
    align-items: stretch;
  }
  .card {
    border: 1px solid #cbd5e1;
    border-radius: 8px;
    padding: 18px 20px;
    min-height: 160px;
    background: #f8fafc;
  }
  .card h3 {
    margin-top: 0;
  }
  .placeholder {
    border: 3px dashed #94a3b8;
    border-radius: 8px;
    height: 430px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #64748b;
    font-size: 28px;
    background: #f8fafc;
  }
  .placeholder-small {
    border: 3px dashed #94a3b8;
    border-radius: 8px;
    height: 250px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #64748b;
    font-size: 22px;
    background: #f8fafc;
  }
  .flow {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: center;
    margin-top: 32px;
    font-size: 21px;
  }
  .box {
    border: 1px solid #64748b;
    border-radius: 8px;
    padding: 15px 18px;
    background: #f8fafc;
    text-align: center;
    min-width: 135px;
  }
  .arrow {
    color: #475569;
    font-weight: 700;
  }
---

# Ceph · Harbor · Backup · Redis

<div class="lead">
공연 기획 회사 티켓팅 서비스<br>
트래픽 외 인프라 성능 계층<br>
저장소 · 이미지 저장소 · 백업 · 캐시
</div>

<br>

- 10G 온프레미스 기반 저장소 구조
- AWS burst 환경 이미지 pull 최적화
- 공연 이미지/동영상 S3 자원 저장
- 정적 자원 백업과 복구 기준
- Redis 기반 DB 부하 감소와 일관성 보조

---

# 발표 목표

- 왜 이 기술을 썼는지 설명
- 왜 현재 설정을 선택했는지 설명
- 사용자 요청 뒤쪽의 인프라 계층 설명
- Ceph RBD와 RGW 사용 구분 설명
- Harbor 자체 레지스트리와 ECR 미러링 이유 설명
- Ceph RGW와 AWS S3 백업 구조 설명
- Redis 유무 차이와 DB 일관성 기준 설명
- HDD 기반 Ceph 성능 고려사항 제시

---

# 시나리오 전제

## 공연 기획 회사

- 공연/콘서트 티켓팅 서비스 제공
- 예매 오픈 시점 트래픽 단기 폭증
- 포스터, 좌석도, 홍보 이미지, 영상 자료 다량 보유
- 평상시 온프레미스 운영
- 피크 시간 AWS cloud bursting 확장
- 정적 자원 저장과 burst 대응이 핵심

---

# 기술 선택과 효용가치

| 기술          | 사용 이유                  | 효용가치                           |
| :------------ | :------------------------- | :--------------------------------- |
| Ceph RBD      | K8s PVC, Proxmox VM 디스크 | 저장소 운영 통합                   |
| Ceph RGW      | Harbor, 앱 S3 자원         | Harbor image blob / 앱 Object 저장 |
| Harbor        | 내부 이미지 저장소         | 온프레 pull 속도                   |
| ECR Mirror    | AWS burst pull             | cold start 감소                    |
| AWS S3 Backup | 정적 자원 2차 백업         | 삭제/오염 복구                     |
| Redis         | 예매 상태 기준점           | DB 부하 감소 + 일관성              |

---

# 왜 현재 설정인가

| 설정                 | 대안                   | 선택 이유             |
| :------------------- | :--------------------- | :-------------------- |
| RBD for K8s/VM       | 로컬 디스크, NFS       | block volume 통합     |
| RGW for Harbor       | filesystem backend     | object blob 저장 적합 |
| Ceph S3 for 앱 자원  | DB blob 저장           | 이미지/영상 분리      |
| Harbor -> ECR        | AWS가 Harbor 직접 pull | burst pull 지연 감소  |
| Redis 예매 상태 기준 | RDS Read Replica 조회  | AWS/온프레 판단 통일  |
| etcd local           | etcd on Ceph           | 제어 평면 장애 격리   |

---

# 담당 범위

| 구분     | 담당 내용                     | 발표 핵심                |
| :------- | :---------------------------- | :----------------------- |
| Ceph RBD | K8s PVC, Proxmox VM           | block storage            |
| Ceph RGW | Harbor, 앱 S3 자원            | object storage           |
| Harbor   | 사내 자체 이미지 저장소       | 내부 pull, ECR mirror    |
| Backup   | 정적 자원, 이미지, 장기 보관  | Ceph RGW -> AWS S3       |
| Redis    | 캐시, 일관성 보조, burst 흡수 | DB 부하 감소 + 예매 기준 |
| etcd     | 제어 평면 데이터              | 로컬 디스크 유지         |

---

# 전체 구조

<div class="flow">
  <div class="box">App Pod</div>
  <div class="arrow">→</div>
  <div class="box">Redis</div>
  <div class="arrow">→</div>
  <div class="box">ProxySQL / PXC</div>
</div>

<div class="flow">
  <div class="box">공연 이미지/영상</div>
  <div class="arrow">→</div>
  <div class="box">Ceph RGW / App S3</div>
  <div class="arrow">→</div>
  <div class="box">AWS S3 Backup</div>
</div>

<div class="flow">
  <div class="box">CI Build</div>
  <div class="arrow">→</div>
  <div class="box">Harbor</div>
  <div class="arrow">→</div>
  <div class="box">AWS ECR</div>
  <div class="arrow">→</div>
  <div class="box">AWS Burst App</div>
</div>

<div class="flow">
  <div class="box">VM / Pod PVC</div>
  <div class="arrow">→</div>
  <div class="box">Ceph RBD</div>
  <div class="box">etcd</div>
  <div class="arrow">→</div>
  <div class="box">Local Disk</div>
</div>

---

# 발표 관점

- 트래픽 외 계층 중심
- 앱 서버보다 저장소/캐시/이미지/백업 계층 중심
- 속도보다 일관성, 복구성, 운영 가능성 중심
- 단일 기능보다 장애 시 설명 가능한 구조 중심
- "Ceph 복제"와 "백업" 목적 분리
- "Redis 캐시"와 "DB 원본" 역할 분리
- "ECR 미러"와 "Harbor 전체 백업" 범위 분리
- "10G 네트워크"와 "HDD 쓰기 성능" 범위 분리

---

# Ceph 핵심

<div class="two-col">
<div>

## 역할

- RBD: VM 디스크, Pod PVC
- RGW: Harbor, 앱 S3 자원
- OSD: 실제 디스크 저장
- MON/MGR: 합의와 관리

</div>
<div>

## 도입 이유

- 10G 내부망 활용
- 외부 인터넷 경유 제거
- RBD로 K8s/VM 저장소 통합
- RGW로 Harbor blob 저장
- 공연 이미지/영상 Object 저장
- 장애 범위와 복구 절차 통제

</div>
</div>

---

# Ceph 저장소 매핑

| 대상                 | 저장소         | 이유                      |
| :------------------- | :------------- | :------------------------ |
| Proxmox VM 디스크    | Ceph RBD       | VM 이동성, 노드 장애 대응 |
| Kubernetes Pod PVC   | Ceph RBD       | Pod 재생성 후 데이터 유지 |
| Harbor registry blob | Ceph RGW       | 이미지 저장소 내부화      |
| 공연 이미지/영상     | Ceph RGW/S3    | 대용량 정적 자원 분리     |
| etcd 데이터          | 로컬 디스크    | 제어 평면 장애 격리       |
| DB 주 데이터         | 실제 배치 확인 | 고 IOPS, 저지연 요구      |

---

# Ceph 캡처 위치

<div class="placeholder">
Ceph 상태 / OSD / Pool / RBD / PVC 캡처
</div>

<div class="small">
추천 캡처: ceph -s, ceph osd tree, ceph osd pool ls detail, Proxmox RBD Storage, kubectl get pvc,pv
</div>

---

# 10G와 IOPS

<div class="two-col">
<div>

## 현재 구성

- Ceph OSD: HDD
- 노드 간 연결: 10G
- 네트워크 전송속도: 빠른 편
- HDD 쓰기 성능: 미확인
- random write IOPS: 검증 대상

</div>
<div>

## 발표 기준

- 10G는 네트워크 병목 완화
- HDD 쓰기는 별도 측정 필요
- object 중심 workload 설명 가능
- 고 IOPS는 SSD/NVMe 전제
- fio/rados bench 캡처 필요

</div>
</div>

---

# HDD 기반 Ceph 고려사항

- 10G 연결: 노드 간 복제/전송 경로 개선
- HDD 한계: seek latency, random write IOPS 제한 가능성
- RBD write latency: VM/PVC 체감 성능 영향
- RGW object upload: 순차 처리 비중으로 상대적 유리 가능성
- 실서비스 전제: hot data와 DB성 workload는 SSD/NVMe 검토
- 발표 표현: "네트워크는 빠르지만 디스크 쓰기는 측정 필요"

---

# 10G · IOPS 캡처 위치

<div class="placeholder">
10G 링크 / iperf3 / fio / rados bench 결과 캡처
</div>

<div class="small">
추천 캡처: ethtool, ip -d link show, iperf3, fio, rados bench, ceph osd perf
</div>

---

# etcd 로컬 유지

## 초기 착오

- 모든 저장소 Ceph 통합 관점
- etcd까지 Ceph RBD 배치 가능성 검토
- 제어 평면과 스토리지 장애 결합 위험

## 해결

- etcd 데이터 디렉터리 로컬 디스크 유지
- Ceph 적용 범위에서 etcd 제외
- VM/Pod/Object 저장소와 제어 평면 저장소 분리
- 장애 격리와 복구 가능성 우선

---

# etcd 캡처 위치

<div class="placeholder">
etcd local disk 확인 캡처
</div>

<div class="small">
추천 캡처: /etc/kubernetes/manifests/etcd.yaml, findmnt /var/lib/etcd, lsblk
</div>

---

# Harbor 핵심

<div class="two-col">
<div>

## Harbor 역할

- 사내 자체 이미지 저장소
- 온프레 K8s 내부 pull
- 프로젝트별 이미지 관리
- CI/CD 연동 기준점
- Ceph RGW storage 활용

</div>
<div>

## 도입 이유

- 외부 registry 의존도 감소
- 내부망 image pull 속도 확보
- 이미지 저장 위치 통제
- 발표 환경 네트워크 영향 감소
- Harbor image blob 저장

</div>
</div>

---

# Harbor -> ECR 미러링

<div class="flow">
  <div class="box">Developer / CI</div>
  <div class="arrow">→</div>
  <div class="box">Harbor</div>
  <div class="arrow">→</div>
  <div class="box">ECR Seoul</div>
  <div class="arrow">→</div>
  <div class="box">AWS Burst App</div>
</div>

<br>

- AWS 노드의 온프레 Harbor 직접 pull 지연 제거
- AWS 리전 내부 ECR pull 경로 사용
- cloud bursting cold start 시간 감소
- 티켓팅 피크 scale-out 시간 감소
- Harbor 장애 또는 WAN 지연 영향 완화
- image pull 최적화 목적
- Harbor metadata 전체 백업 아님

---

# Harbor 캡처 위치

<div class="placeholder">
Harbor UI / Replication / ECR image tag 캡처
</div>

<div class="small">
추천 캡처: Harbor artifact, Harbor replication execution, AWS ECR image list, Kubernetes image pull event
</div>

---

# Backup 핵심

| 데이터           | 원본             | 백업/복제              | 정책              |
| :--------------- | :--------------- | :--------------------- | :---------------- |
| 공연 이미지/영상 | Ceph RGW/S3      | AWS S3                 | copy-only         |
| 정적 자원        | Ceph RGW/S3      | AWS S3                 | key 유지          |
| Harbor image     | Harbor           | AWS ECR                | event replication |
| Harbor metadata  | Harbor DB/config | 별도 필요              | 한계 명시         |
| DB 데이터        | PXC              | XtraBackup/binlog 후보 | 범위 확인         |
| etcd snapshot    | control-plane    | 별도 후보              | 범위 확인         |

---

# Ceph RGW -> AWS S3

<div class="flow">
  <div class="box">공연 이미지/영상</div>
  <div class="arrow">→</div>
  <div class="box">Ceph RGW Bucket</div>
  <div class="arrow">→</div>
  <div class="box">Backup Runner</div>
  <div class="arrow">→</div>
  <div class="box">AWS S3 Bucket</div>
  <div class="arrow">→</div>
  <div class="box">Lifecycle / Glacier</div>
</div>

<br>

- 원본 삭제 금지 중심 copy-only
- Ceph key와 AWS S3 key 동일 유지
- 운영 bucket 직접 덮어쓰기 금지
- restore-test bucket 또는 prefix 우선
- S3 Lifecycle 기반 장기 보관 비용 절감
- Glacier 객체 즉시 조회 대상 제외

---

# Backup 캡처 위치

<div class="placeholder">
RGW bucket / rclone / AWS S3 / Lifecycle 캡처
</div>

<div class="small">
추천 캡처: radosgw-admin bucket stats, rclone dry-run, rclone copy, aws s3 ls --summarize, S3 Lifecycle
</div>

---

# Redis 핵심

<div class="two-col">
<div>

## 역할

- 인메모리 캐시
- DB 앞단 반복 조회 흡수
- 세션 저장소 후보
- rate limit 카운터 후보
- AWS burst 공유 상태 후보
- DB 일관성 보조
- 예매 상태 단일 기준점

</div>
<div>

## 효과

- 공연/좌석 조회 반복 요청 흡수
- DB query 감소
- DB connection pressure 감소
- 반복 조회 응답 시간 감소
- AWS burst traffic 흡수
- 온프레/AWS 동일 캐시 기준
- RDS Read Replica 지연 회피
- 예매 상태 판단 기준 통일
- TTL 기반 stale data 제한

</div>
</div>

---

# 예매 정보 일관성

<div class="flow">
  <div class="box">On-prem App</div>
  <div class="arrow">→</div>
  <div class="box">Redis 단일 기준</div>
  <div class="arrow">←</div>
  <div class="box">AWS Burst App</div>
</div>

<div class="flow">
  <div class="box">좌석 hold</div>
  <div class="box">예매 진행 상태</div>
  <div class="box">대기열 token</div>
</div>

<br>

- RDS Read Replica / 온프레 DB 간 수초 지연 가능
- 중요 예매 정보는 Redis key 기준 판단
- DB는 최종 확정 저장과 정산 기준
- Redis HA와 TTL 정책 필요

---

# Redis와 DB 일관성

<div class="flow">
  <div class="box">Read Request</div>
  <div class="arrow">→</div>
  <div class="box">Redis Hit</div>
  <div class="arrow">→</div>
  <div class="box">Response</div>
</div>

<div class="flow">
  <div class="box">Redis Miss</div>
  <div class="arrow">→</div>
  <div class="box">DB Read</div>
  <div class="arrow">→</div>
  <div class="box">Redis Set + TTL</div>
</div>

<div class="flow">
  <div class="box">Write Request</div>
  <div class="arrow">→</div>
  <div class="box">DB Commit</div>
  <div class="arrow">→</div>
  <div class="box">Cache Invalidate</div>
</div>

<br>

- DB: 원본 데이터
- Redis: 실시간 예매 상태와 캐시 기준점
- AWS/온프레 모두 Redis 단일 endpoint 조회
- cache-aside + 예매 상태 key 기준 설명
- DB commit 후 cache 삭제 또는 갱신

---

# Redis 유무 비교

| 항목        | Redis 없음        | Redis 있음          | 효과           |
| :---------- | :---------------- | :------------------ | :------------- |
| 공연 조회   | DB 직접 조회      | Redis hit           | 응답 지연 감소 |
| DB query    | 높음              | 낮음                | DB 부하 감소   |
| AWS burst   | DB 집중           | Redis 흡수          | DB 보호        |
| 예매 상태   | replica 지연 가능 | Redis 단일 key      | 판단 기준 통일 |
| 일관성      | DB 기준           | TTL/invalidate 필요 | 정책 필요      |
| 장애 리스크 | DB 병목           | Redis HA 필요       | 한계 명시      |

---

# Redis 캡처 위치

<div class="placeholder">
Redis INFO / hit-miss / latency / k6 비교 캡처
</div>

<div class="small">
추천 캡처: redis-cli INFO memory, INFO stats, ROLE, keyspace_hits, keyspace_misses, k6 p95 latency
</div>

---

# 구현 여부 검증

| 영역    | 검증 명령                      | 통과 기준            |
| :------ | :----------------------------- | :------------------- |
| Ceph    | `ceph -s`, `ceph osd tree`     | HEALTH_OK, OSD up/in |
| RBD/PVC | `kubectl get pvc,pv`           | PVC Bound, Ceph CSI  |
| etcd    | `findmnt /var/lib/etcd`        | local disk           |
| Harbor  | `docker push/pull`, UI         | artifact 생성        |
| ECR     | `aws ecr describe-images`      | tag/digest 표시      |
| Backup  | `rclone copy`, `aws s3 ls`     | object count 일치    |
| Redis   | `redis-cli PING`, `INFO stats` | PONG, hit/miss 변화  |

---

# 현재 저장소 기준 주의

- FlaskApp Ceph S3 연동 코드 흔적 존재
- `get_s3_client`, `put_object`, `get_object`, `object_key`
- Redis 구현 흔적은 저장소 기준 부족
- Harbor/Ceph live 구성은 실환경 명령 필요
- 백업 자동화는 실행 로그와 S3 object count 필요
- HDD 기반 Ceph 쓰기 성능은 fio/rados bench 필요
- 발표 시 구현 완료와 설계/후속 적용 분리 필요

---

# 검증 캡처 종합

<div class="three-col">
<div class="placeholder-small">Ceph / 10G</div>
<div class="placeholder-small">Harbor / ECR</div>
<div class="placeholder-small">Backup / S3</div>
</div>

<br>

<div class="three-col">
<div class="placeholder-small">Redis</div>
<div class="placeholder-small">etcd Local</div>
<div class="placeholder-small">성능 비교</div>
</div>

---

# 예상 질문

## 왜 Ceph S3?

- 공연 이미지/동영상 다량 보관
- DB blob 저장 회피
- S3 API 호환

## HDD 성능 괜찮은가?

- 10G는 네트워크 이점
- HDD 쓰기 IOPS는 측정 필요
- 운영은 SSD/NVMe 검토

---

# 예상 질문 2

## ECR 미러링은 백업?

- image pull 가능 복제본
- Harbor metadata 전체 백업 아님
- 배포 성능 최적화 목적

## Redis 장애 시 영향?

- cache-aside면 DB fallback 가능
- 응답 지연과 DB 부하 증가
- Sentinel/Replica 필요성

## Redis와 예매 일관성?

- AWS/온프레 모두 Redis 기준
- RDS Read Replica 지연 회피
- DB는 최종 저장 기준

## Ceph 복제면 백업 불필요?

- 불필요 아님
- 복제와 백업 목적 분리

---

# 발표 금지 표현

- Ceph에 저장했으니 백업 완료
- Redis가 있으니 DB 일관성 자동 보장
- RDS Read Replica로 예매 일관성 자동 보장
- ECR 미러링이 Harbor 전체 백업
- 10G라서 무조건 빠름
- RAM 추가로 성능 몇 배 향상
- etcd도 Ceph에 올림
- AWS 트래픽도 아무 설정 없이 온프레 Redis 사용
- 10G라서 HDD 쓰기 성능도 충분함
- ECR 미러링이 Harbor metadata 백업임

---

# 결론

<div class="lead">
트래픽 외 인프라 병목 완화와 복구 가능성 확보
</div>

<br>

- Ceph: 10G 온프레 저장소 계층
- RBD: K8s PVC와 Proxmox VM 디스크
- RGW: Harbor storage와 공연 자원 S3
- Harbor/ECR: 내부 pull과 AWS burst pull 분리
- Backup: 공연 이미지/영상 AWS S3 2차 백업
- Redis: 티켓팅 조회 부하, burst traffic, 예매 상태 기준점
- etcd: Ceph 제외, 로컬 디스크 유지
- HDD + 10G: 네트워크 이점과 쓰기 한계 분리
