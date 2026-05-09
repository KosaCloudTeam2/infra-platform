# 기술 질문 정리와 적용 판단

팀 회의에서 나온 기술 질문을 프로젝트 기준으로 정리한 문서임. 결론은 13일 구축 + 3일 발표 준비
범위에서 **MVP**, **선택 확장**, **향후 논의**, **제외**를 구분하는 데 사용함.

---

## 1. PXC나 Galera를 쓰면 무조건 active-active인가?

Percona XtraDB Cluster(PXC)는 Galera/wsrep 기반 동기식 복제 클러스터이므로 여러 노드가 쓰기 가능한
multi-primary 구조를 지원함. 하지만 지원한다고 해서 운영 정책이 반드시 active-active여야 하는 것은
아님.

현재 프로젝트 기준은 **PXC 3노드 + ProxySQL + Single Writer**임.

| 구분                   | 판단                                                           |
| :--------------------- | :------------------------------------------------------------- |
| 기술적으로 가능한 구조 | multi-primary 또는 active-active 쓰기 가능                     |
| MVP 운영 정책          | Single Writer 우선                                             |
| 이유                   | 쓰기 충돌, auto-increment 충돌, 장애 분석 복잡도를 줄이기 위함 |

정리:

> PXC는 Galera 기반이지만, MVP에서는 ProxySQL로 writer를 1대로 제한해 운영한다. Galera 기능은 복제와
> 고가용성 기반으로 사용하고, 앱이 여러 DB 노드에 동시에 쓰는 active-active 구조는 채택하지 않는다.

---

## 2. Ingress API의 단점과 현재 프로젝트 적용 여부

Kubernetes Ingress API는 HTTP/HTTPS 라우팅을 선언하는 표준 리소스임. 현재 온프레미스 Kubernetes 앱
노출에는 Ingress 또는 Service를 사용할 수 있음.

단점:

- 구현체가 필요함. 예: NGINX Ingress Controller, Traefik 등
- Controller별 annotation 차이가 있어 이식성이 떨어질 수 있음
- TCP/UDP, 고급 트래픽 정책, Gateway 수준 정책 표현에는 한계가 있음
- AWS ALB와 직접 연동하려면 AWS Load Balancer Controller(ALB Ingress Controller)가 필요하고, 이는
  IAM/OIDC/서브넷 태그/권한 설정이 추가됨

현재 프로젝트 적용 판단:

| 위치                  | 판단                                                        |
| :-------------------- | :---------------------------------------------------------- |
| 온프레미스 Kubernetes | Ingress 사용 가능                                           |
| AWS burst ASG/ALB     | Kubernetes Ingress가 아니라 Terraform ALB/Target Group 사용 |
| EKS 최소 PoC          | 기본 범위에서는 Ingress Controller까지 확장하지 않음        |

정리:

> 온프레미스 앱 진입점에는 Ingress를 사용할 수 있지만, EKS에서 AWS Load Balancer Controller까지
> 붙이는 것은 MVP 최소 PoC 범위를 넘는 확장 기능이다.

---

## 3. Cloudflare GSLB 개념

Global Server Load Balancing(GSLB)은 여러 지역 또는 여러 환경의 endpoint 중 어디로 트래픽을 보낼지
DNS/헬스체크/정책 기반으로 결정하는 방식임. Cloudflare Load Balancing은 Cloudflare 네트워크에서
origin pool의 상태를 확인하고, 가까운 위치 또는 정상 endpoint로 트래픽을 보내는 GSLB 역할을 할 수
있음.

이 프로젝트에서의 의미:

```text
사용자
→ Cloudflare Load Balancing 또는 DNS 정책
→ 온프레미스 Ingress 또는 AWS ALB
```

주의:

- Cloudflare가 Kubernetes 클러스터를 하나로 묶어주는 것은 아님
- 여러 클러스터/환경 앞에서 트래픽을 분산하거나 장애 시 우회하는 DNS/프록시 계층에 가까움
- MVP 필수는 아님. Route 53, 수동 전환, 단순 DNS로도 발표 가능함

적용 판단: **선택 확장**

---

## 4. 클라우드 인프라 프로젝트에서 AI가 들어갈 부분

