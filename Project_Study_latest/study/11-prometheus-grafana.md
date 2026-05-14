# 챕터 11: Prometheus + Grafana — 모니터링의 사실상 표준

> KOSA 인프라 프로젝트 학습 시리즈 / Day 5 / 등급 🟡🟡<br> 선수 챕터: 04(K8s 핵심), 07(Helm),
> 08(Ceph CSI)

---

## 학습 후 알 수 있는 것

- **Pull 기반 모니터링**과 Push 기반(SaaS Datadog 등)의 차이를 한 마디로 설명할 수 있어요.
- **Prometheus의 시계열 모델 + PromQL** 기초 문법으로 우리 클러스터에서 의미 있는 쿼리를 짤 수
  있어요.
- **Exporter 패턴**과 **ServiceMonitor CRD**가 어떻게 자동 디스커버리를 가능하게 하는지 이해해요.
- **Grafana**가 단순 시각화를 넘어 Prometheus + Loki + Tempo 까지 묶는 **observability 허브**인
  이유를 설명할 수 있어요.
- 우리 환경의 `kube-prometheus-stack` Helm 차트가 한 번 설치로 어떻게 **25개 이상 사전 대시보드 +
  Operator + 룰 + 알림**을 모두 띄우는지 따라가요.
- 발표 시 "부하 테스트 시 Pod 2→10 폭증" 같은 시연용 그래프를 어디서 보는지 짚을 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Prometheus**는 시계열(time-series) 메트릭을 pull 방식으로 수집/저장하고 PromQL로 쿼리하는 오픈소스
모니터링 시스템이고, **Grafana**는 그 메트릭을 비롯한 다양한 데이터 소스를 대시보드로 시각화하는
오픈소스 도구예요.

### 1.2 등장 배경

#### Prometheus의 등장

2012년 SoundCloud 엔지니어들이 만들었어요. 이전 모니터링(Nagios, Zabbix, Graphite, OpenTSDB)에 다음
불만이 있었어요.

- **고차원 라벨 부족**: Zabbix 같은 건 host 단위로 메트릭을 보는데, K8s 시대엔 Pod 단위, namespace
  단위, label 단위로 슬라이스해야 함.
- **Push 모델의 한계**: 서비스가 죽으면 Push도 안 옴 → 알람 자체가 안 옴.
- **시계열 DB 최적화 부족**: 디스크 효율, 쿼리 성능 모두 부족.

Prometheus가 이걸 다 해결: **고차원 라벨 + Pull + 자체 TSDB + PromQL**. 2016년 CNCF에 들어가서 K8s
다음으로 **두 번째 Graduated 프로젝트**가 됐어요.

#### Grafana의 등장

원래 Graphite/InfluxDB 시각화로 출발(2014). Prometheus가 떠오르면서 가장 인기 있는 시각화
클라이언트가 됐어요. 지금은 Loki(로그), Tempo(트레이스), Mimir(메트릭 장기보관) 같은 자기 생태계도
만들어서 **observability 풀스택**으로 성장.

### 1.3 핵심 개념 + 용어 풀이

| 용어                     | 설명                                                                    | 예시                                                    |
| ------------------------ | ----------------------------------------------------------------------- | ------------------------------------------------------- |
| **메트릭(metric)**       | 시계열로 수집되는 수치 데이터                                           | `node_cpu_seconds_total`                                |
| **라벨(label)**          | 메트릭에 붙은 key=value 태그 (고차원)                                   | `{instance="k8s-w1", mode="idle"}`                      |
| **시계열(time series)**  | 메트릭 이름 + 라벨 조합 1개                                             | `node_cpu_seconds_total{instance="k8s-w1",mode="idle"}` |
| **샘플(sample)**         | 특정 시점의 값                                                          | `(timestamp=1700000000, value=12345.67)`                |
| **PromQL**               | Prometheus 쿼리 언어                                                    | `rate(http_requests_total[5m])`                         |
| **scrape**               | Prometheus가 target에 HTTP GET해서 메트릭 가져옴                        | `/metrics` endpoint                                     |
| **Exporter**             | 기존 시스템이 노출하는 메트릭을 Prometheus 형식으로 변환해주는 사이드카 | node_exporter, mysql_exporter                           |
| **Service Discovery**    | 동적으로 scrape 대상 찾기                                               | K8s SD (자동)                                           |
| **ServiceMonitor**       | Prometheus Operator의 CRD, "어떤 서비스를 scrape할지" 선언              | 우리 PXC, Redis Exporter용                              |
| **PodMonitor**           | ServiceMonitor의 Pod 직접 버전                                          | Service 없는 Pod 모니터링                               |
| **Alertmanager**         | 알람 라우팅 + dedup + 발송                                              | Slack/Email/PagerDuty 등                                |
| **PromRule**             | 알람 룰 CRD                                                             | "CPU 80% 5분간 → 알람"                                  |
| **Recording Rule**       | 자주 쓰는 쿼리를 미리 계산                                              | `cluster:cpu:rate1m` 같은 합산                          |
| **DataSource (Grafana)** | 데이터 출처 (Prometheus, Loki, MySQL 등)                                | 우리는 Prometheus 1개                                   |
| **Dashboard**            | 그래프 모음 (JSON으로 저장)                                             | "Kubernetes / Compute Resources / Pod"                  |

