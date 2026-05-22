---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: "Noto Sans KR", "Malgun Gothic", Arial, sans-serif;
    color: #172033;
    padding: 54px 64px;
  }
  h1 {
    font-size: 48px;
    letter-spacing: 0;
    color: #111827;
    margin-bottom: 18px;
  }
  h2 {
    font-size: 32px;
    letter-spacing: 0;
    color: #1f2937;
    margin-top: 0;
  }
  h3 {
    font-size: 24px;
    letter-spacing: 0;
    color: #334155;
    margin-bottom: 10px;
  }
  p, li {
    font-size: 25px;
    line-height: 1.45;
  }
  ul {
    margin-top: 18px;
  }
  table {
    font-size: 19px;
  }
  .lead {
    font-size: 34px;
    line-height: 1.36;
    color: #243447;
    max-width: 980px;
  }
  .sub {
    font-size: 22px;
    color: #64748b;
    margin-top: 20px;
  }
  .grid2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 28px;
    align-items: stretch;
  }
  .grid3 {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 20px;
    align-items: stretch;
  }
  .panel {
    border: 1px solid #d4dbe7;
    border-radius: 8px;
    padding: 20px 22px;
    background: #f8fafc;
  }
  .panel p, .panel li {
    font-size: 21px;
  }
  .metric {
    font-size: 38px;
    font-weight: 700;
    color: #0f3a5f;
  }
  .flow {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    margin: 26px 0;
  }
  .box {
    min-width: 126px;
    padding: 16px 18px;
    border: 1px solid #94a3b8;
    border-radius: 8px;
    background: #f8fafc;
    text-align: center;
    font-size: 20px;
  }
  .arrow {
    font-size: 28px;
    color: #64748b;
    font-weight: 700;
  }
  .small-placeholder {
    height: 185px;
    border: 3px dashed #9aa8ba;
    border-radius: 8px;
    background: #f8fafc;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #64748b;
    font-size: 20px;
    text-align: center;
  }
  .foot {
    position: absolute;
    left: 64px;
    bottom: 28px;
    color: #94a3b8;
    font-size: 15px;
  }
---

# 티켓팅 피크 트래픽을 받치는 저장소 플랫폼

<div class="lead">
공연 이미지·영상 자원, 컨테이너 이미지, 예매 상태를<br>
온프레미스와 AWS burst 환경에서 일관되게 처리하는 구조
</div>

<div class="sub">Ceph RBD · Ceph RGW · Harbor/ECR · Redis · AWS S3 Backup</div>

---

# 시나리오

<div class="grid2">
<div class="panel">
<h2>서비스 특성</h2>
<ul>
  <li>공연 예매 오픈 시점 트래픽 집중</li>
  <li>공연 포스터, 좌석도, 영상 자료 다량 보유</li>
  <li>평상시 온프레미스 운영</li>
  <li>피크 시간 AWS cloud bursting</li>
</ul>
</div>
<div class="panel">
<h2>인프라 요구</h2>
<ul>
  <li>정적 자원 저장과 백업</li>
  <li>양쪽 환경의 빠른 image pull</li>
  <li>예매 상태 일관성</li>
  <li>쓰기 성능 검증 가능한 저장소 설계</li>
</ul>
</div>
</div>

---

# 설계 원칙

<div class="grid3">
<div class="panel">
<div class="metric">1</div>
<h2>역할 분리</h2>
<p>Block, Object, Registry, Cache, Backup 경로 분리</p>
</div>
<div class="panel">
<div class="metric">2</div>
<h2>피크 대응</h2>
<p>AWS burst 시 이미지 pull과 예매 상태 조회 지연 최소화</p>
</div>
<div class="panel">
<div class="metric">3</div>
<h2>한계 명시</h2>
<p>10G 네트워크와 HDD 쓰기 성능을 분리 검증</p>
</div>
</div>

---

# 전체 아키텍처

