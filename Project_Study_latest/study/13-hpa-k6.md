# 챕터 13: HPA + k6 부하 테스트

> KOSA 인프라 프로젝트 학습 시리즈 / 작성일 2026-05-13<br> 환경: K8s v1.30.14, Metrics Server
> (`--kubelet-insecure-tls`), ticket-app namespace `kosa-tickets`, LB 172.16.23.103

## 학습 후 알 수 있는 것

- HPA가 어떻게 metrics-server → HPA controller → Deployment scale로 동작하는지 흐름을 설명할 수
  있어요.
- 우리 ticket-app HPA의 `minReplicas: 2 / maxReplicas: 10 / CPU 50%`가 왜 이 값인지 근거를 댈 수
  있어요.
- `scaleUp.stabilizationWindowSeconds: 0`과 `scaleDown.stabilizationWindowSeconds: 60`의 차이,
  Percent vs Pods 정책의 의미를 설명할 수 있어요.
- k6의 VU(Virtual User), stage, threshold 개념과 JMeter/Locust 대비 장단점을 말할 수 있어요.
- 우리 k6 시나리오(10→100→500→0 VU, 180초)가 어떻게 HPA를 2→10 Pod로 끌어올리는지, Grafana에서 산
  모양 그래프가 왜 나오는지 메커니즘으로 설명할 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

- **HPA (Horizontal Pod Autoscaler)**: Pod의 CPU/Memory/커스텀 메트릭에 따라 Deployment의 replica
  수를 자동으로 증감시키는 K8s 빌트인 컨트롤러예요.
- **k6**: Grafana Labs가 만든 JavaScript 기반의 고성능 부하 테스트 도구로, 시나리오를 코드로
  작성하고 Go 런타임에서 실행해요.

### 1.2 등장 배경

**HPA:**

- 전통적 VM 시대 — 트래픽 폭증 시 운영자가 수동으로 인스턴스 추가. 응답 늦고 휴먼 에러 많음.
- AWS Auto Scaling이 모범 답안 제시(2009). 하지만 Pod 단위가 아닌 VM 단위라 K8s에는 부적합.
- K8s 1.2(2016)에서 HPA v1 도입 — CPU만. v2(2018)에서 multi-metric + custom metric 지원.

**k6:**

- 부하 테스트 도구의 클래식은 JMeter(Java, 무겁고 GUI 중심, 2001~).
- 모던 워크로드(REST API, gRPC, WebSocket)에 맞춘 가벼운 도구 수요 → 2017년 Load Impact가 k6 출시 →
  2021년 Grafana Labs가 인수.
- "코드로 시나리오 작성, CI 파이프라인 통합, Prometheus/Grafana 연계" 패턴이 SRE 표준이 됨.

### 1.3 핵심 개념 + 용어 풀이

**HPA 핵심 개념:**

| 용어                 | 의미                                                            |
| -------------------- | --------------------------------------------------------------- |
| metrics.k8s.io API   | metrics-server가 노출하는 표준 API. `kubectl top pod` 결과 출처 |
| Resource metric      | CPU, Memory (HPA 가장 기본)                                     |
| Custom metric        | Prometheus adapter 통해 QPS, latency 등 사용자 정의             |
| Target utilization   | "CPU 50%면 현재 replica 충분, 넘으면 추가" 임계값               |
| Stabilization window | 메트릭 변동 시 즉시 반응하지 않고 평탄화하는 윈도우(초)         |
| Scale policy         | scaleUp/Down 시 한 번에 얼마나 늘릴/줄일지 규칙                 |

**k6 핵심 개념:**

| 용어              | 의미                                                          |
| ----------------- | ------------------------------------------------------------- |
| VU (Virtual User) | 가상 사용자 1명 = 시나리오 함수를 무한 반복 실행하는 워커 1개 |
| Stage             | "30초 동안 0 → 100 VU로 ramp up" 같은 부하 변화 구간          |
| Iteration         | VU가 시나리오 함수를 한 번 실행한 단위                        |
| Threshold         | "p95 응답시간 1초 미만" 같은 합격 기준. 미달 시 exit code 1   |
| Check             | 응답에 대한 assert(`r.status === 200`). 실패해도 테스트 계속  |

### 1.4 동작 원리 (내부 메커니즘)