### 1.4 동작 원리 (내부 메커니즘)

#### Pull 모델의 흐름

```
[Prometheus Server (in K8s)]
        │
        │ (every 30s) HTTP GET /metrics
        ▼
[Target Pod이 노출하는 :9100/metrics 등]
   ▶ "node_cpu_seconds_total{mode=idle} 1234"
   ▶ "node_memory_MemAvailable_bytes 8589934592"
   ▶ ...
        │
        ▼ 수신
[Prometheus]
        │
        ├── 메모리 + WAL (Write-Ahead Log)
        ├── 2시간마다 디스크 블록으로 압축
        └── PromQL 쿼리 시 디스크 + WAL 조합 응답
```

#### Service Discovery (K8s)

K8s에서 Pod이 자주 뜨고 죽으니 정적 target 리스트는 의미 없어요. Prometheus가 K8s API를 watch해서:

1. ServiceMonitor 또는 PodMonitor CRD를 봄
2. 매칭되는 Service/Pod의 endpoint 추출
3. 자동으로 scrape 대상에 추가
4. Pod 죽으면 자동 제거

#### Exporter 패턴

Prometheus가 직접 모든 시스템에 가서 메트릭을 만들 수는 없어요. 그래서:

- **node_exporter**: 호스트 메트릭 (CPU, memory, disk, network)
- **kube-state-metrics**: K8s 객체 상태 (Pod count, Deployment ready 등)
- **mysql_exporter**: MySQL 메트릭 (queries/sec, replication lag)
- **redis_exporter**: Redis 메트릭 (used_memory, ops_per_sec)
- **blackbox_exporter**: 외부 HTTP/TCP 헬스체크

각 exporter가 `/metrics` 엔드포인트를 노출 → Prometheus가 그걸 scrape.

#### Grafana의 동작

```
[브라우저] ─→ Grafana UI :3000
                  │
                  ▼ "이 대시보드 로드"
              Grafana 서버
                  │
                  ▼ "이 쿼리 결과 줘"
              PromQL via HTTP API
                  │
                  ▼
              Prometheus
                  │
                  ▼ JSON 응답
              Grafana가 SVG/Canvas로 렌더링
                  │
                  ▼
              사용자가 그래프 봄
```

대시보드 자체는 JSON으로 저장. Helm으로 사전 정의 대시보드를 ConfigMap에 박아서 자동 로드 가능.

### 1.5 주요 기능

#### Prometheus

- **시계열 저장**: 자체 TSDB, 압축율 높음
- **PromQL**: 강력한 쿼리 언어
- **자동 디스커버리**: K8s, EC2, Consul, file 등
- **Alerting**: PromRule + Alertmanager
- **Federation**: 다중 Prometheus 계층화
- **Remote write**: 외부 TSDB(Thanos, Mimir, Cortex)로 장기 보관

#### Grafana

- **다중 데이터소스**: Prometheus, Loki, Tempo, MySQL, Elasticsearch, ...
- **풍부한 패널 타입**: 그래프, 게이지, 테이블, heatmap, 통계
- **Dashboard 변수**: namespace, pod 같은 드롭다운 필터
- **Provisioning**: ConfigMap으로 대시보드/데이터소스 코드화
- **Alerting (Grafana 8+)**: Prometheus 알람 외 Grafana 자체 알람도 가능
- **공유 대시보드**: grafana.com 에서 ID로 import

