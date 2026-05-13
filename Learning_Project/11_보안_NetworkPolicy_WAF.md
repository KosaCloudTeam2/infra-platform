# 11. 보안 — NetworkPolicy, WAF, RBAC

> Layer 5 / 학습 1일

---

## 1) 보안 계층 (Defense in Depth)

```
[인터넷]
   ↓
[AWS WAF]          ← Layer 7 공격 차단 (SQL injection, XSS)
   ↓
[pfSense]          ← Layer 3/4 방화벽 (포트, IP)
   ↓
[K8s NetworkPolicy] ← Pod 간 통신 제어
   ↓
[Pod Security]     ← Container 권한 제한
   ↓
[RBAC]             ← API 권한 (누가 무엇을)
```

한 계층 뚫려도 다른 계층이 막음.

---

## 2) K8s NetworkPolicy

### 정체

Pod 간 통신을 IP/Port/Label로 제한. **CNI가 지원해야 동작** (Calico, Cilium OK; Flannel 기본 X).

### 기본 동작

- NetworkPolicy 없으면 → **모든 Pod 간 통신 허용** (insecure default)
- NetworkPolicy 적용된 Pod → **명시한 것만 허용** (deny-all 후 allow)

### 예시 — PII namespace 분리

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pii-isolation
  namespace: pii-protected
spec:
  podSelector: {} # 이 namespace의 모든 Pod
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: kosa-tickets # kosa-tickets namespace만 허용
      ports:
        - protocol: TCP
          port: 3306
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kosa-tickets
```

회원/예약 DB(`pii-protected`)는 앱 namespace(`kosa-tickets`)에서만 접근 가능. 모니터링/ArgoCD 등
다른 namespace는 차단.

---

## 3) Calico vs Cilium NetworkPolicy

|                    | **Calico (우리)** | Cilium      |
| ------------------ | ----------------- | ----------- |
| 표준 NetworkPolicy | ✅                | ✅          |
| L7 정책            | 별도 (extension)  | 기본 (eBPF) |
| 성능               | 우수              | 최고        |
| 학습 자료          | 풍부              | 점차 늘어남 |

L4까지로 충분하면 Calico. L7 (URL 경로별 차단) 필요하면 Cilium.

---

## 4) AWS WAF

### 정체

웹 애플리케이션 방화벽. HTTP(S) 트래픽을 분석해 공격 차단.

### 막아주는 공격

| 공격          | 예시                   | 룰                                   |
| ------------- | ---------------------- | ------------------------------------ |
| SQL Injection | `' OR 1=1 --`          | AWSManagedRulesSQLiRuleSet           |
| XSS           | `<script>...</script>` | AWSManagedRulesKnownBadInputsRuleSet |
| 봇            | 비정상 트래픽          | Bot Control                          |
| Rate limit    | 한 IP 100 req/s        | Rate-based rule                      |
| OWASP Top 10  | 다양                   | CoreRuleSet                          |

### 우리 적용

NLB에 WAF 연결. 모든 요청이 WAF 검사 후 백엔드로.

```hcl
resource "aws_wafv2_web_acl_association" "nlb" {
  resource_arn = aws_lb.nlb.arn
  web_acl_arn  = aws_wafv2_web_acl.kosa.arn
}
```

---

## 5) K8s RBAC

### 정체

Role-Based Access Control. 누가 어떤 K8s 리소스에 무엇을 할 수 있는지.

### 4가지 객체

|                        | 범위          | 예시                     |
| ---------------------- | ------------- | ------------------------ |
| **Role**               | namespace     | 한 namespace 안 Pod read |
| **ClusterRole**        | 클러스터 전체 | 모든 Node read           |
| **RoleBinding**        | namespace     | User X에게 Role Y        |
| **ClusterRoleBinding** | 클러스터 전체 | User X에게 ClusterRole Y |

### 예시 — 개발자에게 kosa-tickets namespace만 read-write

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: kosa-tickets
  name: developer
rules:
  - apiGroups: [""]
    resources: [pods, services, configmaps]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [apps]
    resources: [deployments, replicasets]
    verbs: [get, list, watch, create, update, patch, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: kosa-tickets
  name: dev-binding
subjects:
  - kind: User
    name: dev@kosa.team
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

---

## 6) Pod Security Standards (PSS)

PSP (Pod Security Policy)가 deprecated 되고 PSS로.

3단계: | 레벨 | 의미 | |---|---| | `privileged` | 제한 없음 (legacy) | | `baseline` | 일반적 제한 |
| `restricted` | 강력 제한 (root, hostPath 등 X) |

namespace 라벨로 적용:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

우리 환경:

- `metallb-system` → `privileged` (MetalLB는 root 필요)
- `kosa-tickets` → `baseline`
- `pii-protected` → `restricted`

---

## 7) Secret 관리

K8s `Secret`은 **base64 인코딩일 뿐 암호화 X**. etcd에 평문 저장.

대안:

- **Sealed Secrets** — Git에 암호화된 채로 커밋
- **External Secrets Operator** — AWS Secrets Manager / HashiCorp Vault에서 가져옴
- **SOPS** — 파일 단위 암호화

학습 환경에선 기본 Secret 사용. 발표 시 "운영에선 Sealed Secrets 권장" 언급.

---

## 8) 발표 어필

> _"Defense in Depth 원칙으로 5계층 보안을 적용했습니다: AWS WAF (L7), pfSense (L3/4), K8s
> NetworkPolicy (Pod 통신), Pod Security Standards (Container 권한), RBAC (API 권한). 회원 데이터는
> 별도 namespace(pii-protected)에 격리되고 NetworkPolicy로 외부 접근 100% 차단됩니다."_

---

## 학습 완료

11개 단원 모두 학습했다면:

- 본인 담당 단원 🔴 (설계 가능)
- 그 외 🟡 (운영 가능)
- 발표 시 모든 단원 🟢 (설명 가능)

다음 → `../project/` 디렉토리로 가서 우리 프로젝트의 구체 구현 학습.