AI는 MVP 핵심 인프라가 아니라 운영 보조 기능으로 넣는 것이 적합함.

적용 후보:

| 후보               | 설명                                                  | 적용 판단 |
| :----------------- | :---------------------------------------------------- | :-------- |
| 장애 로그 요약     | CloudWatch/Kubernetes/DB 로그를 요약해 원인 후보 제시 | 선택 확장 |
| 이상 탐지          | CPU, latency, 5xx, DB 상태 지표의 비정상 패턴 감지    | 선택 확장 |
| Runbook 추천       | 장애 유형별 복구 절차 추천                            | 선택 확장 |
| 비용 이상 탐지     | 예상보다 비용이 빠르게 증가하는 리소스 탐지           | 선택 확장 |
| AI agent 직접 운영 | 자동 조치까지 수행하는 agent                          | 향후 논의 |

Microsoft/Azure 쪽에는 학습 데이터를 직접 만들지 않아도 쓸 수 있는 이상 탐지/예측 계열 서비스가
있음. 예: Azure AI Anomaly Detector 계열, Azure Monitor의 동적 임계값(dynamic threshold), Azure
Machine Learning 기반 시계열 예측 등. 다만 이 프로젝트 MVP에 직접 붙이면 범위가 커짐.

정리:

> AI는 재해복구 자동화의 핵심 엔진으로 넣기보다, 장애 로그 요약·이상 탐지·Runbook 추천 같은 보조
> 기능으로 선택 확장에 두는 것이 적합하다.

---

## 5. GitHub 저장소를 gitops, apps, iac로 분리해야 하나?

현 단계에서는 **단일 저장소 유지**를 권장함.

분리 예시:

```text
apps repo   : 애플리케이션 코드
iac repo    : Terraform, Ansible
gitops repo : Kubernetes manifest, Argo CD Application
```

장점:

- 권한과 배포 책임 분리
- Argo CD가 GitOps repo만 추적하게 하기 쉬움
- 실제 운영 구조와 가까움

단점:

- 13일 프로젝트에서 관리할 repository, 권한, Secret, 문서 링크가 늘어남
- 팀원이 변경 흐름을 따라가기 어려울 수 있음
- 발표 캡처와 검증 포인트가 분산됨

현재 판단: **MVP는 단일 저장소 유지, 분리는 향후 확장**

---

## 6. garbd 적용 여지와 장단점

`garbd`는 Galera Arbitrator Daemon임. 데이터를 저장하지 않는 투표 전용 구성원으로, 보통 짝수 노드
또는 2노드 Galera/PXC 구성에서 quorum 판단을 보완하는 데 사용함.

현재 프로젝트는 PXC 3노드가 기준이므로 garbd 필요성이 낮음.

| 항목                    | 판단                                                                    |
| :---------------------- | :---------------------------------------------------------------------- |
| PXC 3노드               | garbd 불필요                                                            |
| PXC 2노드만 가능한 경우 | garbd 검토 가능                                                         |
| garbd 장점              | quorum 보완, split-brain 위험 완화                                      |
| garbd 단점              | 추가 운영 요소, 네트워크 장애 시 판단 복잡도 증가, 데이터 복제본은 아님 |

적용 판단: **MVP 제외, 2노드 제약 발생 시 향후 논의**

---

## 7. k6 부하 테스트와 p95 latency

k6는 JavaScript로 시나리오를 작성하는 부하 테스트 도구임. HTTP API, 웹 endpoint, threshold 기반 성능
검증에 적합함.

p95 latency는 전체 요청 중 95%가 이 시간 이하로 응답했다는 의미임.

예:

```text
p95 latency = 300ms
→ 전체 요청 100개 중 95개는 300ms 이하로 응답
```

현재 프로젝트 적용:

| 용도                          | 판단      |
| :---------------------------- | :-------- |
| AWS ASG scale-out 시연        | 유용      |
| ALB Target Response Time 확인 | 유용      |
| 발표용 성능 지표              | 유용      |
| 정교한 SLO/성능 튜닝          | 선택 확장 |

MVP에서는 k6 또는 JMeter 중 하나만 선택해 간단한 부하 테스트를 수행하면 충분함.