### 1.6 다른 도구와 비교

| 항목      | **Prometheus (우리)** | Datadog                  | New Relic     | Zabbix         | InfluxDB + Telegraf     |
| --------- | --------------------- | ------------------------ | ------------- | -------------- | ----------------------- |
| 라이선스  | Apache 2.0 (OSS)      | SaaS 유료                | SaaS 유료     | GPL (OSS)      | MIT (OSS, Cloud는 유료) |
| 수집 모델 | Pull                  | Push (agent)             | Push (agent)  | Pull/Push 혼합 | Push                    |
| 쿼리 언어 | PromQL                | DDSQL                    | NRQL          | XPath-like     | InfluxQL/Flux           |
| K8s 통합  | 표준 (Operator)       | Datadog Agent            | New Relic K8s | 별도 templates | 별도 설정               |
| 비용      | 무료 (셀프 호스팅)    | $$$/노드                 | $$$/노드      | 무료           | 무료 (셀프 호스팅)      |
| 장기 보관 | Thanos/Mimir 별도     | 무제한 (요금에 포함)     | 무제한        | DB 직접 운영   | 자체 가능               |
| 적합 환경 | K8s + 자체 운영       | 멀티 클라우드 enterprise | APM 중심      | 전통 인프라    | 전통 인프라             |

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 필요한가

거의 모든 인프라에 필요해요. 안 쓸 수 없는 영역.

- **K8s 클러스터 운영**: 노드 자원, Pod 상태, 컨테이너 메트릭이 안 보이면 운영 불가.
- **DB 모니터링**: 쿼리 처리량, replication lag, slow query 발견.
- **앱 SLO 추적**: API 응답시간 p95, p99, error rate, throughput.
- **인프라 자원 capacity 예측**: 디스크/메모리 증가 추세로 언제 풀 차는지 예측.
- **장애 대응**: 알람 → 대시보드 → root cause 30분 내 파악.

### 2.2 업계 표준, 대표 사용 기업/사례

- **CNCF Graduated**: Kubernetes 다음으로 두 번째로 Graduated된 프로젝트가 Prometheus. CNCF의 핵심.
- **CNCF 2023 설문**: K8s 운영팀의 **86%가 Prometheus 사용**. 사실상 표준.
- **Google SRE 책**의 모니터링 4 Golden Signal(Latency, Traffic, Errors, Saturation)을 Prometheus가
  가장 잘 표현.
- **DigitalOcean, GitHub, Soundcloud, Uber, Shopify** 모두 사용 공개.
- **Red Hat OpenShift**, **Rancher**, **EKS** 등 매니지드 K8s가 기본 Prometheus 통합.
- **Grafana Labs**: 자체 SaaS도 운영하고 OSS도 메인테인. Grafana Cloud로 유료화 진행 중.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **자동 디스커버리**: K8s에서 Pod이 100개 → 1000개로 늘어도 설정 변경 0. ServiceMonitor 한 번
  박으면 자동 추적.
- **고차원 쿼리**: namespace × pod × container × status_code 같은 슬라이스가 한 줄로.
- **Operator 패턴의 성숙**: Prometheus Operator + kube-prometheus-stack 으로 설치 → 운영 →
  업그레이드 다 자동.
- **사전 대시보드 풍부**: kube-prometheus-stack가 25개+ Grafana 대시보드 기본 제공. 0부터 안
  만들어도 됨.
- **알람 통합**: PromRule → Alertmanager → Slack/PagerDuty 한 흐름.

### 2.4 시장 위치

- DB-Engines time-series ranking: **InfluxDB가 한때 1위였으나 Prometheus가 K8s 시대에 추월**.
- Grafana는 시각화 1위 (Kibana는 Elasticsearch 종속, Tableau는 BI 영역).
- 매니지드 클라우드: **AWS Managed Prometheus (AMP), GCP Cloud Operations, Azure Monitor for
  Containers** 모두 Prometheus 호환 API 제공. 즉 Prometheus가 표준 인터페이스.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 옵션                             | 장점                                            | 단점                                     | 우리 환경 적합도 |
