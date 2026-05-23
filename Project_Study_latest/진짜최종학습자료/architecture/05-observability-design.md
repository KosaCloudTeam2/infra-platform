# 05. 관측성 설계 (3대축)

> ⭐ **한 줄 요약**: **Prometheus (메트릭) + Tempo (트레이스) + Loki (로그)** 3대축을 모두 자체 호스팅하고, **OpenTelemetry Operator로 코드 변경 없이 자동 계측**한다. AlertManager가 같은 alert를 email + AWS Lambda webhook으로 다르게 라우팅한다.

---

## 🎯 우리가 한 선택

관측성 (Observability)은 "**무엇이 잘못됐나"** (메트릭), **"왜"** (로그), **"어디서"** (트레이스)를 답하는 세 가지 데이터의 통합이다. 우리는 각 영역을 가장 보편적인 CNCF 도구로 구축했다.

| 축 | 도구 | 버전 | 배치 |
|---|---|---|---|
| **Metrics** | Prometheus + Grafana + AlertManager | kube-prometheus-stack 85.0.2 | sys1 |
| **Traces** | Tempo (monolithic) | grafana/tempo 1.10.1 | sys1, RBD PVC 10Gi |
| **Logs** | Loki + Promtail (DaemonSet) | loki 2.9.10 / loki-stack 2.10.2 | Loki sys1, Promtail 전 노드 |
| **Auto-instrumentation** | OpenTelemetry Operator | 0.68.0 | opentelemetry-operator-system ns |
| **TLS** | cert-manager (자체 CA) | v1.x | cert-manager ns |

### AlertManager 라우팅 — 핵심 설계

AlertManager의 라우팅이 우리 관측성 설계의 가장 정교한 부분이다. 같은 alert를 **두 가지 receiver로 다르게 보낸다**: 일반 alert는 운영자 email로, burst trigger label이 붙은 alert는 AWS Lambda webhook으로.

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

이 패턴이 강력한 이유는 **alert label로 라우팅을 분기**한다는 점이다. Prometheus rule에서 `labels: { burst_trigger: "true" }`를 추가하면 그 alert만 webhook으로 가고, 나머지는 모두 email로 간다. 새 라우팅 시나리오 (예: Slack, PagerDuty) 추가도 receiver를 정의하고 matcher만 작성하면 끝이다.

### OpenTelemetry Auto-Instrumentation — 코드 변경 0

전통적으로 분산 트레이싱을 도입하려면 각 service에 SDK를 import하고 manual instrumentation을 작성해야 했다. 우리는 그 대신 **OpenTelemetry Operator를 써서 annotation 한 줄로 자동 계측**을 달성했다.

```yaml
# ticket-app deployment에 추가
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-python: "true"
```

이 한 줄이 끝이다. Operator가 ticket-app Pod에 initContainer를 자동으로 주입해서 Python SDK를 Pod에 mount하고, Python import path에 등록한다. ticket-app이 사용하는 FastAPI, SQLAlchemy, requests 같은 라이브러리들이 자동으로 후킹되어 trace가 Tempo로 전송된다. **코드 한 줄도 안 바꾼다.**

---

## 🔍 고려한 대안들

### Q1. 3대축 분리 vs 통합 솔루션 (Datadog, New Relic)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **분리 (Prom+Tempo+Loki) 선택** | 무료, 오픈소스, 학습 가치, 데이터 주권 | 컴포넌트 관리 부담 | ★★★★★ |
| Datadog | 통합 UI, 즉시 사용 | $15+/호스트/월, vendor lock-in | ★★ |
| New Relic | APM 강력 | 동일 SaaS 함정 | ★★ |
| Dynatrace | enterprise 최고급 | 매우 비쌈 | ★ |

가장 큰 결정 포인트는 **"하나의 SaaS로 통합 vs 3개 OSS로 분리"**다. Datadog/New Relic 같은 통합 솔루션은 첫인상이 매력적이다. 하나의 UI, 즉시 사용 가능, 운영 부담 0. 하지만 자세히 보면 세 가지 큰 단점이 있다.

