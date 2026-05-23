# 03. NetworkPolicy — K8s Zero-Trust

> ⭐ **한 줄 요약**: **ticket-app namespace에 zero-trust NetworkPolicy를 적용**해 default deny + 명시적 allow 패턴을 구현했다. Calico CNI가 강제한다. 다른 namespace는 아직 default permit 상태로, **솔직히 zero-trust가 미완성**이라 Phase 6에서 확장 계획이다.

---

## 🎯 우리가 한 선택

ticket-app이 PII 데이터를 다루는 워크로드라 가장 먼저 격리했다. ticket-app Pod이 외부에서 들어올 수 있는 통신과 외부로 나갈 수 있는 통신을 모두 명시적으로만 허용한다.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ticket-app-policy
  namespace: kosa-tickets
spec:
  podSelector:
    matchLabels:
      app: ticket-app
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-haproxy   # Ingress만 허용
      ports:
      - protocol: TCP
        port: 8080
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: pii-protected     # PXC
      ports:
      - protocol: TCP
        port: 3306
    - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: redis             # Redis
      ports:
      - protocol: TCP
        port: 6379
    - to:                                                  # DNS (필수)
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
      ports:
      - protocol: UDP
        port: 53
    - to:                                                  # Tempo (OTel)
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
        podSelector:
          matchLabels:
            app.kubernetes.io/name: tempo
      ports:
      - protocol: TCP
        port: 4318
