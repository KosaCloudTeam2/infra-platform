# 10. 모니터링 — Prometheus, Grafana, JMeter

> Layer 5 / 학습 1일

---

## 1) 왜 모니터링이 필요한가

- "서비스가 느려요" — 어디가 느린지?
- "Pod이 죽었어요" — 왜?
- "DB가 부하 받아요" — 얼마나?
- "burst 시 자원 부족" — 어느 자원이?

**메트릭 + 대시보드 + 알람** 세트로 운영 시야 확보.

---

## 2) Prometheus

### 정체

오픈소스 메트릭 수집 + 시계열 DB + 알람 시스템.

```
[Target (앱, 노드, kube-state-metrics)]
       ↓ /metrics 엔드포인트 노출
[Prometheus] ← pull 방식 (15초 간격)
       ↓
[TSDB (시계열 DB)]
       ↓
[Grafana 쿼리] / [Alertmanager 알람]
```

### Pull vs Push

| | **Prometheus (Pull)** | StatsD / InfluxDB (Push) |
|---|---|---|
| 방식 | Prometheus가 주기적으로 가져옴 | 앱이 메트릭 전송 |
| 발견 | Service Discovery (K8s 자동) | 수동 등록 |
| 우리 사용 | ✅ K8s native | - |

### kube-prometheus-stack

Helm chart 하나로 묶음:
- Prometheus
- Grafana
- Alertmanager
- node-exporter (DaemonSet, 노드별 메트릭)
- kube-state-metrics (K8s 리소스 메트릭)
- prometheus-operator (CR 관리)

설치:
```bash
helm install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=ceph-rbd \
  --set grafana.service.type=LoadBalancer
```

---

## 3) PromQL 기본

```promql
# Pod CPU 사용률 (전체)
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# 최근 1분간 5xx 에러 율
sum(rate(http_requests_total{status=~"5.."}[1m]))
  / sum(rate(http_requests_total[1m])) * 100

# Pod 메모리 사용량 상위 10개
topk(10, container_memory_working_set_bytes)
```

---

## 4) Grafana

### 정체

대시보드 + 시각화 도구. Prometheus 외에도 CloudWatch, Loki 등 다양한 데이터소스.

### 우리 대시보드

| 대시보드 | 핵심 패널 |
|---|---|
| **Cluster Overview** | 노드 6대 CPU/Mem, Pod 수, etcd 상태 |
| **kosa-tickets App** | RPS, p99 latency, 5xx 에러율, JVM/Python 메모리 |
| **PXC** | 노드 상태, replication lag, query QPS |
| **Burst (AWS)** | NLB request, EKS 노드 수, Spot 가격 |

### 발표용 시연 대시보드

대시보드 1개에 모든 핵심 지표 모아두기:
- 좌상단: 노드 상태 (6/6 Ready)
- 우상단: RPS 그래프 (burst 시 spike 보임)
- 좌하단: Pod 수 (HPA 동작 시 증가)
- 우하단: 비용 ($X / hour)

---

## 5) JMeter — 부하 테스트

### 정체

오픈소스 부하 테스트 도구. GUI + CLI.

### 우리 시나리오

#### `ticket-burst.jmx`
```
Thread Group:
  Threads: 1000
  Ramp-up: 1초
  Duration: 60초

HTTP Request:
  Method: POST
  URL: https://api.kosa-tickets.com/v1/reservations
  Body: { "event_id": 123, "seat": "${__Random(1,1000)}" }

Headers:
  Authorization: Bearer ${jwt}
```

실행:
```bash
jmeter -n -t ticket-burst.jmx \
  -l results.jtl \
  -e -o report/
```

리포트 자동 생성 (HTML).

### JMeter vs 대안

| | **JMeter** | Locust | k6 | Gatling |
|---|---|---|---|---|
| 언어 | Java GUI | Python | JavaScript | Scala |
| 학습 곡선 | 중 | 낮음 | 중 | 높음 |
| 시각화 | 풍부 | 보통 | CLI/Cloud | 풍부 |
| **선택 이유** | 기술스택 명시 + KOSA 자료 | - | - | - |

---

## 6) iperf — 네트워크 대역폭 측정

```bash
# 서버 (kosa1)
iperf3 -s

# 클라이언트 (kosa2)
iperf3 -c kosa1
# → 10GbE Spine-Leaf 패브릭 실측
```

기대: ~9.4 Gbps (10G의 94%).

---

## 7) SLI / SLO / SLA

| 용어 | 정의 | 예시 |
|---|---|---|
| **SLI** | 지표 (Service Level Indicator) | p99 latency = 500ms |
| **SLO** | 목표 (Objective) | p99 < 200ms 99% 시간 |
| **SLA** | 약속 (Agreement) | 가용성 99.9% — 안 지키면 보상 |

우리 SLO:
- 평시 p99 < 200ms
- Burst p99 < 1s
- 가용성 99.9% (월 43분 다운타임 허용)

---

## 8) 발표 어필

> *"Prometheus + Grafana로 노드/Pod/앱 메트릭을 실시간 시각화하며, 발표용 통합 대시보드에 RPS, latency, Pod 수, AWS 비용을 한 화면에 모았습니다. JMeter로 10K RPS 부하 시나리오를 자동화했으며, iperf로 10GbE Spine-Leaf 패브릭의 9.4Gbps 실측을 검증했습니다."*

---

## 다음 단원

[`11_보안_NetworkPolicy_WAF.md`](11_보안_NetworkPolicy_WAF.md)