**비용**이 첫 번째다. Datadog Pro 기준 호스트당 $15+/월인데, 우리 7 호스트면 $100+/월. 추가로 trace volume, log GB로 더 청구된다. 우리 워크로드 기준 월 $200+ 수준이다. 자체 호스팅하면 sys1 자원 (RAM ~6GB)만 추가하면 되니 사실상 $0이다.

**데이터 주권**이 두 번째다. 우리 사용자 행동 로그, 코드 stack trace, 인프라 메트릭이 모두 외부 SaaS로 흘러간다. PII 데이터를 다루는 우리 환경에서 컴플라이언스 위험이 있다.

**Vendor lock-in**이 세 번째다. Datadog에 익숙해지면 다른 도구로 옮기기 어렵다. OpenTelemetry는 vendor-neutral 표준이라 백엔드를 Tempo, Jaeger, Datadog, 어디든 자유롭게 교체 가능하다.

### Q2. Metrics — Prometheus vs Mimir vs Thanos vs VictoriaMetrics

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Prometheus (선택)** | 사실상 표준, 가장 단순 | 단일 인스턴스 (HA 부족), retention 한계 | ★★★★★ |
| Thanos | Prometheus HA + 장기 보관 (S3) | 컴포넌트 7개, 학습 곡선 | ★★★ |
| Mimir | Grafana 새 솔루션 | 신규, 자료 적음 | ★★★ |
| VictoriaMetrics | 빠름, 압축 ↑ | 커뮤니티 작음 | ★★★ |

Prometheus는 CNCF 졸업한 사실상 표준이다. 가장 단순하고 자료가 풍부하다. 단점은 **단일 인스턴스라 HA가 약하고, 장기 보관 (months/years)에 부적합**하다. Thanos가 이걸 해결하는데 (Prometheus replicas 2 + S3 백엔드로 무제한 보관 + dedup), 컴포넌트가 7개 (compactor, store, query, sidecar 등)라 학습/운영 부담이 크다.

우리는 학습 환경엔 단순한 Prometheus로 시작하고, sys2 추가와 함께 Thanos 도입을 검토하는 단계적 접근을 골랐다. 현재 7일 retention으로도 학습 용도엔 충분하다.

### Q3. Traces — Tempo vs Jaeger vs Zipkin

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Tempo (선택)** | Grafana 통합 ↑, S3 백엔드 지원 | UI는 Grafana 의존 | ★★★★★ |
| Jaeger | 자체 UI 풍부, 검증됨 | 별도 UI, Grafana 통합 추가 | ★★★★ |
| Zipkin | 오래됨, 단순 | 기능 적음 | ★★ |

Tempo는 Grafana Labs가 만든 trace 백엔드라 **Grafana와 통합이 가장 자연스럽다**. trace → log 점프, trace → metric 점프 같은 기능이 native 지원된다. Jaeger는 자체 UI가 더 풍부하지만, 우리는 이미 Grafana를 메인 UI로 쓰고 있어 Tempo가 일관성 있다.

### Q4. Logs — Loki vs ELK vs Fluentd+S3

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Loki (선택)** | label-only 인덱스 (저장 효율 ★★★), Grafana 통합 | full-text 검색 약함 | ★★★★★ |
| ELK | full-text 강력, 풍부한 UI | 무거움 (메모리 ★★★★), 운영 부담 | ★★★ |
| Splunk | enterprise 최고급 | 매우 비쌈 | ★ |

Loki의 차별점은 **label만 인덱스화**하고 로그 본문은 인덱스 안 한다는 점이다. ELK가 모든 단어를 인덱스해서 빠른 full-text 검색을 제공하는 반면, Loki는 `{namespace="kosa-tickets"}` 같은 label로 chunk를 좁힌 다음 grep으로 본문 검색한다. 결과는 **인덱스 저장 공간 1/10 + 메모리 사용량 1/5**다.

