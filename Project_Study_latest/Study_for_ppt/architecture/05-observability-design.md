# 05. 관측성 설계 (3대축)

> ⭐ **한 줄 요약**: **Prometheus (Metrics) + Tempo (Traces) + Loki (Logs)** 3대축 + **OpenTelemetry 자동 계측** (코드 0줄). AlertManager가 email + AWS Lambda webhook 동시 라우팅.

---

## 🎯 우리가 한 선택

### 스택 구성
| 축 | 도구 | 버전 | 배치 |
|---|---|---|---|
| **Metrics** | Prometheus + Grafana + AlertManager | kube-prometheus-stack 85.0.2 | sys1 (workload-type=system) |
| **Traces** | Tempo (monolithic) | grafana/tempo 1.10.1 | sys1, RBD PVC 10Gi |
| **Logs** | Loki + Promtail (DaemonSet) | loki 2.9.10 / loki-stack 2.10.2 | Loki sys1, Promtail 전 노드 |
| **Auto-instrumentation** | OpenTelemetry Operator | 0.68.0 | opentelemetry-operator-system ns |
| **TLS** | cert-manager (자체 CA) | v1.x | cert-manager ns |

### AlertManager 라우팅
```yaml
route:
  receiver: email                    # default
  routes:
    - matchers:
      - burst_trigger="true"
      receiver: aws-burst            # 특별 라우팅 (Lambda)
      group_wait: 0s                 # 즉시
      repeat_interval: 1m

receivers:
  - name: email
    email_configs:
      - to: parkpark131@naver.com
        smtp_smarthost: smtp.gmail.com:587
        smtp_from: qkrtkdcjfgcp@gmail.com
  - name: aws-burst
    webhook_configs:
      - url: https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com/
```

### OpenTelemetry Auto-Instrumentation
- ticket-app deployment에 annotation 1줄:
  ```yaml
  instrumentation.opentelemetry.io/inject-python: "true"
  ```
- → OTel Operator가 initContainer로 SDK 주입
- → ticket-app 코드 변경 0줄
- → trace가 자동으로 Tempo로 전송

---

## 🔍 고려한 대안들

### Q1. 3대축 분리 vs 통합 솔루션 (Datadog, New Relic, Dynatrace)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **분리 (Prom+Tempo+Loki) 선택** | 무료, 오픈소스, 학습 가치, 데이터 주권 | 컴포넌트 관리 부담 | ★★★★★ |
| Datadog | 통합 UI, 즉시 사용 | $15/호스트/월 이상, vendor lock-in | ★★ (학습 비추) |
| New Relic | APM 강력 | 동일 SaaS 함정 | ★★ |
| Dynatrace | enterprise 최고급 | 매우 비쌈 | ★ |

### Q2. Metrics — Prometheus vs Mimir vs Thanos vs VictoriaMetrics

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Prometheus (선택)** | 사실상 표준, 가장 단순 | 단일 인스턴스 (HA 부족), retention 한계 | ★★★★★ |
| Thanos | Prometheus HA + 장기 보관 (S3) | 컴포넌트 7개, 학습 곡선 | ★★★ (확장 시) |
| Mimir | Grafana 새 솔루션 | 신규, 자료 적음 | ★★★ |
| VictoriaMetrics | 빠름, 압축 ↑ | 커뮤니티 작음 | ★★★ |

### Q3. Traces — Tempo vs Jaeger vs Zipkin

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Tempo (선택)** | Grafana 통합 ↑, S3 백엔드 지원 | UI는 Grafana 의존 | ★★★★★ |
| Jaeger | 자체 UI 풍부, 검증됨 | 별도 UI, Grafana 통합 추가 | ★★★★ |
| Zipkin | 오래됨, 단순 | 기능 적음 | ★★ |

### Q4. Logs — Loki vs ELK vs Fluentd+S3

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Loki (선택)** | label-only 인덱스 (가볍고 저장 효율 ★★★), Grafana 통합 | full-text 검색 약함 | ★★★★★ |
| ELK (Elasticsearch+Kibana) | full-text 강력, 풍부한 UI | 무거움 (메모리 ★★★★), 운영 부담 | ★★★ |
| Fluentd + S3 + Athena | 매우 저렴 (보관) | 실시간 조회 어려움 | ★★ |
| Splunk | enterprise 최고급 | 매우 비쌈 | ★ |