<div class="flow">
  <div class="box">User</div>
  <div class="arrow">→</div>
  <div class="box">On-prem App</div>
  <div class="arrow">↔</div>
  <div class="box">Redis</div>
  <div class="arrow">↔</div>
  <div class="box">AWS Burst App</div>
</div>

<div class="flow">
  <div class="box">K8s PVC</div>
  <div class="arrow">→</div>
  <div class="box">Ceph RBD</div>
  <div class="box">Proxmox VM</div>
</div>

<div class="flow">
  <div class="box">Harbor</div>
  <div class="arrow">→</div>
  <div class="box">Ceph RGW</div>
  <div class="arrow">→</div>
  <div class="box">ECR / S3</div>
</div>

<div class="foot">etcd는 Ceph가 아닌 control-plane local disk 유지</div>

---

# Ceph: 하나의 저장소, 두 가지 역할

<div class="grid2">
<div class="panel">
<h2>Ceph RBD</h2>
<ul>
  <li>Kubernetes PVC</li>
  <li>Proxmox VM 디스크</li>
  <li>Block volume 통합</li>
  <li>Pod/VM 이동성과 장애 대응</li>
</ul>
</div>
<div class="panel">
<h2>Ceph RGW</h2>
<ul>
  <li>Harbor image blob 저장</li>
  <li>앱 Object 저장</li>
  <li>S3 API 호환</li>
  <li>공연 이미지·영상 자원 관리</li>
</ul>
</div>
</div>

---

# Ceph를 선택한 이유

<div class="lead">
공연 서비스는 DB보다 Object Storage에 가까운 데이터가 많음
</div>

<div class="grid3">
<div class="panel">
<h2>이미지·영상</h2>
<p>포스터, 좌석도, 홍보 영상, 썸네일 저장</p>
</div>
<div class="panel">
<h2>S3 API</h2>
<p>앱은 object key만 관리, 저장소 교체와 백업 단순화</p>
</div>
<div class="panel">
<h2>온프레 통제</h2>
<p>평상시 내부 저장소 사용, AWS는 burst와 백업에 집중</p>
</div>
</div>

---

# 현재 Ceph 구성의 성능 해석

<div class="grid2">
<div class="panel">
<h2>확보한 것</h2>
<ul>
  <li>노드 간 10G 전송 경로</li>
  <li>OSD replication traffic 여유</li>
  <li>Harbor/Object read 경로 개선</li>
</ul>
</div>
<div class="panel">
<h2>검증할 것</h2>
<ul>
  <li>HDD random write IOPS</li>
  <li>RBD write latency</li>
  <li>RGW upload throughput</li>
</ul>
</div>
</div>

<div class="sub">네트워크가 빠른 것과 디스크 쓰기 성능이 충분한 것은 별도 문제</div>

---

# Harbor / ECR: 실행 위치별 image pull 최적화

<div class="flow">
  <div class="box">CI Build</div>
  <div class="arrow">→</div>
  <div class="box">Harbor</div>
  <div class="arrow">→</div>
  <div class="box">ECR Mirror</div>
  <div class="arrow">→</div>
  <div class="box">AWS Burst</div>
</div>

<div class="grid2">
<div class="panel">
<h2>온프레</h2>
<p>Harbor에서 내부망 pull, 외부 registry 의존도 감소</p>
</div>
<div class="panel">
<h2>AWS</h2>
<p>ECR에서 리전 내부 pull, burst scale-out 지연 감소</p>
</div>
</div>

---

# Backup: 복제와 백업을 분리

<div class="lead">
Ceph replica는 디스크 장애 대응<br>
AWS S3 backup은 삭제·오염·운영 실수 복구
</div>

<div class="flow">
  <div class="box">Ceph RGW</div>
  <div class="arrow">→</div>
  <div class="box">copy-only</div>
  <div class="arrow">→</div>
  <div class="box">AWS S3</div>
  <div class="arrow">→</div>
  <div class="box">Lifecycle</div>
