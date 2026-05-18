# 11. 관측성 (Prometheus / Grafana / Alertmanager)

> **이 챕터에서 다루는 것**<br> 메트릭/로그/트레이스의 차이, Prometheus의 pull 모델,
> kube-prometheus-stack이 한 번에 설치해주는 것, kubeadm 기본값이 메트릭 포트를 127.0.0.1에만
> binding하는 함정, 추천 대시보드와 알림 룰.

## 목차

1. [이론: 관측 3축](#1-이론-관측-3축)
2. [Prometheus: pull 기반 메트릭](#2-prometheus-pull-기반-메트릭)
3. [kube-prometheus-stack](#3-kube-prometheus-stack)
4. [kubeadm 메트릭 포트 함정](#4-kubeadm-메트릭-포트-함정)
5. [Grafana 대시보드](#5-grafana-대시보드)
6. [Alertmanager 알림](#6-alertmanager-알림)
7. [구축 절차](#7-구축-절차)
8. [운영 치트시트 (PromQL)](#8-운영-치트시트-promql)
9. [트러블슈팅](#9-트러블슈팅)
10. [다음 챕터](#10-다음-챕터)

---

## 1. 이론: 관측 3축

| 축          | 무엇                               | 도구 예               |
| ----------- | ---------------------------------- | --------------------- |
| **Metrics** | 시계열 숫자 (CPU%, 요청 수)        | Prometheus, Datadog   |
| **Logs**    | 시각 순 텍스트 (어플리케이션 로그) | Loki, ELK, Splunk     |
| **Traces**  | 분산 호출 흐름 (A → B → C)         | Jaeger, Tempo, Zipkin |

우리는 **메트릭** 중심. 로그는 `kubectl logs`/journalctl로 수동, traces는 미사용.

### 1.1 왜 메트릭 우선?

- 가장 가성비. 수치 한 줄로 시스템 건강도 표현
- 시계열 DB가 효율적 (수 PB 처리 가능)
- 알림 룰 작성 직관적
- Grafana 대시보드 풍부

향후 로그/트레이스 추가 가능 (Loki/Tempo는 Prometheus 같은 회사 Grafana Labs).

---

## 2. Prometheus: pull 기반 메트릭

### 2.1 push vs pull

```
[Push 모델] (StatsD, Datadog agent 등)
  App → metric 전송 → 수집 서버

  단점: App이 수집 서버 주소 알아야, App 수만큼 트래픽 ↑

[Pull 모델] (Prometheus)
  수집 서버 → App의 /metrics 엔드포인트 GET

  장점: App은 /metrics만 노출, 수집 서버가 누구를 scrape할지 결정
```

### 2.2 Prometheus 구조

```
[Prometheus Server]
  ├── Scraper (15초마다 target /metrics GET)
  ├── TSDB (시계열 DB, 로컬 디스크)
  └── HTTP API (PromQL 쿼리)
       │
       ▼ Grafana가 query
```

### 2.3 Exporter

App이 /metrics를 직접 노출 못 하는 경우 (예: MySQL, Linux 노드) → exporter 사용.

| Exporter                 | 무엇을 노출                            |
| ------------------------ | -------------------------------------- |
| **node-exporter**        | OS 메트릭 (CPU, memory, disk, network) |
| **kube-state-metrics**   | K8s 객체 상태 (Deployment, Pod, ...)   |
| **mysql-exporter**       | MySQL 쿼리/연결 통계                   |
| **blackbox-exporter**    | HTTP/TCP probe (외부 가용성)           |
| **ceph-exporter (내장)** | Ceph 클러스터 상태                     |

---

## 3. kube-prometheus-stack

### 3.1 한 번에 설치되는 것

`prometheus-community/kube-prometheus-stack` Helm chart:

| 컴포넌트                       | 역할                                                              |
| ------------------------------ | ----------------------------------------------------------------- |
| **Prometheus Operator**        | CRD (ServiceMonitor, PodMonitor, PrometheusRule 등)로 K8s 식 설정 |
| **Prometheus**                 | 메트릭 DB                                                         |
| **Alertmanager**               | 알림 그룹/라우팅/silence                                          |
| **Grafana**                    | 대시보드                                                          |
| **node-exporter** (DaemonSet)  | 모든 노드의 OS 메트릭                                             |
| **kube-state-metrics**         | K8s 객체 상태                                                     |
| **Prometheus default rules**   | K8s 표준 알림 룰 (디스크 풀, OOM 등)                              |
| **Grafana default dashboards** | K8s 표준 대시보드                                                 |

### 3.2 ServiceMonitor / PodMonitor

Prometheus Operator의 핵심 CRD. "무엇을 scrape할지" K8s 식으로 정의.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: kosa-tickets
  labels:
    release: kube-prom # ← Prometheus Operator의 selector 매칭
spec:
  selector:
    matchLabels: { app: my-app }
  endpoints:
    - port: metrics # ← Service의 named port
      path: /metrics
      interval: 30s
```

Service에 `metrics` 포트가 있고, ServiceMonitor가 그 Service를 select → Prometheus가 자동 scrape.

### 3.3 우리 helm values 발췌

```yaml
nameOverride: kube-prom
namespaceOverride: monitoring

prometheus:
  prometheusSpec:
    nodeSelector:
      workload-type: system
    retention: 7d # ← TSDB 보존
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: team2-rbd-block
          resources: { requests: { storage: 50Gi } }
    serviceMonitorSelectorNilUsesHelmValues:
      false
      # ← 다른 차트의 ServiceMonitor도 scan
    ruleSelectorNilUsesHelmValues: false

grafana:
  nodeSelector:
    workload-type: system
  deploymentStrategy:
    type: Recreate # ← RWO PVC라 RollingUpdate 불가
  persistence:
    enabled: true
    storageClassName: team2-rbd-block
    size: 5Gi
  ingress:
    enabled: true
    ingressClassName: haproxy
    annotations:
      kubernetes.io/ingress.class: haproxy
      cert-manager.io/cluster-issuer: kosa-ca-issuer
    hosts: [grafana.kosa.team2]
    tls:
      - hosts: [grafana.kosa.team2]
        secretName: grafana-tls
  adminPassword: kosa1004

alertmanager:
  alertmanagerSpec:
    nodeSelector:
      workload-type: system
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: team2-rbd-block
          resources: { requests: { storage: 5Gi } }
```

> ⚠️ **Grafana deploymentStrategy: Recreate**: 기본 RollingUpdate는 새 Pod이 뜨면서 동시에 PVC mount
> → RWO 충돌. Recreate는 old 죽인 후 new 띄움.

---

## 4. kubeadm 메트릭 포트 함정

### 4.1 문제

kubeadm 기본값으로 K8s 시스템 컴포넌트는 메트릭 포트를 **127.0.0.1**에만 binding. 외부 Prometheus가
scrape 불가.

| 컴포넌트                | 포트  | 기본 binding |
| ----------------------- | ----- | ------------ |
| kube-controller-manager | 10257 | 127.0.0.1    |
| kube-scheduler          | 10259 | 127.0.0.1    |
| etcd                    | 2381  | 127.0.0.1    |
| kube-proxy              | 10249 | 127.0.0.1    |

### 4.2 해결: 0.0.0.0 binding

각 CP 노드에서:

**`/etc/kubernetes/manifests/kube-controller-manager.yaml`**:

```yaml
spec:
  containers:
    - command:
        - kube-controller-manager
        - --bind-address=0.0.0.0 # ← 추가/수정
        # ... (기존 옵션들)
```

**`/etc/kubernetes/manifests/kube-scheduler.yaml`**:

```yaml
- --bind-address=0.0.0.0
```

**`/etc/kubernetes/manifests/etcd.yaml`**:

```yaml
- --listen-metrics-urls=http://0.0.0.0:2381
```

이건 static manifest → kubelet이 자동 감지 → 컨테이너 재시작.

**`kube-proxy` ConfigMap**:

```bash
kubectl -n kube-system edit configmap kube-proxy
# metricsBindAddress: "0.0.0.0:10249"
kubectl -n kube-system rollout restart daemonset kube-proxy
```

Ansible playbook `35-metrics-exposure.yml`로 자동화.

### 4.3 검증

```bash
# kube-prometheus-stack의 target 확인
kubectl get --raw \
  /api/v1/namespaces/monitoring/services/kube-prom-kube-prometheus-prometheus:web/proxy/api/v1/targets \
  | jq '.data.activeTargets[] | select(.health!="up") | {labels, lastError}'
```

또는 Prometheus UI → Status → Targets.

---

## 5. Grafana 대시보드

### 5.1 기본 대시보드 (kube-prom-stack 포함)

자동 import 되는 dashboard:

- **Kubernetes / Compute Resources / Cluster** — 클러스터 전체 자원
- **Kubernetes / Compute Resources / Namespace (Pods)** — namespace별
- **Kubernetes / Compute Resources / Node (Pods)** — 노드별
- **Kubernetes / API server** — API 응답 시간/에러율
- **Kubernetes / Networking / Cluster** — 네트워크 트래픽
- **Node Exporter / Nodes** — OS 레벨 (CPU, memory, disk)
- **Kubernetes / Persistent Volumes** — PV 사용량

### 5.2 추가 권장 (커뮤니티)

| 대시보드            | ID                | 용도               |
| ------------------- | ----------------- | ------------------ |
| **Calico Felix**    | 12175             | Calico 상태        |
| **HAProxy Ingress** | (chart 자체 제공) | Ingress 트래픽     |
| **Ceph Cluster**    | 2842              | Ceph 클러스터 전체 |
| **Ceph Pools**      | 5342              | Pool별 IOPS        |
| **Jenkins**         | 9964              | Build 통계         |

import: Grafana UI → Dashboards → Import → ID 입력.

### 5.3 커스텀 대시보드 (앱)

ticket-app이 자체 메트릭 노출 (예: FastAPI의 prometheus_fastapi_instrumentator):

- 요청 수, 응답 시간, 에러율
- ServiceMonitor 정의 → Prometheus scrape → Grafana 패널

---

## 6. Alertmanager 알림

### 6.1 PrometheusRule (알림 정의)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kosa-tickets-rules
  namespace: monitoring
  labels:
    release: kube-prom
spec:
  groups:
    - name: kosa-tickets
      rules:
        - alert: TicketAppDown
          expr: up{job="ticket-app"} == 0
          for: 2m
          labels: { severity: critical }
          annotations:
            summary: "ticket-app pod down"
            description: "{{ $labels.pod }} has been down for 2 minutes"

        - alert: TicketAppHighErrorRate
          expr: |
            sum(rate(http_requests_total{job="ticket-app",status=~"5.."}[5m]))
            / sum(rate(http_requests_total{job="ticket-app"}[5m])) > 0.05
          for: 5m
          labels: { severity: warning }
```

### 6.2 Alertmanager 라우팅

```yaml
alertmanager:
  config:
    route:
      receiver: "slack-default"
      group_by: ["alertname", "cluster"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers:
            - severity = critical
          receiver: "slack-critical"
          repeat_interval: 1h
    receivers:
      - name: "slack-default"
        slack_configs:
          - api_url: "<webhook-url>"
            channel: "#alerts"
      - name: "slack-critical"
        slack_configs:
          - api_url: "<webhook-url>"
            channel: "#alerts-critical"
            send_resolved: true
```

(우리는 아직 Slack 연동 미설정. PagerDuty/OpsGenie도 가능)

### 6.3 Silence

운영 중 정기 작업으로 알림 폭주 방지:

```
Alertmanager UI → New Silence → matcher + 기간 설정
```

---

## 7. 구축 절차

### 7.1 ArgoCD Application

`~/kosa-gitops/apps/_applications/monitoring.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: monitoring, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 85.0.2
    helm:
      values: |
        # (위 §3.3 values)
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers: [/spec/volumeClaimTemplates]
    - kind: Secret
      jsonPointers: [/data]
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jsonPointers: [/webhooks]
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jsonPointers: [/webhooks]
```

### 7.2 메트릭 포트 노출 (Ansible)

```yaml
# 35-metrics-exposure.yml
- name: bind controller-manager metrics on 0.0.0.0
  lineinfile:
    path: /etc/kubernetes/manifests/kube-controller-manager.yaml
    regexp: "--bind-address="
    line: "    - --bind-address=0.0.0.0"
# (scheduler, etcd 동일)
- name: kube-proxy bind
  replace:
    path: ... # 또는 kubectl edit
```

### 7.3 첫 접속

```bash
open https://grafana.kosa.team2
# admin / kosa1004
```

import default dashboards 자동.

---

## 8. 운영 치트시트 (PromQL)

```promql
# 노드별 CPU 사용률
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 노드별 메모리 사용률
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod 메모리 사용 (namespace별 합)
sum by(namespace) (container_memory_working_set_bytes{container!=""})

# API server 응답 시간 (95 percentile)
histogram_quantile(0.95,
  rate(apiserver_request_duration_seconds_bucket[5m]))

# Ingress 요청 rate (서비스별)
sum by(ingress) (rate(haproxy_ingress_http_requests_total[5m]))

# Pod 재시작 (지난 1시간)
sum by(pod, namespace) (rate(kube_pod_container_status_restarts_total[1h])) > 0

# PV 사용률
(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100
```

---

## 9. 트러블슈팅

### 9.1 Target down

```
Prometheus UI → Status → Targets
```

down 이유:

- 포트 안 열림 (kubeadm 함정 §4)
- Service selector 미스매치
- TLS/auth 필요한데 설정 X

### 9.2 ServiceMonitor 인식 안 됨

```bash
kubectl get servicemonitor -A
# 우리 SM이 보여야

# Prometheus Operator log
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=100
```

원인:

- `release: kube-prom` 라벨 누락 (Operator의 selector)
- 다른 namespace에 있는데 `serviceMonitorNamespaceSelector` 제한

### 9.3 Grafana 로그인 실패

```bash
# adminPassword 확인
kubectl get secret -n monitoring kube-prom-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

PVC 재초기화 필요할 수도.

### 9.4 Grafana progress deadline

Deployment Recreate 안 했을 가능성. helm values에 `deploymentStrategy.type: Recreate`.

### 9.5 Prometheus TSDB 디스크 풀

```bash
kubectl exec -n monitoring prometheus-kube-prom-prometheus-0 -c prometheus -- df -h /prometheus
```

- retention 단축 (`retention: 3d`)
- PVC 크기 ↑
- 또는 remote storage (Thanos)

### 9.6 알림 안 옴

```bash
# Alertmanager status
kubectl get --raw /api/v1/namespaces/monitoring/services/alertmanager-operated:9093/proxy/api/v2/alerts

# Slack webhook 테스트
curl -X POST -H 'Content-Type: application/json' \
  --data '{"text":"test"}' \
  https://hooks.slack.com/services/XXX
```

### 9.7 PromQL이 데이터 없음

- target up 확인
- 라벨 매칭 정확 (`{job="..."}` 등)
- 시간 범위 (right top)

### 9.8 자원 사용 폭증

Prometheus 자체가 메모리 많이 먹음. RAM/CPU request 조정.

---

## 10. 다음 챕터

→ **[12. 운영 & 백업](12-operations.md)**

일상 운영 체크리스트, etcd/Ceph 백업, 노드 교체/확장, K8s 업그레이드, 인증서 갱신 캘린더, 통합
트러블슈팅 인덱스.
