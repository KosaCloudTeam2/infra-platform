# 03. NetworkPolicy — K8s Zero-Trust

> ⭐ **한 줄 요약**: **ticket-app namespace에 zero-trust NetworkPolicy 적용** (default deny + 명시적 allow). Calico CNI가 강제. 다른 ns는 default permit (학습 시간 한계). 확장 계획 있음.

---

## 🎯 우리가 한 선택

### ticket-app NetworkPolicy
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
    - to:                                                  # DNS
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

### 적용 안 된 namespace (default permit)
- monitoring
- harbor
- jenkins
- argocd
- cert-manager
- 등등

→ 추후 zero-trust 확장 필요.

---

## 🔍 고려한 대안들

### Q1. NetworkPolicy vs Service Mesh (Istio/Linkerd)

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **NetworkPolicy (선택)** | K8s native, 가벼움, Calico 무료 | L3/L4만 (L7 HTTP/gRPC 정책 X) | ★★★★ |
| Istio AuthorizationPolicy | L7 정책 (method, path), mTLS | 매우 무거움 (sidecar) | ★★★ |
| Linkerd | 가벼운 mesh, mTLS | 우리 use case엔 과함 | ★★★ |
| Cilium (eBPF) | L3~L7 통합, 빠름 | Calico 교체 비용 | ★★★★ |

### Q2. 적용 범위 — ticket-app만 vs 모든 ns

| 대안 | 장점 | 단점 |
|---|---|---|
| **ticket-app만 (현재)** | 학습 데모 충분, 부담 ↓ | 다른 ns 무방비 |
| 모든 ns zero-trust | 진짜 zero-trust | 정책 작성 부담 ★★★ |

---

## 💡 왜 ticket-app만? (한계 인정)

### 1. ⏱️ **학습 시간 한계**
- 모든 ns에 정책 작성 = 7개 ns × ~5 룰 = 35+ 룰
- 각 ns의 의존성 분석 + 검증 필요
- 데모 우선순위 ↓

### 2. 🎯 **demo 데모 적합성**
- 비즈니스 워크로드 (PII 데이터 처리) 보호가 우선
- 시스템 ns는 운영자만 접근 (외부 노출 X)

### 3. 📚 **학습 가치**
- ticket-app 1개로 NetworkPolicy 패턴 학습
- 다른 ns 확장은 같은 패턴 반복

→ **솔직히 zero-trust 미완성. Phase 6에서 확장 권장**.

---

## 💰 비용 분석

NetworkPolicy 자체는 무료 (Calico 내장). 비용은:
- 정책 작성 시간
- 디버깅 시간 (의존성 잘못 빠뜨려서 service 죽음)

→ 운영급 zero-trust 도입 = 정책 작성/검증 1주+

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| ticket-app 격리 | 다른 ns 무방비 |
| zero-trust 패턴 학습 | 완전한 zero-trust X |
| K8s native | L7 정책 X (Service Mesh 필요) |

---

## ⚠️ SPoF + 함정

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **NetworkPolicy 잘못 작성** | service 죽음 (DNS 못 풂 등) | 정책 수정 또는 삭제 |
| **새 의존성 추가 (예: Tempo)** | egress 막혀서 trace 안 감 | egress 룰 추가 (우리 경험) |
| **Calico 죽음** | 정책 무력화 (보안 위험) | Calico 회복 |
| **namespaceSelector label 안 맞음** | 룰이 적용 안 됨 | namespace label 확인 |

---

## 🚀 확장 가능성

### Option A: ⭐ 모든 namespace zero-trust 확장
- ✅ **장점**: 진짜 zero-trust
- ❌ **단점**: 정책 작성 ★★★★, 디버깅 어려움
- ⏱️ **작업**: 1~2주 (각 ns 의존성 분석 + 정책 + 검증)
- 🎯 **추천 시점**: 진짜 운영 + 컴플라이언스

### Option B: Istio/Linkerd 도입 (L7 정책 + mTLS)
- ✅ **장점**: L7 HTTP method/path, mTLS 자동
- ❌ **단점**: sidecar 무거움
- 🎯 **추천 시점**: 마이크로서비스 10+

### Option C: Cilium (eBPF, L3~L7 통합)
- ✅ **장점**: Calico 대체 + 성능, L7 CiliumNetworkPolicy
- ❌ **단점**: Calico 교체 ★★★★
- 🎯 **추천 시점**: 진짜 cloud-native

### Option D: OPA/Gatekeeper (정책 강제)
- ✅ **장점**: NetworkPolicy 강제 (없으면 admission 거부)
- 🎯 **추천 시점**: 다중 팀 환경

### Option E: Calico GlobalNetworkPolicy
- ✅ **장점**: cluster-wide 정책 (모든 ns 기본 deny)
- 🎯 **추천 시점**: 빠른 zero-trust 시작점

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 운영 진입 | A or E (default deny cluster-wide) |
| L7 정책 필요 | B or C |
| 정책 강제 | D |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 | Calico CNI 의존 |
| 💾 데이터 | ticket-app egress → PXC, Redis |
| 🔧 CI/CD | (해당 적음) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. zero-trust인데 왜 ticket-app만?**
A. 학습 시간 한계 + demo 우선순위. 비즈니스 워크로드 (PII 데이터) 우선 보호. Phase 6에서 모든 ns 확장 권장.

**Q2. NetworkPolicy default가 뭐?**
A. K8s default = **allow all** (정책 없으면 모든 Pod 통신 가능). 정책 적용 시점부터 default deny (해당 Pod에 한해). 그래서 "policyTypes: Ingress, Egress" 명시 + ingress/egress 룰 작성.

**Q3. NetworkPolicy 의존성 빠뜨리면?**
A. service 죽음. 예: ticket-app이 Tempo로 trace 보내야 하는데 egress 룰 없으면 trace 안 감 (silent fail). 진단: Pod 로그 + tcpdump.

**Q4. Calico 죽으면 보안 위험?**
A. NetworkPolicy 무력화 → 모든 Pod 통신 가능. Calico HA (DaemonSet) + 모니터링으로 빠른 복구. Cilium도 같은 약점.

**Q5. Service Mesh 안 도입한 이유?**
A. (1) 마이크로서비스 1개 (ticket-app), (2) sidecar 무거움, (3) 학습 곡선. 마이크로서비스 늘면 Istio/Linkerd 검토.

**Q6. L7 정책 필요 케이스?**
A. "ticket-app은 PXC에 SELECT만 허용, INSERT/UPDATE는 admin만" 같은 application-level 정책. NetworkPolicy로는 port만 (3306 OK/NG), method 제어 X.