단점은 "ticket-app 로그에서 'OOMKilled' 검색" 같은 full-text 쿼리가 느릴 수 있는 점인데, 우리 워크로드 규모엔 충분히 빠르다 (수 초 내).

### Q5. Auto-instrumentation — OTel Operator vs Manual SDK vs Datadog Agent

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **OTel Operator (선택)** | annotation 1줄, 코드 변경 0 | Operator 학습 | ★★★★★ |
| Manual SDK | 정밀 통제 | 코드 변경 ★★★, 각 언어별 SDK 학습 | ★★★ |
| Datadog Agent 등 | SaaS 통합 | vendor lock-in | ★★ |

OTel Operator는 정말 게임 체인저다. annotation 한 줄로 ticket-app 코드 변경 없이 자동 계측이 완성된다. Java/Go/Node.js/Python 등 주요 언어 모두 지원한다. 미래에 ticket-app을 Java로 재작성해도 같은 패턴으로 즉시 적용 가능하다.

---

## 💡 왜 이걸 선택했나

다섯 가지 이유로 정리할 수 있다.

**첫째, 3대축 = 진짜 root cause 추적이 가능**해진다. 메트릭만 있으면 "p99 latency 3s"라는 사실은 알지만 어디가 느린지 모른다. 트레이스가 "DB 쿼리에서 2.8s 소비"를 알려주고, 로그가 "DB 쿼리 missing index"를 알려준다. **셋이 함께 있어야 진단 흐름이 완성**된다.

**둘째, 무료 + 데이터 주권 확보.** Datadog 30 호스트면 $450+/월 (₩60만+/월)인데, 우리는 자체 호스팅으로 sys1 추가 자원 (메모리 ~6GB) 외엔 ₩0이다. 데이터도 우리 클러스터에 머무르니 컴플라이언스 위험도 ↓이다.

**셋째, OTel auto-instrumentation = 코드 변경 0.** ticket-app deployment에 annotation 한 줄로 trace가 자동 흐른다. 다른 마이크로서비스 추가해도 같은 패턴으로 즉시 적용 가능하다. 진짜 zero-touch instrumentation이다.

**넷째, AlertManager 라우팅이 정교**하다. 같은 alert를 receiver별로 다르게 처리할 수 있다. 일반 alert는 email, burst trigger는 webhook, critical은 PagerDuty 같은 식으로 무한 확장 가능하다.

**다섯째, 학습 가치 + 면접 어필.** OpenTelemetry는 2024년 CNCF 인큐베이팅 졸업으로 사실상 표준이 됐다. 3대축을 깊이 이해하는 건 SRE 직무 필수 역량이고, 면접에서 자주 등장하는 주제다.

---

## 💰 비용 분석

### sys1 자원 사용

| 컴포넌트 | 메모리 | PVC |
|---|---|---|
| Prometheus | ~1.2 GB | 10 Gi |
| Grafana | ~200 MB | 2 Gi |
| AlertManager | ~100 MB | 1 Gi |
| Tempo | ~256 MB | 10 Gi |
| Loki | ~512 MB | 20 Gi |
| OTel Operator | ~200 MB | - |
| Promtail × 7 노드 | ~100 MB × 7 (분산) | - |
| **합계** | **~2.5 GB (sys1)** | **43 Gi** |

sys1 16GB RAM 중 약 2.5GB가 관측성 stack에 들어간다. Harbor (1.5GB) + Jenkins (500MB) + ArgoCD (500MB) 합쳐도 sys1 자원에 여유가 있다 (60% 사용).

### Datadog/New Relic 대비 절감 (월간)

| SaaS | 우리 환경 기준 | 월 비용 |
|---|---|---|
| Datadog Pro | 7 호스트 + 1M traces + 50GB logs | $200+ |
| New Relic | 4 user + ~50GB | $300+ |
| **우리 (자체)** | sys1 추가 메모리만 | **~$0** |