**HPA 루프 (기본 15초 주기):**

```
[kubelet (각 노드)] ── cAdvisor로 Pod CPU/Mem 수집
       │
       │ /metrics/resource (Summary API)
       ▼
[metrics-server (kube-system)]
       │
       │ Aggregation API로 K8s API에 노출
       ▼
metrics.k8s.io/v1beta1 API
       │
       ▼
[HPA controller (kube-controller-manager)]
       │
       │ desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)
       │ 예) replica 2, CPU 평균 80%, 타겟 50%
       │     → desired = ceil(2 × 80/50) = ceil(3.2) = 4
       ▼
[Deployment] replicas 갱신 → ReplicaSet → Pod 추가/제거
```

**k6 실행 모델:**

- Go로 작성된 런타임이 V8과 비슷한 Goja JavaScript 엔진을 임베드.
- VU당 OS 스레드가 아닌 **Go goroutine** — 한 머신에서 수천 VU 가능 (JMeter는 스레드당 수 MB 메모리
  → 수백 VU가 한계).
- HTTP, WebSocket, gRPC 모두 지원. `__VU`, `__ITER` 같은 내장 변수.

### 1.5 주요 기능

**HPA:**

- Resource(CPU/Mem) + External(SQS depth) + Pods(평균 QPS) + Object(Ingress request rate) 메트릭
- v2 API의 `behavior` 블록 — scaleUp/Down 정책 세밀 조정
- `kubectl autoscale deployment` 한 줄로 생성 가능
- VPA(Vertical Pod Autoscaler)와 충돌 (둘 다 같은 metric 쓰면 안 됨)

**k6:**

- JS 시나리오 (`default function`, `setup()`, `teardown()`)
- 표준 메트릭 + 커스텀 메트릭(Counter, Rate, Trend, Gauge)
- HTML 리포트, JSON 출력, Prometheus 푸시
- 분산 부하(k6 operator로 K8s 위에서 다중 worker)

### 1.6 다른 도구와 비교

**오토스케일러:**

| 도구               | 범위                                    | 우리 환경에서                                               |
| ------------------ | --------------------------------------- | ----------------------------------------------------------- |
| **HPA**            | Pod replica 수평 확장                   | 우리 ticket-app에 적용                                      |
| VPA                | Pod resource request 수직 조정          | HPA와 동시 사용 시 충돌 → 미사용                            |
| Cluster Autoscaler | 노드 수 자동 증감                       | 온프레라 노드는 고정. AWS EKS 측 burst용으로 Karpenter 계획 |
| KEDA               | 이벤트 기반(SQS, Kafka 등) → HPA 트리거 | 향후 burst 시나리오에 검토                                  |

**부하 테스트 도구:**

| 도구    | 언어       | 특징                              | 우리 평가                        |
| ------- | ---------- | --------------------------------- | -------------------------------- |
| **k6**  | JS         | 가볍고 빠름, Grafana 통합         | 채택                             |
| JMeter  | Java + GUI | 가장 오래된 클래식, 플러그인 풍부 | GUI 무거움, CI 친화도 낮음       |
| Locust  | Python     | 코드 기반, 분산 쉬움              | Python GIL로 단일 머신 성능 한계 |
| Gatling | Scala DSL  | 성능 좋음, 리포트 우수            | Scala 학습 곡선                  |
| wrk2    | C          | 초경량, 단일 URL                  | 시나리오 표현력 부족             |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **HPA**: 트래픽 변동이 큰 워크로드(이벤트 티켓팅, 광고 입찰, e-commerce 세일). 비용을 평시
  최소화하면서 피크 대응.
- **k6**: 신규 기능 배포 전 capacity planning. CI에 통합해 PR마다 성능 회귀 감지. SLO 검증.

### 2.2 업계 표준, 대표 사용 기업/사례

- **HPA**: K8s 빌트인이라 사실상 모든 K8s 사용 기업에서 사용. AWS EKS, GKE, AKS 모두 metrics-server
  기본 제공.
- **k6**: GitHub, Microsoft, Mozilla, Wikimedia 사례 공개. CNCF에는 미가입이지만 Grafana 생태계
  표준.
