# 05. Secrets + RBAC

> ⭐ **한 줄 요약**: 현재는 **K8s Secret (평문 base64) + ServiceAccount + RBAC** 패턴으로 운영한다. **etcd encryption 미활성 + Git commit 불가**가 약점이라 Phase 6에서 **Sealed Secrets** 도입이 우선이다. 운영급은 Vault + External Secrets Operator가 정석.

---

## 🎯 우리가 한 선택 — 현재 상태

K8s native Secret을 만들어 namespace에 두고, Pod이 mount해서 사용한다. ArgoCD/cert-manager는 자기 namespace 안에서 Secret을 직접 만들고, Jenkins/Harbor 같은 도구는 setup 시 manual로 Secret 생성한다.

| 항목 | 값 |
|---|---|
| 도구 | K8s native Secret (평문 base64) |
| 저장 | etcd (encryption at rest **미활성** — 위험) |
| Git commit | ❌ (평문 base64는 commit 불가) |
| 회전 | 수동 |

### 주요 Secret 분포

| 이름 | namespace | 용도 |
|---|---|---|
| `harbor-creds-dockerconfigjson` | jenkins | Jenkins → Harbor push |
| `harbor-pull-secret` | kosa-tickets 등 | Pod → Harbor pull |
| `kosa-gitops-ssh` | jenkins | Jenkins → GitOps repo push |
| `alertmanager-...-generated` | monitoring | SMTP password |
| `kosa-pxc-secrets` | pii-protected | PXC root password |
| `argocd-initial-admin-secret` | argocd | ArgoCD admin |

### RBAC 분리

| 주체 | 권한 |
|---|---|
| Jenkins ServiceAccount | namespace jenkins 자원 + agent Pod create |
| ArgoCD application-controller | cluster-admin (all resources) |
| Tempo/Loki SA | 자기 ns 내 |
| 일반 사용자 | kubectl 접근 (bastion 통해) |

ArgoCD가 cluster-admin인 게 critical하다. 모든 K8s resource를 manage할 권한이 있어, ArgoCD 자체가 침해되면 cluster 전체 위험이다. 이 점이 ArgoCD의 보안 부담이 큰 이유다.

---

## 🔍 고려한 대안

### Secret 관리 — 5가지 옵션

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **K8s Secret (현재)** | 단순, K8s 표준 | 평문 base64, etcd 평문, Git commit 불가 | ★★★ (학습엔 OK) |
| **Sealed Secrets** | Git commit 가능, 단순 | controller key 백업 책임 | ★★★★★ |
| **External Secrets Operator + Vault** | 동적 발급, audit, 회전 | Vault 운영 부담 | ★★★★ (운영급) |
| **External Secrets + AWS Secrets Manager** | AWS 관리, 자동 회전 | AWS lock, 비용 | ★★★★ (AWS 환경) |
| **HashiCorp Vault PKI/KV** | 강력, 동적 | 무거움 | ★★★★ |

### K8s Secret의 본질적 약점

K8s Secret은 사실 그냥 base64 encoded data다. **암호화가 아니라 그저 인코딩**이라 누구든 `kubectl get secret -o jsonpath='{.data}' | base64 -d`로 평문을 볼 수 있다. etcd backup이 유출되면 모든 password가 노출되는 위험이 있다.

GitOps 관점에서도 문제다. Secret을 git에 commit하면 평문 password를 repo에 푸시하는 셈. 그래서 우리는 helm values에 reference만 두고 (`existingSecret: harbor-creds`), Secret 자체는 manual로 생성한다. **이게 GitOps 일관성을 깨는 부분**이다.

### Sealed Secrets의 매력

Sealed Secrets는 이 약점을 해결한다. controller가 cluster에서 generated된 private key를 가지고, 사용자는 `kubeseal` CLI로 Secret을 암호화한 SealedSecret을 만들어 git commit. controller가 cluster에서 자동으로 decrypt해서 K8s Secret으로 변환. **GitOps 일관성 + 보안 모두 챙긴다**.