```

이 정책 한 개로 ticket-app은 (1) Ingress controller만 받고, (2) PXC/Redis/DNS/Tempo만 호출 가능하다. 다른 모든 통신은 차단.

### 적용 안 된 namespace (default permit)

**솔직히 부족한 부분**이다. ticket-app만 적용했고 나머지는 default permit 상태다.
- monitoring
- harbor
- jenkins
- argocd
- cert-manager
- 등등

추후 zero-trust를 모든 ns로 확장하는 게 Phase 6 작업이다.

---

## 🔍 고려한 대안

### NetworkPolicy vs Service Mesh (Istio/Linkerd)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **NetworkPolicy (선택)** | K8s native, 가벼움, Calico 무료 | L3/L4만 (L7 HTTP/gRPC 정책 X) | ★★★★ |
| Istio AuthorizationPolicy | L7 정책 (method, path), mTLS | 매우 무거움 (sidecar) | ★★★ |
| Linkerd | 가벼운 mesh, mTLS | 우리 use case엔 과함 | ★★★ |
| Cilium (eBPF) | L3~L7 통합, 빠름 | Calico 교체 비용 | ★★★★ |

K8s NetworkPolicy는 **L3/L4 (IP + Port) 단위**의 정책만 가능하다. "ticket-app은 PXC의 3306 포트만 호출 가능"은 표현 가능하지만, "ticket-app은 PXC에 SELECT만 가능, INSERT/UPDATE는 admin만"같은 L7 정책은 못 한다.

Service Mesh (Istio AuthorizationPolicy)면 L7 정책이 가능하지만 sidecar 패턴이 모든 Pod에 추가돼서 매우 무겁다. 우리 마이크로서비스 1개 (ticket-app) 환경엔 과한 도입이다.

### 적용 범위 — ticket-app만 vs 모든 ns

| 대안 | 장점 | 단점 |
|---|---|---|
| **ticket-app만 (현재)** | 학습 데모 충분, 부담 ↓ | 다른 ns 무방비 |
| 모든 ns zero-trust | 진짜 zero-trust | 정책 작성 부담 ★★★ |

**솔직한 trade-off**다. 모든 ns에 정책 작성 = 7개 ns × ~5 룰 = 35+ 룰. 각 ns의 의존성을 분석하고 검증해야 한다. 학습 시간 한계로 우선 ticket-app만 적용했다. Phase 6에서 확장 계획.

---

## 💡 왜 ticket-app만? — 한계 인정

### 1. 학습 시간 한계

모든 ns에 NetworkPolicy를 작성하려면 (1) 각 ns의 모든 Pod 간 의존성 분석, (2) 정책 작성, (3) 검증 (잘못 빠뜨려서 service 죽음 위험)이 필요하다. 학습 시간 우선순위로 보면 ticket-app 1개로 패턴 학습 + 데모는 충분하다.

### 2. demo 데모 적합성

ticket-app은 PII 데이터를 다루는 비즈니스 워크로드라 보호가 가장 critical하다. 시스템 ns (monitoring, jenkins, argocd 등)는 운영자만 접근하고 외부 노출이 적어 우선순위가 ↓이다.

### 3. 학습 가치 ★★★

ticket-app 1개로 NetworkPolicy 패턴 (default deny, ingress/egress, namespaceSelector, podSelector 등)을 완전히 익혔다. 다른 ns 확장은 같은 패턴 반복이라 추가 학습 가치가 적다.

→ **솔직히 zero-trust 미완성이고, Phase 6에서 확장하는 게 운영급 진입의 필수 작업**이다.

---

## 💰 비용 분석

NetworkPolicy 자체는 무료다 (Calico 내장). 비용은 다음에서 발생한다:
- **정책 작성 시간** — 각 ns 의존성 분석 + 정책 + 검증
- **디버깅 시간** — 의존성을 잘못 빠뜨려서 service 죽으면 추적

→ 운영급 zero-trust 도입 = 정책 작성/검증 1주+ 예상.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| ticket-app 격리 | 다른 ns 무방비 |
| zero-trust 패턴 학습 | 완전한 zero-trust X |
| K8s native | L7 정책 X (Service Mesh 필요) |

가장 큰 trade-off는 **완전한 zero-trust가 아니다**는 점이다. ticket-app은 보호하지만 다른 ns는 무방비. 진짜 zero-trust면 모든 inter-pod 통신이 명시적 허용만 통과해야 한다.

---

## ⚠️ SPoF + 함정

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **NetworkPolicy 잘못 작성** | service 죽음 (DNS 못 풂 등) | 정책 수정 또는 삭제 |
| **새 의존성 추가 (예: Tempo)** | egress 막혀서 trace 안 감 | egress 룰 추가 (우리 경험) |
| **Calico 죽음** | 정책 무력화 (보안 위험) | Calico 회복 |
| **namespaceSelector label 안 맞음** | 룰이 적용 안 됨 | namespace label 확인 |

**우리가 실제 만난 함정**: ticket-app에 OpenTelemetry auto-instrumentation을 추가하면서 Tempo로 trace를 보내려 했는데, NetworkPolicy egress 룰에 Tempo가 없어서 silent fail이 됐다. trace가 안 가서 디버깅하다가 NetworkPolicy 추가로 해결.

새 의존성 추가 시 NetworkPolicy를 같이 업데이트하는 절차가 필요하다.

---

## 🚀 확장 가능성

### Option A: ⭐ 모든 namespace zero-trust 확장

진짜 zero-trust 구현. 각 ns의 의존성 분석 + 정책 작성 + 검증. 디버깅 어려움이 있지만 진짜 운영급 보안 가능.

- ⏱️ **작업**: 1~2주
- 🎯 **추천 시점**: 진짜 운영 + 컴플라이언스

### Option B: Istio/Linkerd 도입 (L7 정책 + mTLS)

L7 HTTP method/path 정책 + mTLS 자동. sidecar 무거움이 단점이지만 마이크로서비스 ↑되면 가치 ↑.

- 🎯 **추천 시점**: 마이크로서비스 10+

### Option C: Cilium (eBPF, L3~L7 통합)

Calico 대체 + 성능 + L7 CiliumNetworkPolicy. Calico 교체 ★★★★ 비용이지만 modern cloud-native 표준.

- 🎯 **추천 시점**: 진짜 cloud-native

### Option D: OPA/Gatekeeper (정책 강제)

NetworkPolicy를 admission webhook으로 강제. "NetworkPolicy 없는 ns는 deploy 거부" 같은 정책 자동화.

- 🎯 **추천 시점**: 다중 팀 환경

### Option E: Calico GlobalNetworkPolicy

cluster-wide 정책 (모든 ns 기본 deny). 빠른 zero-trust 시작점. 단점은 의존성 분석 안 하고 적용하면 service 죽음.

- 🎯 **추천 시점**: 빠른 시작점

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 운영 진입 | A or E (default deny cluster-wide) |
| L7 정책 필요 | B or C |
| 정책 강제 | D |

---

## 🔗 다른 파트와의 연결

NetworkPolicy는 Calico CNI 의존이라 `architecture/02-kubernetes-design.md`와 직결된다. 데이터 측면에선 ticket-app의 egress가 PXC/Redis로 가는 패턴이 `data-storage/05-pxc-redis.md`와 연결된다. TLS (`02-tls-self-ca-double.md`)가 application layer 보안이라면 NetworkPolicy는 network layer 보안이다 — 둘 다 zero-trust의 layer를 구성한다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. zero-trust인데 왜 ticket-app만 적용했나요?**

A. **솔직한 한계 인정입니다**. 학습 시간 + demo 우선순위 trade-off였습니다. PII 데이터를 다루는 ticket-app이 가장 critical이라 우선 적용했고, 다른 ns는 Phase 6에서 확장 계획. **약점 인지 + 개선 계획**이 면접 어필 패턴입니다.

**Q2. NetworkPolicy의 default는 뭔가요?**

A. **K8s default = allow all** (정책 없으면 모든 Pod 통신 가능)입니다. 정책 적용 시점부터 default deny가 됩니다 (해당 Pod에 한해). 그래서 `policyTypes: Ingress, Egress` 명시 + 명시적 allow 룰 작성이 필요합니다.

**Q3. NetworkPolicy 의존성을 빠뜨리면 어떻게 되나요?**

A. **service 죽음**입니다. 예: ticket-app이 Tempo로 trace 보내야 하는데 egress 룰 없으면 silent fail (trace가 안 감, 에러도 안 남). 진단이 어렵습니다. 우리가 실제 만난 함정이고, 새 의존성 추가 시 NetworkPolicy 업데이트 절차를 명문화해야 합니다.

**Q4. Calico 죽으면 보안 위험인가요?**

A. **NetworkPolicy가 무력화**됩니다 → 모든 Pod 통신 가능. Calico HA (DaemonSet으로 모든 노드에 동작) + 모니터링으로 빠른 복구가 중요합니다. Cilium도 같은 약점이 있습니다 — 결국 CNI 자체가 critical SPoF입니다.

**Q5. Service Mesh를 안 도입한 이유는요?**

A. 세 가지 이유입니다. **마이크로서비스 1개** (ticket-app)라 mesh 가치 ↓. **sidecar 무거움** (모든 Pod에 추가). **학습 곡선 ★★★★★**. 마이크로서비스 10+로 늘면 Istio/Linkerd 검토할 가치가 있습니다.

**Q6. L7 정책이 진짜 필요한 use case는요?**

A. **"ticket-app은 PXC에 SELECT만 허용, INSERT/UPDATE는 admin만"** 같은 application-level 정책입니다. NetworkPolicy로는 port만 (3306 OK/NG), HTTP method나 SQL 명령 제어는 불가입니다. PCI/HIPAA 같은 컴플라이언스 환경에서 가치가 큽니다.