---

## 8. Argo Rollouts Blue/Green과 Canary 차이

Argo Rollouts는 Kubernetes 배포 전략을 고도화하는 도구임.

| 구분     | Blue/Green                                       | Canary                              |
| :------- | :----------------------------------------------- | :---------------------------------- |
| 방식     | 새 버전과 기존 버전을 동시에 준비 후 트래픽 전환 | 새 버전에 트래픽을 조금씩 증가      |
| 장점     | 전환/롤백이 명확함                               | 위험을 단계적으로 줄임              |
| 단점     | 리소스가 더 필요할 수 있음                       | 트래픽 분산/지표 분석 설정이 복잡함 |
| MVP 판단 | 선택 확장                                        | 선택 확장                           |

현재 프로젝트는 기본 Kubernetes rolling update와 Argo CD sync만으로 충분함. Argo Rollouts는 발표
완성도 향상용 선택 확장으로 둠.

---

## 9. KEDA와 RPS/p95 기반 autoscaling

Kubernetes Event-driven Autoscaling(KEDA)는 외부 이벤트나 지표를 기준으로 Kubernetes workload를
scale-out/scale-in 하는 도구임. Prometheus, Kafka, RabbitMQ, HTTP add-on 등 다양한 scaler를 사용할
수 있음.

RPS(Requests Per Second)나 p95 latency 기반 scale-out은 매력적이지만, 현재 프로젝트에서는 MVP 기본
경로가 아님.

이유:

- KEDA는 Kubernetes workload autoscaling에 적합함
- 현재 AWS burst는 Kubernetes가 아니라 EC2 ASG/ALB 기준임
- 온프레미스 지표를 기준으로 EKS/ASG까지 자동 확장하려면 모니터링, 권한, 트래픽 전환 설계가 추가됨

적용 판단: **선택 확장 또는 향후 논의**

---

## 10. Prometheus remote_write, Thanos Receiver, Loki, Ceph, Grafana 흐름 검토

질문에 적힌 흐름:

```text
cloud: prometheus remote_write
→ on-premise: thanos receiver → prometheus → local disk
cloud: Fluent Bit push → loki → ceph <- grafana
```

수정해서 이해하면 다음과 같음.

### 지표(metrics) 흐름

일반적으로 Prometheus는 local TSDB에 지표를 저장하고, `remote_write`로 외부 수신자에 지표를 복제할
수 있음. Thanos Receiver는 Prometheus remote_write를 받아 장기 저장소(object storage)에 업로드하고,
Thanos Query/Grafana가 이를 조회하게 할 수 있음.

권장 개념 흐름:

```text
Cloud Prometheus 또는 Agent
→ remote_write
→ Thanos Receiver
→ Object Storage(Ceph RGW 또는 S3)
→ Thanos Query
→ Grafana
```

주의:

- Thanos Receiver 뒤에 다시 Prometheus가 오는 구조는 일반적이지 않음
- Prometheus local disk는 각 Prometheus의 단기 저장소임
- 장기 보관은 Thanos + Object Storage가 담당하는 구조가 자연스러움

### 로그(logs) 흐름

Fluent Bit는 로그 수집/전송 에이전트이고, Loki는 로그 저장/조회 시스템임. Loki는 object storage
backend로 S3 호환 저장소를 사용할 수 있으므로 Ceph RGW를 backend로 둘 수 있음.

권장 개념 흐름:

```text
Cloud 또는 On-prem 앱 로그
→ Fluent Bit
→ Loki
→ Ceph RGW 또는 S3 object storage
→ Grafana에서 LogQL로 조회
```

현재 프로젝트 판단:

- MVP는 CloudWatch, Kubernetes logs, EC2 Docker logs로 충분함
- Prometheus/Thanos/Loki/Ceph RGW 통합은 선택 확장
- 발표에서는 흐름도를 개념 설명으로만 사용하고 실제 구축 범위로 과장하지 않음

---

## 11. Redis Sentinel 사용할 수 있나?

Redis Sentinel은 Redis primary/replica 상태를 감시하고 장애 시 primary 승격을 수행하는 고가용성
구성임.

