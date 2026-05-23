# 07. 보안 정책 + 거버넌스

> ⭐ **한 줄 요약**: 다른 보안 문서들이 **기술 통제 (NetworkPolicy, TLS 등)를 다룬다면 여기는 정책/원칙/프로세스**다. 5가지 원칙 + 위협 모델 + 컴플라이언스 + 인증서 인벤토리 + 사고 대응 절차를 정리한다.

---

## 🎯 5가지 보안 원칙

우리 인프라의 보안은 다섯 가지 원칙으로 정리할 수 있다. 모든 기술 결정은 이 원칙 중 하나를 구현한다.

### 1. Zero Trust 네트워크

모든 inter-pod 통신을 명시적으로 허용한 것만 통과시킨다. K8s NetworkPolicy + Calico로 구현하고, 현재 ticket-app에 적용돼 있다. 다른 ns로 확장은 Phase 6 작업.

→ **상세**: `03-network-policy.md`

### 2. Defense in Depth (이중 TLS)

신뢰 경계마다 TLS를 재종료해서 한 layer가 뚫려도 다음이 보호하게 만든다. 외부 → Edge HAProxy → K8s Ingress → Pod 흐름에서 두 layer가 TLS 종료를 담당한다.

→ **상세**: `02-tls-self-ca-double.md`

### 3. Least Privilege (최소 권한)

K8s ServiceAccount는 namespace 한정으로, AWS IAM은 service별로 분리한다. ArgoCD가 예외적으로 cluster-admin인 게 약점인데, 진짜 운영급에선 AppProject로 RBAC를 정밀화한다.

→ **상세**: `05-secrets-rbac.md`

### 4. 외부 노출 최소화

외부 진입점이 Edge HAProxy 1곳뿐이다 (DMZ). Jenkins/Grafana/ArgoCD 등 운영 도구는 모두 내부 도메인 (*.kosa.team2)이고 외부에서 직접 접근 불가. pfSense Port Forward는 명시적 명단 (80/443)만.

→ **상세**: `01-pfsense-firewall.md`

### 5. Secret 분리

코드/Git에 password를 commit하지 않는다. K8s Secret + cert-manager로 관리하지만, 현재 K8s Secret이 평문 base64라 GitOps 일관성이 깨지는 약점이 있다. Sealed Secrets 도입이 Phase 6 우선.

→ **상세**: `05-secrets-rbac.md` + Phase 6 Sealed Secrets

---

## 🛡️ 위협 모델 (Threat Model)

우리가 인지하고 대응 중인 위협을 정리하면 12가지가 된다. 각 위협의 영향, 대응 도구, 현재 상태를 명시한다.

| 위협 | 영향 | 대응 도구 | 현재 상태 |
|---|---|---|---|
| 외부 스캐너 | 정찰 | pfSense + WAF | ✅ |
| DDoS L3/L4 | 서비스 중단 | CloudFront + AWS Shield | ✅ |
| DDoS L7 (HTTP flood) | 서비스 중단 | WAF Rate Limit | ⚠️ (k6 차단으로 임시 제거) |
| SQL Injection | DB 노출 | AWS WAF + ORM | ✅ |
| XSS | 사용자 피해 | AWS WAF + CSP header | ✅ + ⚠️ (앱 CSP 미적용) |
| 컨테이너 탈출 | 노드 침해 | Calico + Pod SecurityContext | ⚠️ (Kaniko rootless OK, 다른 Pod 정책 약) |
| 내부자 위협 | 권한 남용 | RBAC + audit log | ⚠️ (audit log 미수집) |
| Supply chain (이미지) | 악성 코드 | Harbor + Trivy 스캔 | ✅ |
| Secret 유출 | 노출 | K8s Secret + cert-manager | ⚠️ (Sealed Secrets 미도입) |
| 인증서 만료 | 서비스 중단 | cert-manager 자동 갱신 | ✅ (service cert만) |
| pfSense 침해 | 전체 인프라 | pfSense 보안 (강력한 admin password, SSH 비활성) | ⚠️ (정기 update 필요) |
| 강의장 네트워크 도청 | 트래픽 노출 | 이중 TLS | ✅ |

12개 중 7개는 대응 완료 (✅), 5개는 부분 대응 (⚠️)이다. 부분 대응 항목들이 Phase 6/7 작업 우선순위가 된다.