| -------------------------------- | ----------------------------------------------- | ---------------------------------------- | ---------------- |
| **kube-prometheus-stack (선택)** | Operator + 25개 대시보드 + Alertmanager 한 번에 | 메모리 좀 먹음 (~2Gi)                    | ★★★★★            |
| Datadog                          | SaaS, 0운영                                     | 노드당 월 $15+ → 6노드 → 발표 비용 부담  | ★★               |
| InfluxDB + Telegraf              | OSS, 자체 운영                                  | K8s 통합 약함, Operator 없음             | ★★               |
| Cloud Native Loki Only           | 로그만 필요할 때                                | 메트릭 모니터링 부족                     | X                |
| Prometheus + Grafana 별도 설치   | 컴포넌트 따로 관리 가능                         | Operator 없어서 수동 ServiceMonitor 작성 | ★★               |

### 3.2 현업 표준과의 정합성

- **K8s 표준 = Prometheus**: CNCF Graduated, 매니지드 K8s 모두 통합. 우리 구성이 즉시 업계 표준.
- **Grafana 대시보드 공유 문화**: grafana.com에 수천 개 공개 대시보드. ID 입력으로 즉시 import.

### 3.3 선택 근거 (트레이드오프)

#### 왜 kube-prometheus-stack (단독 Prometheus 대신)?

이 차트는 단순한 Prometheus + Grafana가 아니에요. 다음을 한 번에 깔아줘요.

1. **Prometheus Operator** (CRD 관리)
2. **Prometheus 서버** (스토리지 PVC 포함)
3. **Alertmanager** (알람 라우팅)
4. **Grafana** (대시보드 + 데이터소스 자동 등록)
5. **node-exporter DaemonSet** (각 노드 메트릭)
6. **kube-state-metrics** (K8s 객체 상태 메트릭)
7. **사전 정의 ServiceMonitor 다수** (kubelet, api-server, etcd, scheduler...)
8. **사전 정의 PromRule 다수** (CPU/Memory/디스크 룰, K8s 컴포넌트 헬스)
9. **사전 정의 Grafana Dashboard 25개+** (compute resources, namespace, pod, node 등)

→ 이걸 따로 깔면 일주일. Helm으로 30분.

#### 왜 SaaS Datadog 안 씀?

- **비용**: 노드당 월 $15~$23 → 6노드면 월 $90~140 → 발표 데모용으로 부담.
- **온프레미스 데이터 외부 송출** 거부감.
- **학습 가치**: Prometheus를 직접 운영하는 게 더 많이 배움.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
Namespace: monitoring
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│ Deployment: prometheus-operator                              │
│   └─ Watch: ServiceMonitor, PodMonitor, PromRule CRDs        │
│                                                              │
│ StatefulSet: prometheus-kube-prom-prometheus                 │
│   ├─ Pod replica × 1 (학습용; 운영은 2+)                     │
│   ├─ PVC 50Gi (team2-rbd-block, 메트릭 영속화)              │
│   └─ scrape interval: 30s                                    │
│                                                              │
│ Deployment: kube-prom-grafana                                │
│   ├─ Service type: LoadBalancer → 172.16.23.102 (MetalLB)    │
│   ├─ Sidecar: 대시보드 ConfigMap 자동 로드                   │
│   └─ Datasource: Prometheus (자동 등록)                      │
│                                                              │
│ StatefulSet: alertmanager-kube-prom-alertmanager             │
│   └─ Receiver: 미구성 (학습용)                               │
│                                                              │
│ DaemonSet: kube-prom-prometheus-node-exporter (6 Pod)        │
│   └─ 각 노드의 /proc, /sys 메트릭 수집                       │
│                                                              │
│ Deployment: kube-state-metrics                               │
│   └─ K8s API watch → Pod/Deployment/PVC state 메트릭         │
└──────────────────────────────────────────────────────────────┘
                              │
                              │ scrape
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ 자동 디스커버리 대상 (ServiceMonitor 기반)                    │
│                                                              │
│ • kubelet (각 노드 :10250)                                    │
│ • kube-apiserver, kube-scheduler, controller-manager         │
│ • etcd                                                        │
│ • CoreDNS                                                     │
│ • node-exporter (자기 자신)                                   │
│ • kube-state-metrics                                          │
│ • (추가) PXC exporter, Redis exporter, ticket-app /metrics   │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 핵심 설정값과 근거