현재 프로젝트에서 Redis는 필수 구성요소가 아님. 세션 저장소, 캐시, 큐가 필요한 앱이라면 선택할 수
있음.

적용 판단:

| 상황                        | 판단                                |
| :-------------------------- | :---------------------------------- |
| 현재 앱이 Redis를 쓰지 않음 | 도입 불필요                         |
| 세션 저장소가 필요함        | Redis 또는 DB/외부 세션 저장소 검토 |
| Redis HA까지 필요함         | Redis Sentinel 선택 확장            |

MVP에서는 Redis Sentinel을 넣지 않는 것을 권장함.

---

## 12. 로그 관리에 Sentry를 써야 하나?

Sentry는 애플리케이션 예외, stack trace, release별 오류 추적에 강한 도구임. 인프라 로그 전체를
수집하는 Loki/CloudWatch와는 목적이 다름.

| 도구            | 주 용도                                   |
| :-------------- | :---------------------------------------- |
| Sentry          | 앱 예외, stack trace, release별 오류 추적 |
| Loki            | Kubernetes/app 로그 수집과 검색           |
| CloudWatch Logs | AWS 리소스와 EC2 로그 수집                |

현재 프로젝트 판단:

- MVP 인프라 관측은 CloudWatch, Kubernetes logs, EC2 Docker logs로 충분
- Sentry는 실제 앱 코드 오류 추적이 중요할 때 선택 확장
- 인프라 프로젝트의 필수 관측성 도구로 넣을 필요는 낮음

---

## 13. JMeter와 iperf 활용 방법

### JMeter

JMeter는 HTTP/API 요청 부하를 만들어 애플리케이션 응답 시간, 오류율, 처리량을 확인하는 도구임.

적용 예:

- ALB endpoint에 HTTP 요청 부하 생성
- AWS ASG scale-out 전후 응답 시간 비교
- p95 latency와 5xx 비율 확인

### iperf

iperf는 네트워크 대역폭과 지연을 측정하는 도구임. 앱 HTTP 성능이 아니라 네트워크 경로 자체를 확인할
때 사용함.

적용 예:

- 온프레미스 노드 간 Ceph 스토리지망 대역폭 확인
- Proxmox 노드 간 jumbo frame 적용 후 throughput 확인
- VPN/WireGuard 연결 시 대역폭 확인

현재 프로젝트 적용 판단:

| 도구           | MVP 활용                                    |
| :------------- | :------------------------------------------ |
| JMeter 또는 k6 | AWS burst scale-out 시연용 HTTP 부하 테스트 |
| iperf          | 온프레미스 네트워크/Ceph망 검증 보조        |

둘 다 넣을 수 있지만 발표용 MVP에서는 k6 또는 JMeter 중 하나만 선택하고, iperf는 네트워크 검증
캡처용으로 제한하는 것이 좋음.

---

## 최종 적용 판단 요약

| 주제                     | 현재 프로젝트 판단                                              |
| :----------------------- | :-------------------------------------------------------------- |
| PXC/Galera active-active | PXC 사용, 운영은 Single Writer                                  |
| Ingress API              | 온프레미스 K8s에 사용 가능, AWS Load Balancer Controller는 확장 |
| Cloudflare/GSLB          | 선택 확장, 트래픽 분산/장애 우회 계층                           |
| AI/DR/agent              | 선택 확장, 로그 요약/이상 탐지/Runbook 추천 중심                |
| 저장소 분리              | MVP는 단일 저장소 유지, 분리는 향후 확장                        |
| garbd                    | PXC 3노드 기준 불필요, 2노드 제약 시 논의                       |
| k6/p95                   | 부하 테스트와 발표 지표로 유용                                  |
| Argo Rollouts            | Blue/Green/Canary는 선택 확장                                   |
| KEDA                     | Kubernetes autoscaling 고도화, 현재 MVP 기본 경로 아님          |
| Thanos/Loki/Ceph         | 선택 확장 관측성 구조                                           |
| Redis Sentinel           | Redis가 필요해질 때 선택 확장                                   |
| Sentry                   | 앱 예외 추적 선택 확장                                          |
| JMeter/iperf             | JMeter/k6는 앱 부하, iperf는 네트워크 검증                      |