→ **연간 $2,400+ 절감**. 학습 환경에선 큰 액수는 아니지만 진짜 운영급 가면 누적적 절감이 크다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 3개 도구 = 정확한 진단 | 3개 운영 부담 |
| 무료 | SaaS UX 편의 (one-click setup) |
| 데이터 주권 | 외부 expert support |
| OTel auto = 코드 0줄 | OTel Operator 학습 |
| AlertManager 정교 | YAML 복잡도 |

가장 큰 trade-off는 **운영 부담**이다. SaaS면 setup 30분이지만 우리는 helm chart 설정 + GitOps + 함정 (PVC fsGroup, Grafana migration timeout 등) 다 풀어야 했다. 그 대신 한번 구축하면 비용 0 + 확장 가능 + 데이터 주권이라는 장점이 누적된다.

---

## ⚠️ SPoF + 회복

| SPoF | 영향 | 회복 |
|---|---|---|
| **Prometheus 다운** | 메트릭 수집 멈춤, alert 안 옴 | Pod 재시작. sys2 추가 시 replica HA |
| **AlertManager 다운** | alert 누락 | replicas 3 spec (현재 sys1 1대라 1만 active) |
| **Grafana 다운** | 시각화 못 봄 (데이터는 안전) | Pod 재시작 |
| **Tempo 다운** | 새 trace 못 받음 | PVC 살아있으면 자동 회복 |
| **Loki 다운** | 새 log 못 받음 (Promtail이 buffer) | 회복 후 buffer flush |

Prometheus가 죽으면 메트릭 수집이 멈춰서 SLA/SLO 측정도 끊기고, alert도 안 발사된다. **이게 burst trigger가 안 동작하는 시나리오와 연결**된다 (Prometheus 죽음 → AlertManager 발사 X → Lambda 호출 X → burst 안 됨). 그래서 Prometheus HA가 진짜 운영급의 필수다.

Loki는 Promtail이 일정 시간 buffer를 잡고 있어서 (default 30분), 잠깐 Loki 다운돼도 로그 손실 없이 회복 후 flush한다. 다만 30분 넘게 down이면 그 사이 로그는 손실 가능.

---

## 🚀 확장 가능성

### Option A: ⭐ Thanos 도입 (Prometheus 장기 보관 + HA)

Prometheus의 가장 큰 약점인 단일 인스턴스 + 짧은 retention을 해결하는 표준 솔루션이다. Prometheus replicas 2 + Thanos sidecar로 메트릭이 S3 (우리 Ceph RGW)로 자동 upload되고, query federation으로 통합 조회된다. dedup도 자동.

- 💰 **비용**: Ceph RGW (이미 있음), 0 추가
- ⏱️ **작업**: 1주 (컴포넌트 7개 설정 + 검증)
- 🎯 **추천 시점**: retention 30일+ 필요 또는 sys2 추가하면서 HA 동시 구축

### Option B: ⭐ Loki S3 backend로 전환 (현재 RBD)

현재 Loki가 RBD PVC에 데이터 저장 중인데, S3 backend로 전환하면 수평 확장 + 장기 보관 효율이 크게 ↑된다. Ceph RGW를 backend로 쓰면 비용도 0이다.

- 💰 **비용**: 0
- ⏱️ **작업**: 2~4시간 (helm values 수정 + 마이그레이션)
- 🎯 **추천 시점**: 로그량 증가 또는 retention 30일+ 필요

### Option C: Tempo S3 backend

위와 같은 패턴으로 Tempo도 S3 backend로 전환 가능하다.

### Option D: Pyroscope 추가 (Profiling)

CPU/메모리 profiling을 통해 코드 레벨 병목을 찾는 도구다. 메트릭 (어떤 endpoint 느림) → trace (어떤 span에서 시간 소비) → profile (코드 어느 라인이 느림) 순으로 깊이 들어갈 수 있다. 진짜 성능 튜닝 단계에서 가치 있다.