| 항목                 | 값                                           | 근거                               |
| -------------------- | -------------------------------------------- | ---------------------------------- |
| Helm chart           | `prometheus-community/kube-prometheus-stack` | CNCF 호환 풀스택                   |
| Namespace            | `monitoring`                                 | 격리 + RBAC 관리                   |
| Prometheus 디스크    | 50Gi (`team2-rbd-block`)                     | 메트릭 보존 약 2주 분량            |
| Prometheus retention | 14d (기본)                                   | 학습 환경엔 충분, 운영은 30d~90d   |
| scrape interval      | 30s (기본)                                   | 트래픽 vs 정밀도 균형              |
| Grafana service      | LoadBalancer → 172.16.23.102                 | MetalLB 풀 안에서 할당             |
| Grafana admin pw     | `kosa1004` (학습용)                          | 운영은 Sealed Secret               |
| Alertmanager         | 설치만, receiver 미구성                      | 학습 단계                          |
| 사전 대시보드        | 25개+ 자동 ConfigMap                         | grafana-dashboard-\* labelSelector |

### 4.3 다른 컴포넌트와의 연결

```
[K8s 노드 6대]        ──→ node-exporter DaemonSet → Prometheus
[K8s 컨트롤 플레인]    ──→ kubelet/apiserver/etcd metrics → Prometheus
[Pod 전체]            ──→ kube-state-metrics → Prometheus
[ceph-csi-rbd]        ──→ (선택) ceph-csi 자체 메트릭
[Percona PXC]         ──→ Percona PMM exporter (옵션)
[Redis]               ──→ redis-exporter 사이드카 (옵션)
[ticket-app]          ──→ FastAPI prometheus-fastapi-instrumentator → /metrics

                        ↓ scrape
                    Prometheus (TSDB)
                        ↓ query
                     Grafana
                        ↓ HTTP
                     [브라우저 / 172.16.23.102]
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 Helm values

**우리 파일 (예시):** `/Users/sangjjang/kosa_infra_project/manifests/monitoring/values.yaml`

```yaml
prometheus:
  prometheusSpec:
    retention: 14d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: team2-rbd-block
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 50Gi
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        memory: 2Gi
    # 모든 namespace의 ServiceMonitor를 자동 감지
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

grafana:
  enabled: true
  adminPassword: "kosa1004"
  service:
    type: LoadBalancer
    loadBalancerIP: 172.16.23.102 # MetalLB에 명시 요청
  persistence:
    enabled: true
    storageClassName: team2-rbd-block
    size: 5Gi
  # 사전 대시보드 25개+ 활성화
  defaultDashboardsEnabled: true
  defaultDashboardsTimezone: "Asia/Seoul"

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: team2-rbd-block
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 1Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

**왜 이 옵션? (라인별)**

- `retention: 14d` : Prometheus의 자체 TSDB 보존 기간. 14일이면 학습/시연 충분. 장기 보관(90d+)은
  Thanos/Mimir 별도 필요.
- `storageClassName: team2-rbd-block` : 챕터 08의 default SC. Prometheus 재시작해도 메트릭 유지.
- `serviceMonitorSelectorNilUsesHelmValues: false` : 이게 핵심 옵션. 기본값 true면 차트가 만든
  ServiceMonitor만 보고, 사용자가 다른 ns에 만든 ServiceMonitor는 무시. **우리가 PXC, Redis exporter
  ServiceMonitor를 추가하려면 false로 둬야 함**.
- `loadBalancerIP: 172.16.23.102` : MetalLB에 특정 IP를 요청. 풀(172.16.23.100-150) 안이어야 함.
  다른 컴포넌트(ArgoCD .101, ticket-app .103)와 충돌 회피.
- `defaultDashboardsEnabled: true` : 25개 사전 대시보드(Pod, Node, Namespace 등) ConfigMap으로 자동
  생성.

### 5.2 추가 ServiceMonitor (Redis exporter 예시)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-exporter
  namespace: kosa-app
  labels:
    release: kube-prom # ★ Helm release 이름과 매칭
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: redis-exporter
  endpoints:
    - port: metrics
      interval: 30s
