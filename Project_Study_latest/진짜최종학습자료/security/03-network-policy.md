# 03. NetworkPolicy — K8s Zero-Trust

> ⭐ **한 줄 요약**: **ticket-app과 admin-app 두 namespace에 zero-trust NetworkPolicy 적용**해 default deny + 명시적 allow 패턴을 구현. Calico CNI가 강제한다. ticket-app은 PXC/Redis/DNS/monitoring만 허용 (운영 보호), admin-app은 RDS만 허용 (OLAP 격리). 다른 namespace는 아직 default permit이라 Phase 6에서 확장 계획.

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

### admin namespace 격리 (OLAP/OLTP 분리 강제) ⭐ 신규

`admin-app`은 OLAP 분석 전용이라 **운영 DB(PXC)와 캐시(Redis)는 완전 차단**, **분석 DB(RDS Replica)만 허용**해야 한다. 3개 정책으로 구현.

```yaml
# 1) 기본: 모든 egress 차단 (default-deny)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: admin-default-deny-egress
  namespace: admin
spec:
  podSelector: {}
  policyTypes:
    - Egress

# 2) DNS만 추가 허용 (필수, 안 그러면 hostname resolve 실패)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: admin-allow-dns
  namespace: admin
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP

# 3) admin-app만 RDS (10.20.10.54)로 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: admin-allow-rds
  namespace: admin
spec:
  podSelector:
    matchLabels:
      app: admin-app
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 10.20.10.54/32
      ports:
        - port: 3306
          protocol: TCP
```

3개 정책 (default-deny + DNS + RDS-only)이 OR 조합으로 동작 — admin namespace pod은 DNS와 RDS만 허용된다. PXC, Redis, 외부 인터넷 모두 차단.

### 적용 안 된 namespace (default permit)

여전히 적용 안 된 부분도 있다. 우선순위가 낮은 system namespace들.

- monitoring (Grafana 등은 다양한 data source 봄 → 신중)
- harbor
- jenkins
- argocd
- cert-manager
- 등등

추후 zero-trust를 모든 ns로 확장하는 게 Phase 6 작업이다. 이미 적용된 곳은:
- ✅ `kosa-tickets` — ticket-app strict egress (DNS/PXC/Redis/monitoring만)
- ✅ `admin` — admin-app strict egress (DNS/RDS만, OLAP 격리 강제)
- ⏳ 나머지 7개 ns — 미적용

---

## ✅ 검증 결과 (2026-05-23 실측)

NetworkPolicy 적용 후 Python socket으로 직접 도달 시험. **격리가 진짜 동작하는지 입증**한 데이터.

### admin namespace — admin-app

```python
# admin-app Pod 안에서 socket connect 시험
targets = [
    ('10.20.10.54',  3306, 'RDS         (허용되어야)'),
    ('172.16.23.56', 6033, 'PXC ProxySQL (차단되어야)'),
    ('172.16.23.59', 6379, 'Redis       (차단되어야)'),
]
```

결과:
```
RDS         : ✅ CONNECTED (10.20.10.54:3306)
PXC ProxySQL: ❌ BLOCKED (172.16.23.56:6033) - TimeoutError
Redis       : ❌ BLOCKED (172.16.23.59:6379) - TimeoutError

healthz: {"status":"ok","db":"ok","_cluster":"onprem","_db_host":"10.20.10.54"}
DNS: kubernetes.default.svc → 10.96.0.1 (OK)
```

→ **OLAP 분리가 NetworkPolicy 레벨에서 강제됨**. admin-app 코드에 bug나 SQL injection이 있어도 운영 DB(PXC)에 직접 접근 불가.

### kosa-tickets namespace — ticket-app

```python
targets = [
    ('172.16.23.56', 6033, 'PXC      (허용되어야)'),
    ('172.16.23.59', 6379, 'Redis    (허용되어야)'),
    ('10.20.10.54',  3306, 'RDS     (차단되어야)'),
    ('8.8.8.8',      53,   'DNS 외부 (차단되어야)'),
]
```

결과:
```
PXC      : ✅ CONNECTED (172.16.23.56:6033)
Redis    : ✅ CONNECTED (172.16.23.59:6379)
RDS     : ❌ BLOCKED (10.20.10.54:3306)
DNS 외부 : ❌ BLOCKED (8.8.8.8:53)
```

→ ticket-app은 운영 dependency (PXC + Redis)만 통신 가능. RDS도 차단 + 외부 8.8.8.8 같은 임의 outbound도 차단. **진짜 zero-trust egress**.

### 정책 1개 vs 정책 2개 — 함정