단점은 **controller private key 백업이 critical**이라는 점이다. 그 key를 잃으면 모든 SealedSecret을 복호화 못 한다.

### Vault + External Secrets

진짜 운영급은 HashiCorp Vault에 secret 저장 + 동적 발급 + 회전 + audit. External Secrets Operator가 K8s ↔ Vault 다리. 강력하지만 Vault 운영이 ★★★ 부담.

---

## 💡 왜 현재 K8s Secret만?

### 1. 학습 환경 단순화

Sealed Secrets/Vault는 추가 컴포넌트 + 학습 시간 ↑. 학습 환경엔 K8s native Secret으로 시작이 합리적이고, 한계를 직접 체감하면서 Phase 6에 개선하는 패턴이 학습 가치 ↑이다.

### 2. 트레이드오프 의식적 인지

평문 base64의 위험을 알고 있다. **Git commit 불가 + etcd 평문 노출 위험**이 명확한 약점. Phase 6 우선 작업으로 Sealed Secrets 도입 계획 명시.

### 3. 시급도 vs 다른 작업

현재 학습 환경에선 etcd 직접 접근하는 사람이 4명 팀뿐이라 secret 노출 위험이 ↓이다. sys2 추가, backup 자동화 같은 다른 critical 작업이 우선순위가 더 높았다.

---

## 💰 비용 분석

| 도구 | 비용 |
|---|---|
| K8s Secret | 0 |
| Sealed Secrets | 0 (controller 1 Pod) |
| Vault | 0 (자체) 또는 ★★★ 운영 |
| External Secrets + AWS SM | $0.40/secret/월 + API call |

비용은 모두 작다. 진짜 차이는 **운영 부담과 보안 강도**의 trade-off다.

---

## ⚖️ Trade-off

### 현재 K8s Secret만

| 얻은 것 | 잃은 것 |
|---|---|
| 단순 | Git commit 불가 |
| K8s 표준 | etcd 평문 (encryption 미활성) |
| 학습 곡선 0 | 운영 진입 불가 |

운영 진입 불가는 강한 표현이지만 사실이다. 진짜 운영급은 secret이 git에 commit돼야 GitOps 일관성이 완성되고, etcd encryption은 컴플라이언스 요구사항인 경우가 많다.

---

## ⚠️ SPoF + 위험

| 위험 | 영향 | 대응 |
|---|---|---|
| **K8s API server 죽음 + etcd 침해** | 모든 Secret 노출 | etcd encryption at rest 활성 + access 통제 |
| **Secret 평문 etcd 백업 유출** | 백업에서 password 추출 가능 | 백업도 암호화 |
| **kubectl 접근 권한 가진 사람 다 알 수 있음** | 내부자 위협 | RBAC 강화 + audit log |
| **회전 안 함 → 영구 노출** | password 누출 시 무한 노출 | 회전 정책 (90일) + automation |

가장 우려스러운 시나리오는 **etcd backup 유출**이다. 우리 backup이 평문 etcd라 어디 유출되면 모든 password가 같이 노출된다. **etcd encryption at rest + 백업 암호화**가 같이 가야 안전하다.

---

## 🚀 확장 가능성

### Option A: ⭐ Sealed Secrets 도입 (Phase 6 우선)

가장 시급한 개선이다. controller 1 Pod (~100MB) 설치 + 기존 Secret을 SealedSecret으로 변환. **GitOps 일관성 완성** + Git commit 가능. 4시간 작업이라 ROI가 좋다.