### Q5. Auto-instrumentation — OTel Operator vs Manual SDK vs Agent

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **OTel Operator (선택)** | annotation 1줄, 코드 변경 0 | Operator 학습 | ★★★★★ |
| Manual SDK | 정밀 통제 | 코드 변경 ★★★, 각 언어별 SDK | ★★★ |
| Datadog Agent 등 | SaaS 통합 | vendor lock | ★★ |

---

## 💡 왜 이걸 선택했나 (5가지)

### 1. 🔧 **3대축 = 진짜 관측성**
> 🔥 **핵심**: 메트릭은 "무엇이" 잘못됐는지, 로그는 "왜", 트레이스는 "어디서" 답한다.

- 메트릭만 있으면 "p99 latency 3s" 같은 사실만 알지 어디가 느린지 모름
- 트레이스가 "DB 쿼리에서 2.8s 소비" 알려줌
- 로그가 "DB 쿼리 missing index" 알려줌
- 3개 다 있어야 root cause 빠르게 도달

### 2. 💰 **무료 + 데이터 주권**
- Datadog 30 호스트 = $450/월 = ₩60만/월
- 우리: 자체 호스팅 sys1 추가 자원 (메모리 ~6GB) → ₩0
- 데이터가 우리 클러스터에 있음 → 컴플라이언스 ↑

### 3. ⚡ **OTel auto-instrumentation = 0 코드 변경**
- ticket-app deployment에 annotation 1줄
- 코드는 한 글자도 안 건드림
- 다른 언어 (Java, Go) 추가도 같은 패턴

### 4. 🎯 **AlertManager 라우팅 정교**
- 일반 alert → email
- burst trigger label → Lambda webhook
- 같은 alert를 receiver별로 다른 처리

### 5. 📚 **학습 가치 + 면접 어필**
- OpenTelemetry는 2024 CNCF 인큐베이팅 졸업 (사실상 표준)
- 3대축 깊이 이해는 SRE 직무 필수

---

## 💰 비용 분석

### sys1 자원 사용
| 컴포넌트 | 메모리 | 디스크 (PVC) |
|---|---|---|
| Prometheus | ~1.2 GB | 10 Gi |
| Grafana | ~200 MB | 2 Gi |
| AlertManager | ~100 MB | 1 Gi |
| Tempo | ~256 MB | 10 Gi |
| Loki | ~512 MB | 20 Gi |
| OTel Operator | ~200 MB | - |
| Promtail × 7 노드 | ~100 MB × 7 = 700 MB (분산) | - |
| **합계 (sys1)** | **~2.5 GB** | **43 Gi** |

### Datadog/New Relic 비교 (월간)
| SaaS | 단가 | 우리 환경 (7 노드) | 월 비용 |
|---|---|---|---|
| Datadog Pro | $15/호스트 + traces + logs | 7 호스트 + 1M traces + 50GB logs | $200+ |
| New Relic | $25/유저 + 데이터 | 4 user + ~50GB | $300+ |
| **우리 (자체)** | 자원 비용 | sys1 추가 메모리 | **~$0** |

→ **연간 절감 $2,400+**

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 3개 도구 = 정확한 진단 | 3개 운영 부담 |
| 무료 | SaaS UX 편의 (one-click setup) |
| 데이터 주권 | 외부 expert support |
| OTel auto = 코드 0줄 | OTel Operator 학습 |
| AlertManager 정교 | YAML 복잡도 |

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **Prometheus 다운** | 메트릭 수집 멈춤, alert 안 옴 | Pod 재시작 (PVC reuse). sys2 추가 시 replica HA |
| **AlertManager 다운** | alert 누락 | replicas 3 spec (현재 sys1 1대라 1만 active) |
| **Grafana 다운** | 시각화 못 봄 (데이터는 안전) | Pod 재시작 |
| **Tempo 다운** | 새 trace 못 받음, 옛 trace 조회 불가 | PVC 살아있으면 자동 회복 |
| **Loki 다운** | 새 log 못 받음 (Promtail이 buffer) | 회복 후 buffer flush |
| **OTel Operator** | 새 Pod에 instrumentation 안 됨 | 기존 Pod은 영향 X |
| **자체 CA 만료 (10년)** | 모든 cert 망가짐 | 9년 뒤 catalog로 사전 회전 |

---

## 🚀 확장 가능성

### Option A: ⭐ Thanos 도입 (Prometheus 장기 보관 + HA)
- ✅ **장점**: S3에 메트릭 영구 보관, query federation, deduplication
- ❌ **단점**: 컴포넌트 7개 (compactor, store, query, sidecar 등)
- 💰 **비용**: Ceph RGW에 메트릭 저장 (S3 호환), 0 추가
- ⏱️ **작업**: 1주
- 🎯 **추천 시점**: retention 30일+ 필요 또는 sys2 추가하면서 HA 동시 구축

