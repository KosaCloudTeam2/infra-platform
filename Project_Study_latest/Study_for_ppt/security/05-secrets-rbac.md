# 05. Secrets + RBAC

> ⭐ **한 줄 요약**: K8s Secret (현재 평문 base64) + ServiceAccount + RBAC. Sealed Secrets는 Phase 6 도입 예정. 운영급은 Vault 권장.

---

## 🎯 우리가 한 선택 (현재 상태)

### Secret 관리
| 항목 | 값 |
|---|---|
| 도구 | K8s native Secret (평문 base64) |
| 저장 | etcd (encryption at rest **미활성** — 위험) |
| Git commit | ❌ (평문 base64는 commit 불가) |
| 회전 | 수동 |

### 주요 Secret
| 이름 | namespace | 용도 |
|---|---|---|
| `harbor-creds-dockerconfigjson` | jenkins | Jenkins → Harbor push |
| `harbor-pull-secret` | kosa-tickets 등 | Pod → Harbor pull |
| `kosa-gitops-ssh` | jenkins | Jenkins → GitOps repo push |
| `alertmanager-...-generated` | monitoring | SMTP password |
| `kosa-pxc-secrets` | pii-protected | PXC root password |
| `argocd-initial-admin-secret` | argocd | ArgoCD admin |

### RBAC
| 주체 | 권한 |
|---|---|
| Jenkins ServiceAccount | namespace jenkins 자원 + agent Pod create |
| ArgoCD application-controller | cluster-admin (all resources) |
| Tempo/Loki SA | 자기 ns 내 |
| 일반 사용자 | kubectl 접근 (bastion 통해) |

---

## 🔍 고려한 대안

### Secret 관리

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **K8s Secret (현재)** | 단순, K8s 표준 | 평문 base64, etcd 평문, Git commit 불가 | ★★★ (학습엔 OK) |
| **Sealed Secrets** | Git commit 가능, 단순 | controller key 백업 책임 | ★★★★★ |
| **External Secrets Operator + Vault** | 동적 발급, audit, 회전 | Vault 운영 부담 | ★★★★ (운영급) |
| **External Secrets + AWS Secrets Manager** | AWS 관리, 자동 회전 | AWS lock, 비용 | ★★★★ (AWS 환경) |
| **HashiCorp Vault PKI/KV** | 강력, 동적 | 무거움 | ★★★★ |

---

## 💡 왜 현재 K8s Secret만?

### 1. 📚 **학습 환경 단순화**
- Sealed Secrets, Vault 설치/운영 부담 ↑
- 데모에 K8s Secret 한계 직접 보여줌 (정직)

### 2. 🎯 **트레이드오프 인지**
- Git commit 불가 = manual 관리
- 운영 진입 시 무조건 개선 필요

### 3. ⏱️ **Phase 6 우선순위 명시**
- 발표 시 "현재 한계 + 개선 계획" 솔직 어필
- → `security/07-security-policy.md` Option A에 Sealed Secrets 우선

---

## 💰 비용 분석

| 도구 | 비용 |
|---|---|
| K8s Secret | 0 |
| Sealed Secrets | 0 (controller 1 Pod) |
| Vault | 0 (자체) 또는 ★★★ 운영 |
| External Secrets + AWS SM | $0.40/secret/월 + API call |

---

## ⚖️ Trade-off

### 현재 K8s Secret만
| 얻은 것 | 잃은 것 |
|---|---|
| 단순 | Git commit 불가 |
| K8s 표준 | etcd 평문 (encryption 미활성) |
| 학습 곡선 0 | 운영 진입 불가 |

---

## ⚠️ SPoF + 위험

