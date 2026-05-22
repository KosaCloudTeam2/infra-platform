# 07. 보안 정책 + 거버넌스

> ⭐ **한 줄 요약**: 기술 통제는 다른 문서에서, 여기는 **정책 + 원칙 + 프로세스**. 5 원칙 + 위협 모델 + 컴플라이언스 + 인증서 인벤토리 + 회전 catalog.

---

## 🎯 5가지 보안 원칙

### 1. Zero Trust 네트워크
모든 inter-pod 통신은 명시적 허용만. (구현: NetworkPolicy)
→ **상세**: `03-network-policy.md`

### 2. Defense in Depth (이중 TLS)
신뢰 경계마다 TLS 재종료. 한 layer 뚫려도 다음이 보호.
→ **상세**: `02-tls-self-ca-double.md`

### 3. Least Privilege
- K8s ServiceAccount = namespace 한정
- AWS IAM = service별 분리
→ **상세**: `05-secrets-rbac.md`

### 4. 외부 노출 최소화
- 외부 진입 = Edge HAProxy 1곳 (DMZ)
- 모든 내부 도메인은 외부 접근 X
- pfSense Port Forward = 명시적 명단만
→ **상세**: `01-pfsense-firewall.md`

### 5. Secret 분리
- 코드에 secret commit X
- K8s Secret + cert-manager
→ **상세**: `05-secrets-rbac.md` + Phase 6 Sealed Secrets

---

## 🛡️ 위협 모델 (Threat Model)

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

---

## 📜 컴플라이언스 + 감사

### 로그 수집 (Audit Trail)
| 로그 종류 | 수집처 | 보관 |
|---|---|---|
| K8s audit log | 미수집 | (향후 Loki) |
| HAProxy access log | Loki | 7일 |
| pfSense firewall log | 미수집 | (향후 Syslog → Loki) |
| AWS CloudTrail | CloudWatch | 90일 |
| Jenkins audit | Jenkins UI | 무제한 |
| Harbor audit | Harbor DB | 무제한 |

### 인증서 인벤토리
| 인증서 | 발급 | 만료 | 갱신 책임 |
|---|---|---|---|
| KOSA Team2 Internal CA | 자체 | 2036 (10년) | 9년 catalog (수동) |
| `*.kosa.team2` wildcard | 자체 CA | 매년 | 11개월 catalog |
| service별 cert | cert-manager | 90일 | 자동 |
| Harbor TLS | cert-manager | 90일 | 자동 |
| Edge HAProxy cert | wildcard 위 | 1년 | 11개월 catalog |
| AWS RDS cert | AWS 관리 | 자동 | AWS |

### 비밀번호 정책 (현재 학습 환경)
| 시스템 | 현재 | 운영급 권장 |
|---|---|---|
| Jenkins admin | kosa1004 | 12자+ 복잡, 90일 회전 |
| ArgoCD admin | kubectl secret | SSO 통합 |
| Harbor admin | kosa1004 | 12자+ 복잡, robot account |
| pfSense admin | (별도) | SSH 비활성 + GUI access 제한 |
| PXC root | rootpass123! | 정기 회전 |

---

## 🚨 사고 대응 절차 (Incident Response)

### 1단계: 감지 (Detection)
- Prometheus alert → AlertManager → email (parkpark131@naver.com)
- CloudWatch alarm → SNS → email
- 사용자 신고

### 2단계: 분석 (Analysis)
- 영향 범위 확인 (어떤 service, 얼마나, 언제부터)
- Loki/Prometheus/Tempo 3대축으로 root cause 추적

### 3단계: 격리 (Containment)
- 영향 받은 Pod scale down 또는 격리 (NetworkPolicy 추가)
- 침해 의심 시 노드 cordon + drain

### 4단계: 복구 (Recovery)
- 백업에서 복구 (또는 git에서 재구축)
- 정상 동작 검증

### 5단계: 회고 (Postmortem)
- `docs/onprem/incident-YYYY-MM-DD-*.md` 작성
- 원인 + 대응 + 재발 방지

→ 우리 사례: `docs/onprem/incident-2026-05-21-cp1-cascade.md`

---

## 🚀 보안 강화 로드맵

### Phase 6 (즉시 — 운영 진입 전)
1. **Sealed Secrets** 도입 — `05-secrets-rbac.md` Option A
2. **etcd encryption at rest** — `05-secrets-rbac.md` Option C
3. **AlertManager webhook 인증** (API Key) — `06-burst-trigger-security.md` Option A
4. **모든 ns NetworkPolicy 확장** — `03-network-policy.md` Option A
5. **Backup 자동화** — `08-backup-dr-policy.md`

### Phase 7 (중기)
1. **Vault + External Secrets Operator** — `05` Option B
2. **K8s audit logging → Loki** — `05` Option E
3. **OPA/Gatekeeper** (정책 강제) — `03` Option D
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

**Q1. 5 원칙이 그냥 글이 아니라 진짜 적용?**
A. 부분 적용. (1) Zero trust = ticket-app만 (다른 ns 진행 중), (2) 이중 TLS = ✅ 완전, (3) Least privilege = ServiceAccount 분리됨, (4) 외부 노출 = Edge HAProxy 1곳 ✅, (5) Secret = K8s Secret (Sealed Secrets Phase 6). 솔직한 자기 평가 중요.

**Q2. K8s audit log 수집 안 하는데 컴플라이언스?**
A. 현재 학습 환경엔 불필요. 운영 진입 시 (PCI/HIPAA) 필수 → Phase 7. 작업: kube-apiserver flag `--audit-policy-file` + 로그 → Loki.

**Q3. 정기 침투 테스트 비용?**
A. 회당 ~₩1000만 (외부 업체). 운영 6개월+ 시점에 검토. 데모/학습 환경엔 불필요.

**Q4. pfSense admin GUI 외부 노출?**
A. **No**. Internal VLAN에서만 접근 (172.16.x). 외부에서 pfSense 관리 불가 → 침해 risk ↓.

**Q5. 사고 발생 시 누가 책임?**
A. 4명 팀 모두 (RACI 표 권장). 실무에선 on-call rotation (Grafana OnCall, PagerDuty). 우리는 demo 환경이라 미적용.

**Q6. 보안 정책 1순위 강화?**
A. Phase 6 #1 Sealed Secrets — GitOps 완성 + Secret 평문 노출 위험 해소. 4시간 작업, 효과 ★★★★.