### Option B: ⭐ Loki S3 backend로 전환 (현재 RBD)
- ✅ **장점**: 수평 확장, 장기 보관 효율, RWO 제약 회피
- 💰 **비용**: Ceph RGW (이미 있음), 0 추가
- ⏱️ **작업**: 2~4시간 (helm values 수정 + 마이그레이션)
- 🎯 **추천 시점**: 로그량 증가 또는 retention 30일+ 필요

### Option C: Tempo S3 backend
- 위 Option B와 같은 패턴 (Tempo도 S3 지원)
- 🎯 **추천 시점**: trace 보존 30일+

### Option D: Pyroscope 추가 (Profiling)
- ✅ **장점**: CPU/메모리 profiling으로 코드 레벨 병목 찾기
- ❌ **단점**: 또 한 컴포넌트
- 🎯 **추천 시점**: 성능 튜닝 단계

### Option E: Grafana OnCall (PagerDuty 대체)
- ✅ **장점**: 무료 alert 스케줄링/escalation
- 🎯 **추천 시점**: on-call rotation 정식 운영

### Option F: SLO Dashboard (Sloth or Pyrra)
- ✅ **장점**: SLI/SLO/Error Budget 시각화
- 🎯 **추천 시점**: 운영 성숙

### Option G: 멀티 클러스터 통합 (EKS + 온프레)
- Prometheus federation 또는 Mimir로 통합
- 🎯 **추천 시점**: EKS burst 자주 + EKS metrics도 보고 싶을 때

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 메트릭 retention 부족 (7일 → 30일+) | A or B |
| 로그 보관 정책 강화 | B |
| 성능 튜닝 단계 | D |
| on-call 운영 | E |
| 운영 성숙 | F |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 자기 (`04-burst-architecture.md`) | AlertManager가 burst trigger의 시작점 |
| 💾 데이터 | Prometheus/Loki/Tempo의 PVC. 향후 S3 백엔드 전환. |
| 🔧 CI/CD | Grafana dashboard도 GitOps 관리 가능 (현재는 manual) |
| 🔒 보안 | Grafana 외부 노출 + 인증, AlertManager webhook 인증 (현재 없음) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Datadog 한 번에 살 수 있는데 왜 굳이 3개 도구?**
A. (1) 비용 (월 $200+ vs $0), (2) 데이터 주권 (외부 SaaS에 사용자 데이터 보내기 컴플라이언스 위험), (3) 학습 가치 (OpenTelemetry는 표준), (4) vendor lock-in 회피. 단점은 운영 부담인데 자동화 (kube-prometheus-stack helm chart) + GitOps로 완화.

**Q2. OpenTelemetry vs Datadog APM?**
A. OTel은 vendor-neutral 표준 (CNCF). 백엔드를 Tempo, Jaeger, Datadog, New Relic 어디든 보낼 수 있음. 한번 계측하면 백엔드 자유 교체. Datadog APM은 Datadog에만.

**Q3. 코드 변경 없이 trace 어떻게 자동 추가?**
A. OTel Operator의 initContainer가 Python SDK를 Pod에 mount → Python import path에 자동 등록 → ticket-app이 import한 FastAPI/SQLAlchemy 등이 SDK 후킹됨. Java/Go도 같은 패턴.

**Q4. 메트릭/로그/트레이스 보존 정책?**
A. Prometheus 7일 (RBD 10Gi), Loki 7일 (RBD 20Gi), Tempo 7일 (RBD 10Gi). 장기 보관 필요시 Thanos+S3 (option A) 또는 Loki/Tempo S3 (option B/C).

**Q5. AlertManager가 죽었는데 burst trigger는 동작?**
A. 안 됨 (AlertManager가 webhook 발사 주체). 그래서 AlertManager는 replicas 3 spec. 현재 sys1 1대라 1만 active이지만, sys2 추가하면 3-노드 cluster로 진짜 HA.

**Q6. trace를 모든 요청에 다 받으면 비용/저장 폭증 아닌가?**
A. 맞아서 **sampling** 적용. 우리 현재 `parentbased_traceidratio 1.0` (100% — 데모용). 운영급은 `0.01` (1%) 정도로 줄임. 또는 tail-based sampling (에러만 100%, 성공은 1%).