| 위험 | 영향 | 대응 |
|---|---|---|
| **K8s API server 죽음 + etcd 침해** | 모든 Secret 노출 | etcd encryption at rest 활성 + access 통제 |
| **Secret 평문 etcd 백업 유출** | 백업에서 password 추출 가능 | 백업도 암호화 |
| **kubectl 접근 권한 가진 사람 다 알 수 있음** | 내부자 위협 | RBAC 강화 + audit log |
| **회전 안 함 → 영구 노출** | password 누출 시 무한 노출 | 회전 정책 (90일) + automation |

---

## 🚀 확장 가능성

### Option A: ⭐ Sealed Secrets 도입 (Phase 6 우선)
- ✅ **장점**: Git commit 가능 (declarative GitOps 완성), 컨트롤러 key로 복호화
- ❌ **단점**: controller key 백업 책임
- 💰 **비용**: 0 (controller 1 Pod ~100MB)
- ⏱️ **작업**: 4시간 (설치 + 기존 Secret 변환)
- 🎯 **추천 시점**: 즉시 (Phase 6 #1)

### Option B: ⭐ External Secrets Operator + Vault
- ✅ **장점**: 동적 발급, 회전 자동, audit ★★★★★
- ❌ **단점**: Vault 운영 ★★★
- 💰 **비용**: Vault Pod 1GB + 학습 시간
- 🎯 **추천 시점**: 운영급 진입 또는 컴플라이언스 (PCI/HIPAA)

### Option C: etcd encryption at rest
- ✅ **장점**: etcd 백업 노출 시 데이터 보호
- 💰 **비용**: 0 (kubeadm config)
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option D: 자동 회전 (cert-manager 같은 패턴)
- 현재: 모든 password 수동
- 확장: External Secrets로 30~90일 자동 회전
- 🎯 **추천 시점**: Vault 도입 후

### Option E: K8s audit logging
- ✅ **장점**: 누가 Secret 접근했는지 감사
- 💰 **비용**: 로그 저장 (Loki 통합)
- 🎯 **추천 시점**: 컴플라이언스

### Option F: PodSecurityPolicy (deprecated) → Pod Security Admission
- ✅ **장점**: privileged Pod 방지
- 🎯 **추천 시점**: 운영 진입

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| GitOps 완성 | A (Sealed Secrets) |
| 운영급 | A + B |
| 컴플라이언스 | B + C + E |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔧 CI/CD | Jenkins/Harbor credentials |
| 💾 데이터 | DB password, replication user |
| 🏛️ 아키텍처 | etcd encryption 결정 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. K8s Secret이 평문 base64인데 보안 어떻게?**
A. 현재는 (1) etcd 접근 제한 (kubectl + bastion), (2) RBAC로 Secret read 제한, (3) Phase 6에서 Sealed Secrets/Vault 도입 예정. 학습 환경 한계 + 개선 계획 명시.

**Q2. ArgoCD가 cluster-admin인데 위험?**
A. ArgoCD는 모든 K8s resource를 manage하므로 admin 필요. 위험은 ArgoCD 자체 침해 시 cluster 전체 위험. 완화: ArgoCD UI에 강력한 인증 (현재 admin/password), AppProject로 namespace 분리 가능.

**Q3. Sealed Secrets와 Vault 차이?**
A. Sealed = Git에 암호문 commit, controller가 cluster에서 복호화. Vault = 동적 발급 + 회전 + audit. Sealed는 가볍고 (GitOps만 필요), Vault는 운영급 (compliance).

**Q4. ServiceAccount token 만료?**
A. K8s 1.21+ ServiceAccount token에 만료 시간 (default 1년). 우리 K8s 1.30이라 적용. Token 만료 시 자동 갱신 (projected volume).

**Q5. password 회전 정책?**
A. **현재 없음** (학습 환경). 운영급은 90일. Vault + External Secrets로 자동화 가능.

**Q6. ArgoCD가 helm values에 박는 password (예: alertmanager SMTP)는?**
A. helm values는 Git에 commit. **현재 SMTP password 평문 Git에 노출** (학습 환경 단순화). Phase 6에서 Sealed Secrets로 변환 또는 existingSecret 참조.