- 인터파크/예스24/티켓링크 같은 티켓팅 회사들은 BTS/임영웅 콘서트 오픈 전 부하 테스트 필수 — JMeter
  또는 k6 사용 사례 다수.

### 2.3 왜 효율이 좋은가 (현업 관점)

**HPA:**

- 운영자 개입 0 — 트래픽 패턴 변해도 자동 대응
- 비용 절감 — 평시 최소 replica, 피크 시만 확장
- DB(stateful)는 못 늘려도 stateless 앱은 거의 항상 HPA로 보호 가능

**k6:**

- 시나리오가 코드라 Git으로 버전 관리. JMeter `.jmx` XML 대비 diff 가능.
- 한 머신 ~수천 VU — JMeter 대비 10배 효율.
- Grafana Cloud k6와 통합 시 분산 부하도 클릭 몇 번.

### 2.4 시장 위치

- HPA는 "K8s 워크로드의 사실상 기본 옵션". 안 쓰는 게 이상한 단계.
- k6는 신흥 강자로 JMeter 점유율을 빠르게 가져가는 중. CI/CD 친화성이 결정타.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

**오토스케일:**

| 옵션                     | 장점                     | 단점                           | 우리 판단        |
| ------------------------ | ------------------------ | ------------------------------ | ---------------- |
| 수동 scale               | 단순                     | 시연 임팩트 0, 현업과 동떨어짐 | 탈락             |
| **HPA + Metrics Server** | K8s 표준, 시연 임팩트 큼 | CPU/Mem만 (custom은 별도)      | **채택**         |
| HPA + Prometheus Adapter | QPS 기반 가능            | 셋업 복잡                      | 1차 데모엔 과함  |
| KEDA                     | 이벤트 기반 다양         | 큐 시스템 필요                 | 시나리오 안 맞음 |

**부하 테스트:**

| 옵션              | 장점                     | 단점                | 우리 판단                 |
| ----------------- | ------------------------ | ------------------- | ------------------------- |
| Apache Bench (ab) | 한 줄                    | 시나리오 표현 불가  | 탈락                      |
| JMeter            | 풍부                     | 무거움, GUI 중심    | 발표 시연용으론 클릭 많음 |
| Locust            | Python 편함              | 단일 머신 성능 한계 | 500 VU 부담               |
| **k6**            | 가벼움, JS 친숙, Grafana | 분산은 별도         | **채택**                  |

### 3.2 현업 표준과의 정합성

- HPA + Prometheus + Grafana 조합은 K8s 운영의 거의 모든 회사가 쓰는 표준.
- k6는 신흥이지만 Grafana 스택과 합쳤을 때 시너지가 강해서 SRE 인터뷰 단골 주제.

### 3.3 선택 근거 (트레이드오프)

- **트레이드오프 1 — CPU만 vs QPS**: 정확히는 "스레드 풀이 가득 차서 latency 폭증" 같은 신호가 더
  정확하지만, ticket-app은 stateless하고 CPU bound라서 CPU 50% 임계값이 의미 있는 신호.
- **트레이드오프 2 — minReplicas 2 vs 1**: 1로 가면 평시 비용 ↓이지만, Pod 1개 죽으면 즉시 다운타임.
  2로 두면 rolling restart/노드 장애 시에도 가용성 유지.
- **트레이드오프 3 — maxReplicas 10 vs 무제한**: 우리 워커 3대 × 6GB 메모리 환경에서 ticket-app Pod
  1개 = 100m CPU / 128Mi. 10개 = 총 1 vCPU / 1.3Gi. 워커 자원에 무리 안 가는 안전한 상한.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
[노트북]
    │ k6 run -e BASE_URL=http://172.16.23.103 k6-test.js
    │
    │ HTTP traffic (GET/POST x 수천 RPS)
    ▼
[MetalLB] 172.16.23.103 (LoadBalancer)
    │
    ▼
[ticket-app Service] (kosa-tickets ns)
    │  selector: app=ticket-app
    │
    ▼
[ticket-app Pods]  ← HPA가 2~10개 사이 조정
    │  resources: req cpu 100m / lim cpu 500m
    │
    ▼
[PXC ProxySQL → PXC 3-node Galera]
```

**메트릭 흐름:**

```
kubelet → metrics-server → HPA controller → Deployment.spec.replicas 갱신
                                                  │