</div>

<div class="sub">초기 정책: 원본 삭제 금지, object key 동일 유지, restore-test 우선</div>

---

# Redis: 캐시를 넘어 예매 상태 기준점

<div class="lead">
AWS와 온프레미스가 서로 다른 DB replica를 보면<br>
예매 상태가 몇 초 차이로 어긋날 수 있음
</div>

<div class="flow">
  <div class="box">On-prem App</div>
  <div class="arrow">→</div>
  <div class="box">Redis</div>
  <div class="arrow">←</div>
  <div class="box">AWS Burst App</div>
</div>

<div class="sub">좌석 hold · 예매 진행 상태 · 대기열 token</div>

---

# Redis 일관성 모델

<div class="grid2">
<div class="panel">
<h2>Redis 기준</h2>
<ul>
  <li>실시간 예매 상태 판단</li>
  <li>좌석 hold TTL</li>
  <li>대기열 token</li>
  <li>중복 요청 방지 key</li>
</ul>
</div>
<div class="panel">
<h2>DB 기준</h2>
<ul>
  <li>최종 예매 확정</li>
  <li>정산과 이력</li>
  <li>장기 보관</li>
  <li>복구 기준 데이터</li>
</ul>
</div>
</div>

<div class="sub">Redis가 DB를 대체하지 않음. 실시간 판단 경로와 최종 저장 경로를 분리함.</div>

---

# etcd는 Ceph에 두지 않음

<div class="lead">
제어 평면과 스토리지 장애를 결합하지 않기 위한 선택
</div>

<div class="grid2">
<div class="panel">
<h2>Ceph에 두면</h2>
<ul>
  <li>Ceph 장애가 API Server 영향으로 확대</li>
  <li>복구 순서 복잡도 증가</li>
  <li>순환 의존 가능성</li>
</ul>
</div>
<div class="panel">
<h2>로컬 디스크 유지</h2>
<ul>
  <li>control-plane 독립성 유지</li>
  <li>장애 범위 축소</li>
  <li>복구 판단 단순화</li>
</ul>
</div>
</div>

---

# 검증 증거

<div class="grid3">
  <div class="small-placeholder">Ceph 상태<br>OSD / pool / RBD</div>
  <div class="small-placeholder">10G + HDD<br>iperf / fio / rados bench</div>
  <div class="small-placeholder">Harbor / ECR<br>replication execution</div>
</div>

<br>

<div class="grid3">
  <div class="small-placeholder">AWS S3 backup<br>object count / lifecycle</div>
  <div class="small-placeholder">Redis<br>key / TTL / hit ratio</div>
  <div class="small-placeholder">etcd local<br>findmnt / manifest</div>
</div>

---

# 운영상 남는 리스크

<div class="grid2">
<div class="panel">
<h2>기술 리스크</h2>
<ul>
  <li>HDD 기반 Ceph write IOPS</li>
  <li>Redis 단일 장애점</li>
  <li>Harbor metadata 별도 백업</li>
</ul>
</div>
<div class="panel">
<h2>대응 방향</h2>
<ul>
  <li>fio/rados bench 기준 수치화</li>
  <li>Redis Sentinel/Replica 검토</li>
  <li>Harbor DB/config backup 분리</li>
</ul>
</div>
</div>

---

# 결론

<div class="lead">
이 구조의 목표는 단순한 기술 도입이 아니라<br>
티켓팅 피크 시간의 저장소·이미지·예매 상태 병목을 분리하는 것
</div>

<ul>
  <li>Ceph RBD: K8s/VM block volume 통합</li>
  <li>Ceph RGW: Harbor image blob과 앱 Object 저장</li>
  <li>Harbor/ECR: 실행 위치별 image pull 최적화</li>
  <li>Redis: DB 부하 감소와 예매 상태 단일 기준점</li>
  <li>AWS S3: 정적 자원 2차 백업과 장기 보관</li>
</ul>