가장 우려스러운 ⚠️는 **컨테이너 탈출**과 **내부자 위협**이다. 컨테이너 탈출은 Pod SecurityContext + Falco 같은 runtime 탐지로 강화 가능하고, 내부자 위협은 audit log + Vault로 보완 가능하다.

---

## 📜 컴플라이언스 + 감사

### 로그 수집 (Audit Trail)

audit log는 사고 후 추적의 핵심이다. 현재 우리 수집 상태를 정리하면:

| 로그 종류 | 수집처 | 보관 |
|---|---|---|
| K8s audit log | **미수집** | (향후 Loki) |
| HAProxy access log | Loki | 7일 |
| pfSense firewall log | **미수집** | (향후 Syslog → Loki) |
| AWS CloudTrail | CloudWatch | 90일 |
| Jenkins audit | Jenkins UI | 무제한 |
| Harbor audit | Harbor DB | 무제한 |

**K8s audit log와 pfSense firewall log가 미수집**이 약점이다. K8s audit log는 kube-apiserver flag로 enable + Loki로 흘려보내면 가능. pfSense는 syslog forward로 외부로 보낸 후 Loki에 ingest.

### 인증서 인벤토리

회전 일정 관리가 중요한 인증서들:

| 인증서 | 발급 | 만료 | 갱신 책임 |
|---|---|---|---|
| KOSA Team2 Internal CA | 자체 | 2036 (10년) | 9년 catalog (수동) |
| `*.kosa.team2` wildcard | 자체 CA | 매년 | 11개월 catalog |
| service별 cert | cert-manager | 90일 | 자동 |
| Harbor TLS | cert-manager | 90일 | 자동 |
| Edge HAProxy cert | wildcard 위 | 1년 | 11개월 catalog |
| AWS RDS cert | AWS 관리 | 자동 | AWS |

service별 cert는 cert-manager가 자동 회전이라 신경 안 써도 되지만, 자체 CA (10년)와 wildcard cert (1년)는 manual 회전이라 catalog가 critical하다.

### 비밀번호 정책 (현재 학습 환경)

| 시스템 | 현재 | 운영급 권장 |
|---|---|---|
| Jenkins admin | kosa1004 | 12자+ 복잡, 90일 회전 |
| ArgoCD admin | kubectl secret | SSO 통합 |
| Harbor admin | kosa1004 | 12자+ 복잡, robot account |
| pfSense admin | (별도) | SSH 비활성 + GUI access 제한 |
| PXC root | rootpass123! | 정기 회전 |

학습 환경이라 password가 약한 게 명백한 약점이다. 운영급은 password manager + 회전 정책 + SSO가 표준.

---

## 🚨 사고 대응 절차 (Incident Response)

보안 사고 발생 시 따를 표준 절차다. 5단계로 정형화돼 있다.

### 1단계: 감지 (Detection)

- Prometheus alert → AlertManager → email (parkpark131@naver.com)
- CloudWatch alarm → SNS → email
- 사용자 신고

### 2단계: 분석 (Analysis)

영향 범위 확인 (어떤 service, 얼마나, 언제부터). Loki/Prometheus/Tempo 3대축으로 root cause 추적한다. 이 단계에서 관측 stack의 가치가 드러난다 — 분리된 도구라도 통합 분석이 가능해야 한다.

### 3단계: 격리 (Containment)

영향 받은 Pod scale down 또는 격리 (NetworkPolicy 추가). 침해 의심 시 노드 cordon + drain. 사고가 cascade되지 않게 빠르게 봉쇄.

### 4단계: 복구 (Recovery)

백업에서 복구 (또는 git에서 재구축). ArgoCD가 git을 source of truth로 운영하니 git에서 재 deploy가 자연스럽다. 백업이 없는 데이터 (PXC 등)는 별도 복구.

### 5단계: 회고 (Postmortem)

`docs/onprem/incident-YYYY-MM-DD-*.md` 작성. 원인 + 대응 + 재발 방지를 문서화. **우리 사례**: `docs/onprem/incident-2026-05-21-cp1-cascade.md`. 이게 cp1 etcd cascade 9-layer 사고의 회고로, 같은 사고 재발 방지 fix (etcd auto-compact, HAProxy fall 5, GARP)가 적용됐다.