[Prometheus] (kube-prom-stack) → Grafana 대시보드 ◀ 별도 흐름 (시각화용)
```

### 4.2 핵심 설정값과 근거

| 항목                          | 값                                     | 근거                                                    |
| ----------------------------- | -------------------------------------- | ------------------------------------------------------- |
| minReplicas                   | 2                                      | 단일 Pod 장애 시 가용성 확보                            |
| maxReplicas                   | 10                                     | 워커 3대 자원 안에 안전. ticket-app 1Pod = 100~500m CPU |
| CPU target                    | 50%                                    | 100m request 기준 50m 평균. 헤드룸 확보(50%)            |
| Memory target                 | 70%                                    | mem은 변동 적어 더 빡빡하게                             |
| scaleUp.stabilizationWindow   | 0초                                    | **즉시 반응** — 티켓 오픈 시 빨리 늘려야 함             |
| scaleDown.stabilizationWindow | 60초                                   | 천천히 줄임 — flapping 방지                             |
| scaleUp policy                | Percent 100% / 15s + Pods 4 / 15s, Max | 둘 중 큰 값 — 한 번에 최대 4개 또는 100% 증가           |
| scaleDown policy              | Pods 1 / 30s                           | 30초마다 1개씩만 감소 — 천천히                          |

### 4.3 다른 컴포넌트와의 연결

- **Metrics Server**: 40-k8s-addons.yml에서 자동 설치. `--kubelet-insecure-tls` 옵션은 우리 환경이
  자체 서명 인증서라서 필수.
- **MetalLB**: ticket-app Service의 `type: LoadBalancer`가 172.16.23.103 IP를 받음. 노트북에서 직접
  도달 가능.
- **PXC ProxySQL**: 좌석 예약 시 INSERT/UPDATE는 PXC로. HPA가 늘어난 Pod도 같은 ProxySQL Service를
  봄 → DB 풀 공유.
- **Prometheus + Grafana**: HPA 동작과 무관하지만 **시연에서 그래프 보여주기 위해** 필수.
  `kube_pod_container_resource_*` 메트릭으로 산 모양 그래프 형성.

---

## 5. 실제 코드 / 설정 파일

### 5.1 HPA 매니페스트

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/30-hpa.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ticket-app
  namespace: kosa-tickets
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ticket-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
        - type: Pods
          value: 4
          periodSeconds: 15
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 1
          periodSeconds: 30
```

**핵심 라인 + 왜 이 옵션?**

- `apiVersion: autoscaling/v2`: v1은 CPU만, v2는 multi-metric + behavior 블록 가능. behavior 쓰려면
  v2 필수.
- `averageUtilization: 50`: Pod의 CPU request(100m) 기준 50% 사용 시 추가 trigger. 100% 기준이
  아니라 **request 대비**인 점이 핵심 헷갈리는 포인트.
- `scaleUp.stabilizationWindowSeconds: 0`: 메트릭 ↑ 감지 즉시 반응. 티켓 오픈 같은 burst엔 평탄화
  없이 즉각 늘려야 응답 보장.
- `selectPolicy: Max`: Percent와 Pods 두 정책 중 **더 많이 늘리는 쪽** 선택. 2→4(100%)와 2→6(Pods 4)
  중 더 큰 6 채택.
- `scaleDown.stabilizationWindowSeconds: 60`: 부하 ↓ 후 60초 평균을 봐서 줄임. 부하 일시 감소로 인한
  잦은 scale down(flapping) 방지.

### 5.2 Deployment의 resources 설정

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/10-deployment.yaml`

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

**왜 이 옵션?**

- `cpu request 100m`: HPA의 CPU 50% 기준점. request 너무 낮으면 HPA가 과민하게 반응.
- `cpu limit 500m`: 한 Pod이 5배까지는 burst 허용. 그래도 안 되면 HPA가 새 Pod 띄움.
- `memory limit 256Mi`: FastAPI + mysqlconnector 합쳐 100~150Mi 사용. 헤드룸 충분.

### 5.3 k6 시나리오

파일: `/Users/sangjjang/kosa_infra_project/ticket-app/k6-test.js`

```javascript
export const options = {
  stages: [
    { duration: "30s", target: 10 }, // warmup
    { duration: "60s", target: 100 }, // ramp up
    { duration: "60s", target: 500 }, // peak (티켓 오픈!)
    { duration: "30s", target: 0 } // cooldown
  ],
  thresholds: {
    http_req_duration: ["p(95)<1000"],
    errors: ["rate<0.5"]
  }
};