처음엔 ticket-app namespace에 `tickets-deny-rds` 정책을 별도로 추가했는데, 기존 strict한 `ticket-app-policy`와 OR 조합되면서 **외부 통신(8.8.8.8)이 풀려버렸다**. K8s NetworkPolicy의 OR 의미를 모르면 의도 약화 가능.

```
ticket-app-policy (strict): DNS/PXC/Redis/monitoring만 허용
tickets-deny-rds (광범위): 0.0.0.0/0 except RDS

OR 결과: 0.0.0.0/0 except RDS → 외부 임의 통신 가능 ⚠️
```

→ **tickets-deny-rds 정책 제거**해서 기존 strict 정책만 살림. 이후 8.8.8.8도 BLOCKED.

**교훈**: NetworkPolicy 추가 전에 기존 정책의 의도를 봐야 한다. 같은 podSelector에 여러 정책이 붙으면 더 광범위한 정책이 이긴다.

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
| **광범위 정책이 strict 정책 옆에 추가됨** | OR 조합으로 strict 의도 약화 | 광범위 정책 제거 또는 strict하게 재작성 |
| **API VIP 일시 timeout 중 검증** | `kubectl exec` 실패로 검증 못함 | lb-1/lb-2 HAProxy + Keepalived 확인 후 재시도 |

**우리가 실제 만난 함정 2가지**:

**1. Silent fail — OpenTelemetry Tempo egress 누락**: ticket-app에 OTel auto-instrumentation 추가하면서 Tempo로 trace를 보내려 했는데, NetworkPolicy egress 룰에 Tempo가 없어서 silent fail. trace가 안 가서 디버깅하다가 NetworkPolicy 추가로 해결. **새 의존성 추가 시 NetworkPolicy도 같이 업데이트하는 절차** 필요.

**2. 광범위 정책이 strict 정책 약화**: kosa-tickets ns에 `tickets-deny-rds`(0.0.0.0/0 except RDS) 정책을 추가했더니, 기존 `ticket-app-policy`(DNS/PXC/Redis만 strict)와 **OR 조합**으로 외부 8.8.8.8 통신이 풀려버림. NetworkPolicy의 OR semantics 잊으면 발생. 해결: `tickets-deny-rds` 제거 후 기존 strict 정책만 유지. 검증으로 8.8.8.8도 BLOCKED 확인.

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

**Q7. OLTP/OLAP 분리를 NetworkPolicy로 어떻게 강제했나요?** ⭐

A. **두 namespace에 정반대 방향의 정책**입니다. `admin` namespace는 RDS(10.20.10.54)만 egress 허용 + DNS만 추가 → PXC/Redis는 도달 불가 (timeout). `kosa-tickets` namespace는 PXC/Redis/DNS/monitoring만 명시 허용 → RDS도 자동 차단 + 외부 인터넷도 차단. 결과적으로 **admin은 분석 DB만, ticket-app은 운영 DB만** 보는 격리가 K8s 레벨에서 강제됩니다. admin-app 코드에 SQL injection이나 bug가 있어도 운영 PXC에 영향 0이 보장됩니다.

**Q8. NetworkPolicy 검증은 어떻게 하나요?**

A. **Python socket으로 직접 connect 시험**이 가장 확실합니다. nc/curl이 image에 없으면 (slim image), Python 표준 라이브러리만으로 가능합니다:
```python
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(3)
try:
    s.connect(('10.20.10.54', 3306))
    print('CONNECTED')
except (socket.timeout, OSError):
    print('BLOCKED')
```
timeout이 뜨면 차단된 것 (DNS는 풀리지만 packet drop). connection refused면 도달은 하는데 service가 안 받는 것 (정책 통과). 이 차이로 NetworkPolicy 동작을 확인할 수 있습니다. 실제 우리 환경에선 admin-app, ticket-app 둘 다 정확히 의도대로 동작 확인했습니다 (위 "검증 결과" 섹션).

**Q9. 정책 여러 개가 같은 Pod에 붙으면?** ⭐ 우리가 만난 함정

A. **OR 조합**입니다. 어느 한 정책에서 허용하면 통과. 그래서 strict 정책 옆에 광범위 정책을 추가하면 strict 의도가 약해집니다. 우리도 `tickets-deny-rds`(0.0.0.0/0 except RDS) 정책을 기존 `ticket-app-policy`(DNS/PXC/Redis만) 옆에 추가했더니, OR로 외부 8.8.8.8 같은 임의 통신이 풀려버렸습니다. 결국 `tickets-deny-rds` 제거하고 기존 strict 정책만 살리는 게 정답이었습니다. **추가 전 기존 정책의 의도를 봐야 한다**는 교훈.