- 💰 **비용**: 0
- ⏱️ **작업**: 4시간
- 🎯 **추천 시점**: 즉시 (Phase 6 #1)

### Option B: ⭐ External Secrets Operator + Vault

진짜 운영급. Vault에 secret 저장 + 동적 발급 + 회전 자동 + audit ★★★★★. Vault 운영 ★★★ 부담이라 신중해야 한다.

- 💰 **비용**: Vault Pod 1GB + 학습 시간
- 🎯 **추천 시점**: 운영급 진입 또는 컴플라이언스 (PCI/HIPAA)

### Option C: etcd encryption at rest

K8s kubeadm config에 encryption provider 추가하면 etcd가 secret을 자동 암호화 저장. 백업 노출 시도 데이터 보호.

- 💰 **비용**: 0 (config 수정만)
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option D: 자동 회전 (cert-manager 같은 패턴)

현재 모든 password가 manual 회전. External Secrets + Vault 도입 후 30~90일 자동 회전 가능.

### Option E: K8s audit logging

누가 언제 어떤 Secret을 접근했는지 audit trail. Loki에 통합하면 분석 + 알람 가능.

### Option F: Pod Security Admission

privileged Pod 방지 같은 Pod 레벨 보안 정책. PodSecurityPolicy (deprecated)의 후속.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| GitOps 완성 | A (Sealed Secrets) ⭐ |
| 운영급 | A + B + C |
| 컴플라이언스 | B + C + E |

---

## 🔗 다른 파트와의 연결

이 Secret/RBAC 결정은 모든 파트와 연결된다. CI/CD에선 Jenkins/Harbor credentials, 데이터에선 DB password와 replication user, 아키텍처에선 etcd encryption 결정. 모두 보안 정책의 일부다 (`07-security-policy.md`).

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. K8s Secret이 평문 base64인데 보안은 어떻게요?**

A. **솔직히 약점**입니다. 현재 대응은 (1) **etcd 접근 제한** (kubectl + bastion만), (2) **RBAC로 Secret read 제한**, (3) **Phase 6에서 Sealed Secrets/Vault 도입 예정**. 학습 환경 한계 + 개선 계획 명시 패턴입니다.

**Q2. ArgoCD가 cluster-admin인데 위험하지 않나요?**

A. **ArgoCD는 모든 K8s resource를 manage해야 하므로 admin 필요**합니다. 위험은 ArgoCD 자체 침해 시 cluster 전체 위험인데, 완화책은 (1) **ArgoCD UI에 강력한 인증** (현재 admin/password — 약함), (2) **AppProject로 namespace 분리** (RBAC 정밀화), (3) **SSO 통합** (운영급). 우리는 학습 환경이라 강력한 인증을 우선시하지 못했지만 위험은 인지하고 있습니다.

**Q3. Sealed Secrets와 Vault 차이는요?**

A. **Sealed = Git에 암호문 commit, controller가 cluster에서 복호화**합니다. **Vault = 동적 발급 + 회전 + audit + 더 강력한 보안**. Sealed는 가볍고 GitOps만 필요하고, Vault는 운영급 (compliance) 표준입니다. Phase 6엔 Sealed로 시작, Phase 7+에 Vault 검토.

**Q4. ServiceAccount token 만료는요?**

A. **K8s 1.21+ ServiceAccount token이 default 1년 만료**입니다. 우리 K8s 1.30이라 적용됩니다. Token 만료 시 자동 갱신 (projected volume)이라 사람 개입 X. 옛 K8s 버전이면 token이 영구 유효라 위험이 컸습니다.

**Q5. password 회전 정책은요?**

A. **현재 없습니다 (학습 환경)**. 운영급은 90일 회전이 일반적이고, Vault + External Secrets로 자동화 가능합니다. 우리는 Phase 7에 Vault 도입 후 회전 정책 추가 계획입니다.

**Q6. ArgoCD가 helm values에 박는 password (예: SMTP)는 어떻게 보호하나요?**

A. **솔직히 현재 평문 Git에 노출**입니다 (학습 환경 단순화). Phase 6에서 (1) **Sealed Secrets로 변환** 또는 (2) **existingSecret 참조** 패턴으로 변경 예정입니다. helm values엔 reference만 두고 Secret 자체는 별도 관리하는 게 정석입니다.