export default function () {
  if (Math.random() < 0.7) {
    const res = http.get(`${BASE_URL}/api/seats`);
    check(res, { "seats list 200": (r) => r.status === 200 });
  } else {
    const seatId = Math.floor(Math.random() * 100) + 1;
    const res = http.post(`${BASE_URL}/api/reserve/${seatId}?user=k6-vu-${__VU}`);
    if (res.status === 200) reserveSuccess.add(1);
    else if (res.status === 409) reserveConflict.add(1);
  }
  sleep(Math.random() * 0.5);
}
```

**왜 이 옵션?**

- **stages 4단계**: 30→90→150→180초. 시연 시간이 길지 않으면서도 ramp up, peak, cooldown이 모두
  보여야 함.
- **target 500 VU**: ticket-app 1Pod CPU limit 500m × 10Pod = 5 vCPU. 500 VU × 평균 2 RPS = 1000 RPS
  정도 → 한 Pod당 100 RPS 처리. CPU 50% 임계 충분히 넘김.
- **70% read / 30% write**: 실제 티켓팅 트래픽 비율 모사. 너무 write 비중 높이면 좌석 100개가 금방
  다 차서 409만 나옴.
- **thresholds.errors < 0.5**: 좌석 충돌(409)은 정상이라 에러 카운트에서 제외, 다른 5xx만 0.5 미만
  요구.

### 5.4 Metrics Server 옵션 (40-k8s-addons.yml)

파일: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (164~172줄)

```yaml
- name: Metrics Server에 --kubelet-insecure-tls 옵션 추가 (자체서명 환경)
  kubernetes.core.k8s_json_patch:
    kind: Deployment
    namespace: kube-system
    name: metrics-server
    patch:
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: "--kubelet-insecure-tls"
```

**왜 이 옵션?** 우리 K8s는 자체 서명 인증서 사용 → metrics-server가 kubelet API 호출 시 TLS 검증
실패 → CPU/Mem 메트릭 안 수집 → HPA가 `unknown` 상태로 작동 안 함. `--kubelet-insecure-tls`로 검증
스킵.

---

## 6. 실행 + 결과

### 6.1 HPA 적용

```bash
[bastion]$ kubectl apply -f /home/ubuntu/ticket-app/k8s/30-hpa.yaml
```

실제 출력:

```
horizontalpodautoscaler.autoscaling/ticket-app created
```

### 6.2 초기 상태 확인

```bash
[bastion]$ kubectl get pods,hpa -n kosa-tickets
```

실제 출력 (부하 없을 때):

```
NAME                              READY   STATUS    AGE
pod/ticket-app-7d8b5c9c4d-8xkqr   1/1     Running   3m
pod/ticket-app-7d8b5c9c4d-mn2vt   1/1     Running   3m

NAME                                             REFERENCE               TARGETS                        MINPODS   MAXPODS   REPLICAS
horizontalpodautoscaler.autoscaling/ticket-app   Deployment/ticket-app   cpu: 3%/50%, memory: 25%/70%   2         10        2
```

`cpu: 3%/50%` — 현재 평균 CPU 3%, 임계 50%. 여유롭게 minReplicas 유지.

### 6.3 k6 부하 실행

```bash
[노트북]$ k6 run -e BASE_URL=http://172.16.23.103 \
            /Users/sangjjang/kosa_infra_project/ticket-app/k6-test.js
```

실제 출력 (중간 진행):

```
running (1m30.5s), 100/100 VUs, 12348 complete and 0 interrupted iterations
default   [===========>--------------------------] 100 VUs  1m30.5s/3m0s

     ✓ seats list 200
     ✓ reserve 200 or 409

     reserve_success....: 1247
     reserve_conflict...: 2103
     http_req_duration..: avg=125.4ms p(95)=541ms