```

**왜 `release: kube-prom` 라벨?**

kube-prometheus-stack의 Prometheus는 기본적으로 `release: <helm-release-name>` 라벨이 붙은
ServiceMonitor만 픽업해요. 우리 helm release를 `kube-prom`으로 깔았으니 그 라벨이 매칭 키.

### 5.3 PromRule 예시 (CPU 알람)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ticket-app-alerts
  namespace: kosa-tickets
  labels:
    release: kube-prom
spec:
  groups:
    - name: ticket-app
      rules:
        - alert: TicketAppHighCPU
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace="kosa-tickets"}[5m]))
              / sum(kube_pod_container_resource_limits{namespace="kosa-tickets",resource="cpu"})
            > 0.8
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "ticket-app CPU > 80% for 2min"
```

---

## 6. 실행 + 결과

### 6.1 Helm 설치

명령

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f /Users/sangjjang/kosa_infra_project/manifests/monitoring/values.yaml
```

기대 출력

```
NAME: kube-prom
LAST DEPLOYED: ...
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=kube-prom"
```

### 6.2 Pod 확인

명령

```bash
kubectl get pods -n monitoring
```

기대 출력 (10여 개 Pod)

```
NAME                                                     READY   STATUS    AGE
alertmanager-kube-prom-alertmanager-0                    2/2     Running   3m
kube-prom-grafana-7c9f4b8c7d-xyz12                       3/3     Running   3m
kube-prom-kube-prometheus-operator-79b6d4f8c-abc34       1/1     Running   3m
kube-prom-kube-state-metrics-5b6f8c9d-def56              1/1     Running   3m
kube-prom-prometheus-node-exporter-aaa11                 1/1     Running   3m
kube-prom-prometheus-node-exporter-bbb22                 1/1     Running   3m
kube-prom-prometheus-node-exporter-ccc33                 1/1     Running   3m
kube-prom-prometheus-node-exporter-ddd44                 1/1     Running   3m
kube-prom-prometheus-node-exporter-eee55                 1/1     Running   3m
kube-prom-prometheus-node-exporter-fff66                 1/1     Running   3m
prometheus-kube-prom-kube-prometheus-0                   2/2     Running   3m
```

해석:

- node-exporter 6개 = K8s 노드 6대에 DaemonSet
- Prometheus STS 1개 (학습용; 운영은 2+)
- Alertmanager STS 1개
- Operator 1개, Grafana 1개, kube-state-metrics 1개

### 6.3 Grafana 접속

명령

```bash
kubectl get svc -n monitoring kube-prom-grafana
```

기대 출력

```
NAME                TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
kube-prom-grafana   LoadBalancer   10.105.42.10    172.16.23.102    80:30000/TCP
```

브라우저에서 `http://172.16.23.102` → admin / kosa1004.

### 6.4 사전 대시보드 확인

Grafana 로그인 후 좌측 `Dashboards` → `Browse` → `General` 폴더.

기대: 25개+ 대시보드. 핵심 몇 개.

| 대시보드 이름                                         | 보는 것                                |
| ----------------------------------------------------- | -------------------------------------- |
| **Kubernetes / Compute Resources / Cluster**          | 클러스터 전체 CPU/메모리 사용량        |
| **Kubernetes / Compute Resources / Namespace (Pods)** | namespace 별 Pod 자원                  |
| **Kubernetes / Compute Resources / Pod**              | 특정 Pod의 컨테이너 자원               |
| **Kubernetes / Compute Resources / Node (Pods)**      | 노드별 Pod 자원                        |
| **Node Exporter / Nodes**                             | 노드의 OS 레벨 (CPU/메모리/디스크)     |
| **Kubernetes / API server**                           | API 서버 메트릭 (latency, error)       |
| **Kubernetes / Kubelet**                              | kubelet 메트릭 (Pod 시작/정리 latency) |
| **Kubernetes / Persistent Volumes**                   | PVC 상태, 디스크 사용량                |
| **Kubernetes / Networking / Cluster**                 | 클러스터 전체 네트워크 (Bytes/sec)     |

### 6.5 Prometheus UI에서 직접 쿼리

명령

```bash
kubectl port-forward -n monitoring svc/kube-prom-kube-prometheus 9090:9090
```

브라우저 `http://localhost:9090` → 쿼리 입력란.

PromQL 예시:

```promql
# 1) ticket-app Pod의 CPU 사용률 (millicore)
sum by (pod) (
  rate(container_cpu_usage_seconds_total{namespace="kosa-tickets",container!="POD"}[5m])
) * 1000

# 2) Pod 수 변화 (HPA 모니터링용)
count(kube_pod_status_phase{namespace="kosa-tickets",phase="Running"})

# 3) PVC 사용량 (Ceph RBD)
sum by (persistentvolumeclaim) (
  kubelet_volume_stats_used_bytes{namespace=~"pii-protected|kosa-app"}
)

# 4) Node 메모리 사용률
1 - (
  node_memory_MemAvailable_bytes
  / node_memory_MemTotal_bytes
)
```