---

## 🚀 보안 강화 로드맵

### Phase 6 (즉시 — 운영 진입 전)

1. **Sealed Secrets 도입** — `05-secrets-rbac.md` Option A
2. **etcd encryption at rest** — `05-secrets-rbac.md` Option C
3. **AlertManager webhook 인증 (API Key)** — `06-burst-trigger-security.md` Option A
4. **모든 ns NetworkPolicy 확장** — `03-network-policy.md` Option A
5. **Backup 자동화** — `08-backup-dr-policy.md`

이 5개가 Phase 6의 보안 영역 작업이다. 운영 진입 직전 무조건 적용해야 할 것들.

### Phase 7 (중기)

1. **Vault + External Secrets Operator** — `05` Option B
2. **K8s audit logging → Loki** — `05` Option E
3. **OPA/Gatekeeper (정책 강제)** — `03` Option D
4. **Image signing (Cosign)** — `cicd/04-harbor` Option F
5. **HMAC webhook 인증** — `06` Option B

### Phase 8 (장기)

1. **Service Mesh (Linkerd)** — mTLS 자동 + L7 정책
2. **Falco (Runtime 위협 탐지)**
3. **정기 침투 테스트** (외부 업체)
4. **PCI/HIPAA 컴플라이언스 인증**

---

## 🔗 다른 문서 참조

| 토픽 | 문서 |
|---|---|
| 방화벽 + DNS + VPN | `01-pfsense-firewall.md` |
| TLS + CA | `02-tls-self-ca-double.md` |
| K8s 네트워크 격리 | `03-network-policy.md` |
| 외부 트래픽 보호 | `04-aws-waf-cloudfront.md` |
| Secret + RBAC | `05-secrets-rbac.md` |
| Burst webhook 보안 | `06-burst-trigger-security.md` |
| Backup + DR | `08-backup-dr-policy.md` |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. 5 원칙이 그냥 글이 아니라 진짜 적용되나요?**

A. **부분 적용**입니다. (1) Zero trust = ticket-app만 (다른 ns 진행 중), (2) 이중 TLS = ✅ 완전, (3) Least privilege = ServiceAccount 분리됨 (ArgoCD admin 예외), (4) 외부 노출 = Edge HAProxy 1곳 ✅, (5) Secret = K8s Secret (Sealed Secrets Phase 6). **솔직한 자기 평가**가 중요합니다 — 다 됐다고 거짓 답하기보다 부분 적용 + 개선 계획이 면접 어필 패턴입니다.

**Q2. K8s audit log 수집 안 하는데 컴플라이언스가 되나요?**

A. **현재 학습 환경엔 불필요**합니다. 운영 진입 시 (PCI/HIPAA) 필수가 되고 Phase 7 작업입니다. 작업: kube-apiserver flag `--audit-policy-file` + 로그 → Loki. 1일 정도 작업.

**Q3. 정기 침투 테스트 비용은요?**

A. **회당 ~₩1000만 (외부 업체)**. 운영 6개월+ 시점에 검토. 데모/학습 환경엔 불필요합니다. 진짜 운영 + 매출 발생 + 사용자 데이터 다루는 환경에서 의미 있습니다.

**Q4. pfSense admin GUI가 외부 노출인가요?**

A. **No**. Internal VLAN (172.16.x)에서만 접근 가능합니다. 외부에서 pfSense 관리는 불가하니 침해 risk가 ↓입니다. SSH도 비활성 권장 (GUI만).

**Q5. 사고 발생 시 누가 책임지나요?**

A. **4명 팀 모두**입니다 (RACI 표 권장). 실무에선 on-call rotation (Grafana OnCall, PagerDuty)로 시간대별 책임자를 명시합니다. 우리는 demo 환경이라 미적용이지만 진짜 운영 시 필수입니다.

**Q6. 보안 정책 1순위 강화는 뭐예요?**

A. **Phase 6 #1 Sealed Secrets**입니다. **GitOps 완성 + Secret 평문 노출 위험 해소** 둘 다 챙기는 작업이라 ROI가 가장 좋습니다. 4시간 작업으로 효과 ★★★★. etcd encryption at rest도 같이 적용하면 좋습니다.