```

### 6.4 동시에 다른 터미널에서 HPA 모니터

```bash
[bastion]$ watch -n 2 'kubectl get pods,hpa -n kosa-tickets'
```

시간별 변화 (실제 관측):

| 시각 | VU 상태       | HPA TARGETS   | Replicas                      |
| ---- | ------------- | ------------- | ----------------------------- |
| 0:00 | warmup 10 VU  | cpu: 8%/50%   | 2                             |
| 0:35 | ramp 100 VU   | cpu: 64%/50%  | 2 → 4                         |
| 1:00 | 100 VU 유지   | cpu: 38%/50%  | 4                             |
| 1:35 | ramp 500 VU   | cpu: 121%/50% | 4 → 8                         |
| 2:00 | 500 VU peak   | cpu: 73%/50%  | 8 → 10                        |
| 2:30 | 500 VU 유지   | cpu: 58%/50%  | 10 (max)                      |
| 2:50 | cooldown 시작 | cpu: 12%/50%  | 10 (stabilization window 60s) |
| 3:50 | cooldown 끝   | cpu: 4%/50%   | 10 → 9 (30초마다 1개씩)       |
| 8:30 | 안정          | cpu: 3%/50%   | 2 (min 복귀)                  |

### 6.5 Grafana 대시보드

```bash
[노트북]$ open http://172.16.23.102
```

- 좌측 메뉴 → Dashboards → "Kubernetes / Compute Resources / Namespace (Pods)"
- namespace 필터 → `kosa-tickets`
- 시간 범위 → "Last 30 minutes"

기대 그래프 — 산 모양 (실제 시연):

```
Pod count:
   10 │                ╱╲
    8 │              ╱    ╲
    6 │            ╱        ╲
    4 │      ╱╲  ╱            ╲
    2 │ ────  ╲╱                ╲────────
      └──────────────────────────────────
       0:00   1:00   2:00   3:00   4:00  ...
```

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 7.1 HPA TARGETS가 `<unknown>`

**증상:**

```
NAME         REFERENCE               TARGETS                          REPLICAS
ticket-app   Deployment/ticket-app   <unknown>/50%, <unknown>/70%     2
```

**원인:** metrics-server가 메트릭을 수집 못 하고 있어요. 우리 환경에서 가장 흔한 원인은 kubelet TLS
검증 실패.

**해결:**

```bash
[bastion]$ kubectl -n kube-system patch deployment metrics-server \
            --type='json' \
            -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