### 6.6 시연 시나리오 — 부하 테스트 그래프

k6 부하 테스트 시 보는 그래프:

1. `Kubernetes / Compute Resources / Namespace (Pods)` 진입
2. namespace 필터 = `kosa-tickets`
3. 시간 범위 = `Last 30 minutes`
4. 패널 4개를 한 번에 봄:
   - `CPU Usage` — 부하 시 2 → 10 코어로 폭증
   - `Memory Usage` — 점진 증가
   - `Pod Count` — HPA 동작 (2 → 10)
   - `Network I/O` — 트래픽 증가

`watch -n 2 'kubectl get pods,hpa -n kosa-tickets'` 와 Grafana를 화면 분할로 보여주면 발표 효과
만점.

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 함정 1. ServiceMonitor가 다른 ns에 있으면 Prometheus가 못 봄

#### 증상

PXC namespace(`pii-protected`)에 PMM exporter ServiceMonitor 만들었는데, Prometheus UI의 Targets에
안 보임.

#### 원인

기본 Helm 차트는 `serviceMonitorSelectorNilUsesHelmValues: true` 인데, 이 경우 Prometheus가 **자기와
같은 release 라벨**의 ServiceMonitor만 봄.

```yaml
# 기본 Prometheus 매니페스트
spec:
  serviceMonitorSelector:
    matchLabels:
      release: kube-prom
```

다른 ns의 ServiceMonitor에 이 라벨 안 붙어 있으면 무시.

#### 해결

두 가지 방법:

**(A) ServiceMonitor 라벨 추가**

```yaml
metadata:
  labels:
    release: kube-prom
```

**(B) values.yaml 변경 — 모든 ServiceMonitor 감지**

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {} # 모든 ns
    serviceMonitorSelector: {} # 모든 라벨
```

운영에선 라벨 명시(A)가 깔끔. 학습에선 (B)로 자유롭게.

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Prometheus Operator는 **`Prometheus` CRD**를 만들고, 그 안에 `serviceMonitorSelector`로 어떤
ServiceMonitor를 watch할지 명시해요. 이건 멀티 테넌트 환경에서 **"내 ServiceMonitor만 이
Prometheus가 보게"** 격리하려는 의도예요.

예를 들어 한 클러스터에 팀 A와 팀 B가 각자 Prometheus를 운영한다면, 각자의 ServiceMonitor만 보게
selector로 격리 가능.

우리는 단일 팀이라 다 보는 게 편하지만, 기본값이 격리 지향이라 명시적으로 풀어줘야 해요.

---

### 함정 2. Prometheus 디스크 풀

#### 증상

Prometheus Pod이 OOM 또는 디스크 풀로 죽음. PVC 50Gi인데 어느 순간 가득 참.

#### 원인 (두 가지)

1. **Retention 잘못 설정**: `retention: 30d`로 늘려놓고 디스크는 50Gi 그대로. 메트릭 양 대비 부족.
2. **Cardinality 폭발**: 라벨이 너무 다양해서 시계열 수 폭증. 예: `user_id` 같은 high-cardinality
   라벨을 metric에 넣으면 사용자 1000명 → 시계열 1000개씩 늘어남.

#### 해결

```bash
# 1) 디스크 사용량 확인
kubectl exec -n monitoring prometheus-kube-prom-kube-prometheus-0 -c prometheus -- \
  du -sh /prometheus

# 2) 시계열 수 확인
# Prometheus UI에서 `prometheus_tsdb_head_series` 쿼리