### Option E: Grafana OnCall (PagerDuty 대체 SaaS)

무료 alert 스케줄링 + on-call rotation + escalation. 운영 진입 + 24/7 on-call 시작 시점에 유용.

### Option F: SLO Dashboard (Sloth or Pyrra)

SLI/SLO/Error Budget을 시각화하는 도구. 운영 성숙 단계에서 의미 있다.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 메트릭 retention 부족 (7일 → 30일+) | A or B |
| 로그 보관 정책 강화 | B |
| 성능 튜닝 단계 | D |
| on-call 운영 | E |
| 운영 성숙 | F |

---

## 🔗 다른 파트와의 연결

이 관측성 stack은 burst 아키텍처의 trigger 시작점이다 (`04-burst-architecture.md`). 데이터 측면에선 Prometheus/Loki/Tempo의 PVC와 향후 S3 backend 전환 (`data-storage/04-s3-comparison.md`)이 관련된다. 보안 측면에서 Grafana 외부 노출 + 인증 (`security/05-secrets-rbac.md`)과 AlertManager webhook 인증 (`security/06-burst-trigger-security.md`)도 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Datadog 한 번에 살 수 있는데 왜 굳이 3개 도구를?**

A. 세 가지 이유 때문입니다. **비용**: 월 $200+ vs $0. **데이터 주권**: 외부 SaaS에 사용자 데이터 보내는 것의 컴플라이언스 위험. **학습 가치**: OpenTelemetry는 vendor-neutral 표준이라 한번 익히면 어디서나 통합. **Vendor lock-in 회피**도 큽니다. 단점은 운영 부담인데 kube-prometheus-stack helm chart로 자동화 + GitOps로 완화했습니다.

**Q2. OpenTelemetry vs Datadog APM 차이는?**

A. **OTel은 vendor-neutral 표준 (CNCF)**입니다. 백엔드를 Tempo, Jaeger, Datadog, New Relic 어디든 자유롭게 보낼 수 있습니다. 한 번 계측하면 백엔드 교체가 endpoint URL 변경 한 줄입니다. Datadog APM은 Datadog에만 가는 vendor-specific 솔루션입니다.

**Q3. 코드 변경 없이 trace를 어떻게 자동 추가하나요?**

A. **OTel Operator의 initContainer가 Python SDK를 Pod에 mount**합니다. Python import path에 자동 등록되어, ticket-app이 import한 FastAPI/SQLAlchemy 같은 라이브러리들이 자동으로 후킹됩니다. Java/Go/Node.js도 같은 패턴이고 각 언어별 instrumentation library를 OTel이 관리합니다.

**Q4. 메트릭/로그/트레이스 보존 정책은요?**

A. 현재 모두 7일입니다 (Prometheus RBD 10Gi, Loki RBD 20Gi, Tempo RBD 10Gi). 학습 환경에 충분한 수치고, **장기 보관 필요시 Thanos+S3 (Option A) 또는 Loki/Tempo S3 (Option B/C)**로 확장합니다. Ceph RGW를 S3 backend로 쓰면 비용 0입니다.

**Q5. AlertManager 죽으면 burst trigger 안 되나요?**

A. **네, 그래서 AlertManager는 replicas 3 spec입니다**. 다만 현재 sys1 1대라 실제로는 1개만 active 상태입니다. **sys2 추가하면 진짜 3-노드 cluster**로 HA 완성됩니다. burst trigger가 critical 흐름이라 Phase 6 우선 작업 중 하나입니다.

**Q6. trace를 모든 요청에 받으면 비용/저장 폭증 아닌가요?**

A. 정확한 지적입니다. 그래서 **sampling 적용**이 핵심입니다. 현재는 `parentbased_traceidratio 1.0` (100% 데모용)인데, 운영급은 `0.01` (1%) 정도로 줄입니다. 또는 **tail-based sampling**으로 "에러는 100%, 성공은 1%" 같은 정밀 정책도 가능합니다.