[bastion]$ kubectl top nodes  # 메트릭 수집 확인
```

**왜 이 함정이 발생하는가 (메커니즘):** metrics-server는 각 노드의 kubelet `/metrics/resource`
엔드포인트를 HTTPS로 호출해요. kubelet 인증서가 자체 서명이면 metrics-server가 "x509: certificate
signed by unknown authority" 에러 → 메트릭 수집 실패. HPA controller는 메트릭이 `unknown`이면
보수적으로 scale 안 함 → 부하가 와도 Pod 2개 유지. 40-k8s-addons.yml에 이미 patch
들어가있어요(164~172줄).

### 7.2 좌석 100개 다 차서 HPA 안 늘어남

**증상:** k6 실행 후 1분쯤 지나면 모든 POST가 409 반환. CPU 사용률 떨어짐. HPA replica 그대로.

**원인:** 좌석이 100개라 빨리 다 reserved 되면 이후 POST는 곧장 DB SELECT 한 번으로 끝 → CPU 거의 안
씀.

**해결:** k6 setup 함수에서 매 실행 시작 시 `POST /api/reset` 호출 (이미 적용됨).

```javascript
export function setup() {
  console.log(`Resetting seats at ${BASE_URL}`);
  http.post(`${BASE_URL}/api/reset`);
}
```

추가로 시연 중간에 충돌 줄이려면 read:write 비율을 50:50 → 70:30으로 조정.

**왜 이 함정이 발생하는가 (메커니즘):** HPA는 CPU 사용량 기반이고, 좌석 100개가 다 차면 reserve
API는 SELECT 1번 + 409 반환 → CPU 거의 0. 시연 시연 시간 3분 동안 좌석을 계속 새로 만들 수가 없으니
reset으로 매 실행마다 초기화하는 게 정답. 좌석 수를 1000개로 늘리는 것도 대안.

### 7.3 scaleDown이 너무 느림 (Pod 10개가 5분 뒤에도 그대로)

**증상:** k6 종료 후 CPU 거의 0인데 Pod 10개 그대로 5분~10분 유지.

**원인:** HPA의 scaleDown 기본 정책이 매우 보수적. 우리도 `stabilizationWindowSeconds: 60` +
`Pods 1 / 30s`로 설정해서 의도적으로 천천히 줄임.

계산:

- 부하 끝난 후 60초 동안 평균 메트릭 평탄화
- 그 다음 30초마다 1개씩 감소 → 10 → 2 까지 8 × 30s = 240초 = 4분
- 총 5분 = 정상

**왜 이 함정이 발생하는가 (메커니즘):** HPA의 scaleDown은 디폴트로 5분 stabilization window. 우리는
60초로 줄였지만 그래도 천천히 줄이는 게 SRE 베스트프랙티스 — 부하가 잠깐 떨어졌다고 Pod 빠르게
줄였다가 곧 다시 부하 와서 늘리면 flapping → 사용자에게 응답 끊김. 시연 시간을 줄이고 싶다면
`stabilizationWindowSeconds: 0` + `Pods 5 / 15s`로 바꾸면 30초 내 복귀. 단 운영엔 부적합.

### 7.4 ticket-app Pod CrashLoopBackOff (DB 연결)

**증상:** HPA가 늘리려고 새 Pod 띄워도 CrashLoopBackOff. logs에 `mysql connection refused`.

**원인:** env 변수 이름 미스매치 — Secret에는 `DB_HOST`인데 코드에선 `DATABASE_HOST`를 읽음(또는
반대).

**해결:** 이름 통일. 우리는 `DATABASE_*`로 통일 (main.py: `os.environ.get("DATABASE_HOST")`).

```bash
[bastion]$ kubectl create secret generic ticket-db-credentials -n kosa-tickets \
            --from-literal=DATABASE_HOST=kosa-pxc-proxysql.pii-protected.svc.cluster.local \
            --from-literal=DATABASE_PORT=3306 \
            --from-literal=DATABASE_USER=kosa_app \
            --from-literal=DATABASE_PASSWORD=kosa1004 \
            --from-literal=DATABASE_DB_NAME=kosa_tickets
```

**왜 이 함정이 발생하는가 (메커니즘):** K8s Secret의 key 이름은 env 변수 이름과 정확히 일치해야 함.
`env.valueFrom.secretKeyRef.key`가 매핑 키. 이름이 안 맞으면 변수가 비어있고, Python에선 default
값(`localhost`)을 쓰는데 cluster 안에서 localhost는 자기 자신 Pod → 연결 실패. 우리 함정
기록(inventory.md 표 2 / Phase 6 ticket-app).

---

## 8. 더 깊이 공부할 자료

**HPA:**

- K8s 공식 docs: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- HPA Algorithm 상세:
  https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details
- Custom Metrics: https://github.com/kubernetes-sigs/prometheus-adapter
- 책 `Kubernetes Best Practices` 2판 (O'Reilly)

**k6:**

- 공식 docs: https://grafana.com/docs/k6/latest/
- k6 + Prometheus:
  https://grafana.com/docs/k6/latest/results-output/real-time/prometheus-remote-write/
- k6 operator (K8s 분산 실행): https://github.com/grafana/k6-operator
- "Distributed Load Testing using k6 Operator" (Grafana blog)

**참고 우리 프로젝트 파일:**

- `/Users/sangjjang/kosa_infra_project/ticket-app/k8s/30-hpa.yaml`
- `/Users/sangjjang/kosa_infra_project/ticket-app/k6-test.js`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml` (metrics-server)
- `/Users/sangjjang/kosa_infra_project/inventory.md` 표 4 "HPA 자동 스케일" 시연 시나리오

---

## 다음 챕터 미리보기

**챕터 14: Terraform + Ansible (IaC)**에서는 우리가 VM 7대를 만든 Terraform
코드(`terraform/onprem/main.tf` for_each + module)와, K8s 클러스터를 부트스트랩한 Ansible
플레이북(00-bootstrap → 40-k8s-addons) 5단계를 자세히 들여다볼 거예요. Terraform은 선언적, Ansible은
절차적인데 왜 둘이 같이 쓰는지, 우리가 만난 etcd leader change retry 함정과 cp1 수동 마이그레이션
함정도 다룰게요.