# 3) 카디널리티 큰 메트릭 찾기
# PromQL: topk(10, count by (__name__)({__name__=~".+"}))
```

해결책:

- Retention 줄이기 또는 PVC 확장
- 문제 메트릭의 라벨 제거 (앱 코드 수정)
- 장기 보관은 Thanos/Mimir로 외부화

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Prometheus의 시계열 저장 단위는 **메트릭 이름 + 라벨 조합 1개**예요. 라벨 값 종류가 늘어나면 시계열
수가 곱셈으로 폭발해요.

예시:

- `http_requests_total{method, status}` → method 5개 × status 5개 = 25개 시계열
- `http_requests_total{method, status, user_id}` → 5 × 5 × 1000 = **25000개**

각 시계열이 메모리 + 디스크를 먹으니 디자인 단계에서 라벨 신중해야 해요.

---

### 함정 3. Grafana 대시보드가 안 뜸

#### 증상

Helm 설치 직후 Grafana 진입했는데 대시보드 폴더가 비어 있음.

#### 원인

`defaultDashboardsEnabled: true` 옵션은 ConfigMap을 만들어주는데, Grafana sidecar가 ConfigMap을
watch해서 자동 import 하기까지 1~2분 걸려요. 그동안은 빈 상태.

#### 해결

1~2분 기다리거나 Grafana Pod 재시작.

```bash
kubectl rollout restart deployment -n monitoring kube-prom-grafana
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

kube-prometheus-stack의 사전 대시보드는 **ConfigMap**으로 저장돼요. ConfigMap 이름에
`grafana_dashboard=1` 라벨이 붙어 있고, Grafana Pod의 sidecar 컨테이너(`kiwigrid/k8s-sidecar`)가 그
라벨의 ConfigMap을 watch.

신규 ConfigMap 감지 → Grafana provisioning 디렉토리로 복사 → Grafana가 reload.

이 과정이 비동기라 즉시 안 뜨는 거예요. 다음 sync까진 보통 30초~2분.

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- [Prometheus Docs](https://prometheus.io/docs/) — 본가
- [Grafana Docs](https://grafana.com/docs/grafana/latest/) — 본가
- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  — 우리가 쓴 차트
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) — Operator 자체

### Blog / Book / Talk

- [Prometheus Up & Running (O'Reilly)](https://www.oreilly.com/library/view/prometheus-up/9781492034131/)
  — 사실상 교과서
- [Google SRE Book — Chapter 6 Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)
  — 4 Golden Signals 원전
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/) — 쿼리 패턴 모음
- [Grafana Dashboards 공유소](https://grafana.com/grafana/dashboards/) — ID로 import할 수 있는 수천
  개

### 우리 프로젝트 내 관련 문서

- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 6.5 — 설치 절차
- `/Users/sangjjang/kosa_infra_project/inventory.md` — Grafana 접속 정보 (172.16.23.102)
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md` — Pod count 시연 시나리오

### 한 단계 더

- **Loki**: Grafana 표준 로그 수집. Prometheus의 로그 버전. 우리 인프라에 추가하면 풀스택
  observability.
- **Tempo**: 분산 트레이싱(Jaeger 호환). 마이크로서비스 latency 추적.
- **Thanos / Mimir**: Prometheus 장기 보관 + HA + federation. 90일+ 메트릭 필요해지면.
- **OpenTelemetry**: 메트릭/로그/트레이스 통합 수집 표준. 미래 방향.
- **Alertmanager 통합**: Slack/Discord/Email 받기. 학습용으로 간단한 Slack webhook 추가 좋음.

---

## 다음 챕터 미리보기

다음 챕터들에서는 지금까지 만든 인프라를 **GitOps로 자동 배포**하는 ArgoCD, AWS 하이브리드 burst를
위한 **Terraform on AWS + EKS + Karpenter**, 그리고 발표용 시연 자료들(좌석 예매 시나리오, 부하
테스트, VM HA 데모)을 다룰 예정이에요. 이번 챕터의 Grafana 대시보드가 **모든 시연의 시각적 증거**가
되니, 발표 전에 한 번씩 미리 들어가서 익숙해지면 좋아요.

KOSA 인프라 학습 시리즈의 핵심 6개 챕터(06~11)를 한 챕터로 묶어 보면:

- 06 K8s 핵심 — 컨테이너 오케스트레이션의 기본
- 07 Helm — 인프라 패키지 매니저
- **08 Ceph CSI — 영구 스토리지 백엔드**
- **09 Percona PXC — 동기 복제 RDBMS**
- **10 Redis Sentinel — HA 캐시**
- **11 Prometheus + Grafana — observability**

이 6개가 **온프레미스 K8s 운영의 최소 셋**이에요. 어디 가서 K8s 인프라 짭니다고 하면 이 조합은 거의
무조건 등장한다는 점, 기억하세요.
