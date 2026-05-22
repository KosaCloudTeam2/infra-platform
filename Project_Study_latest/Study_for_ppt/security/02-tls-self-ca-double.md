# 02. 자체 CA + 이중 TLS (Defense in Depth)

> ⭐ **한 줄 요약**: **자체 CA (KOSA Team2 Internal CA, 10년)** + **이중 TLS** = Edge HAProxy(외부) + HAProxy Ingress(내부) 두 번 종료. 내부 트래픽도 wire에서 평문 X. cert-manager가 90일 자동 회전.

---

## 🎯 우리가 한 선택

### CA 구조
| 항목 | 값 |
|---|---|
| Root CA | **KOSA Team2 Internal CA** (자체) |
| 만료 | 10년 (2036) |
| Key 보관 | bastion `~/pki/ca.key` (현재 평문 — 위험) |
| Wildcard cert | `*.kosa.team2` (1년, HAProxy Edge용) |
| Service별 cert | cert-manager가 90일 자동 발급 (`kosa-ca-issuer` ClusterIssuer) |

### 이중 TLS 흐름
```
[외부 client]
   │ HTTPS (TLS 1)
   ▼
[Edge HAProxy 172.16.22.5]
   │ TLS 1 종료 (자체 CA wildcard *.kosa.team2)
   │ Host 헤더 검사 (ACL)
   │
   │ HTTPS (TLS 2 — 재암호화)
   ▼
[HAProxy Ingress 172.16.23.50]
   │ TLS 2 종료 (cert-manager 발급 per-service cert)
   │ Path 라우팅
   │
   │ HTTP (cluster 내부 plaintext)
   ▼
[Pod]
```

### 모든 도메인 (5개) TLS 적용
- ticket.kosa.team2 → ticket-app
- grafana.kosa.team2 → kube-prom-grafana
- argocd.kosa.team2 → argocd-server
- harbor.kosa.team2 → harbor-core
- jenkins.kosa.team2 → jenkins

---

## 🔍 고려한 대안들

### Q1. 자체 CA vs Let's Encrypt vs Public CA

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **자체 CA (선택)** | 내부 도메인 OK, 무료, 통제 | 외부 신뢰 X (CA cert 배포 필요) | ★★★★ (내부망) |
| Let's Encrypt | 외부 신뢰, 자동 갱신 | DNS-01 필요 (내부 도메인 어려움), public DNS 노출 | ★★ (내부엔 어려움) |
| Public CA (DigiCert, GlobalSign 등) | 외부 신뢰 | 비쌈 ($100~/년) | ★★★ (외부 도메인) |
| 자체 CA + Let's Encrypt (hybrid) | 내부엔 자체, 외부엔 LE | 두 가지 운영 | ★★★★ (이상적) |

### Q2. TLS 종료 위치 — Edge only vs Ingress only vs 이중 (선택)

| 대안 | 장점 | 단점 |
|---|---|---|
| **이중 (Edge + Ingress) 선택** | 내부 트래픽도 암호화, cert 회전 독립 | TLS 핸드셰이크 2배 |
| Edge only | 단순 | 내부 평문 (cluster 내부 tap 위험) |
| Ingress only | 단순 | Edge 거치는 동안 평문 (DMZ 위험) |

### Q3. cert 자동화 — cert-manager vs manual vs Vault PKI

| 대안 | 장점 | 단점 |
|---|---|---|
| **cert-manager (선택)** | K8s native, ClusterIssuer 다양, 자동 갱신 | K8s만 (외부 cert X) |
| Manual | 통제 | 만료 risk, 갱신 부담 |
| HashiCorp Vault PKI | 강력, 동적 | Vault 운영 부담 |

---

## 💡 왜 자체 CA + 이중 TLS?

### 1. 🔒 **이중 TLS = Defense in Depth**
> 🔥 **핵심**: Edge 뚫려도 내부 평문 아님. 한 layer 무력화돼도 다음 layer 보호.

- 내부 트래픽도 wire에서 암호화
- 10G NIC tap/감청 방지
- cluster 내부 노드 침해돼도 다른 서비스 cert 별개

### 2. 🌐 **내부 도메인 (.kosa.team2)은 Let's Encrypt 안 됨**
- LE는 public DNS 검증 (HTTP-01 또는 DNS-01)
- `*.kosa.team2`는 public DNS에 없음 → 검증 불가
- DNS-01에 public TXT 추가하는 방법 있지만 학습 환경엔 과함

### 3. 💰 **무료**
- Public CA wildcard cert $200~/년
- 자체 CA: openssl 명령 한 번

### 4. ⚡ **cert-manager 자동화**
- ClusterIssuer 한번 설정 → 모든 service cert 자동 90일 회전
- Ingress annotation 한 줄로 cert 발급

### 5. 📚 **학습 가치**
- PKI 깊이 학습
- cert 회전/감사 실무 경험

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| 자체 CA (openssl) | 무료 |
| cert-manager (K8s) | 무료 (자원 ~100MB) |
| Wildcard *.kosa.team2 cert | 무료 (자체 발급) |
| 운영 부담 | 9년에 한 번 CA 갱신 + 가끔 cert manual 갱신 |

비교:
- DigiCert wildcard: $200~/년
- 자체 CA: ₩0

→ **9년에 한 번 CA 갱신만 (catalog 일정)**

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 통제 | 외부 신뢰 X (브라우저 cert 경고) |
| 내부 도메인 가능 | 외부 client에 CA cert 배포 부담 |
| 이중 TLS 보안 | TLS 핸드셰이크 2배 (성능 영향 미미) |
| cert-manager 자동화 | cert-manager 운영 부담 |
| 9년 만료 | 진짜 운영엔 catalog 필요 |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **자체 CA 만료 (10년)** | 모든 cert 망가짐 | 9년 catalog로 사전 회전 |
| **CA key 손실/유출** | 새 CA 만들고 모든 cert 재발급 + 모든 노드 trust 교체 | bastion key 백업 + KMS 등 |
| **cert-manager 죽음** | 새 cert 발급 안 됨 (기존 cert는 OK) | Pod 재시작 |
| **wildcard cert 만료 (1년)** | Edge HAProxy 죽음 | catalog 11개월 후 갱신 |
| **service cert 만료 (90일)** | 자동 갱신 (cert-manager) | 자동 |

---

## 🚀 확장 가능성

### Option A: ⭐ Let's Encrypt 추가 (외부 도메인)
- 현재: `*.kosa.team2` 자체 CA
- 확장: 외부 도메인 (예: ticket.caffeinism.cloud)은 LE
- 작업: cert-manager에 LE ClusterIssuer 추가 + DNS-01 (Route 53)
- 🎯 **추천 시점**: 외부 사용자에게 진짜 신뢰 cert 제공

### Option B: ⭐ HashiCorp Vault PKI
- ✅ **장점**: 동적 cert 발급, 강력한 audit, key 회전
- ❌ **단점**: Vault 운영
- 🎯 **추천 시점**: 컴플라이언스 강화

### Option C: cert key 회전 정책
- 현재: cert만 90일 회전, key는 그대로
- 확장: key도 회전 (cert-manager 옵션)
- 🎯 **추천 시점**: 보안 강화

### Option D: mTLS (양방향 인증)
- 현재: server cert만 (client는 익명)
- 확장: client cert 요구 (Pod ↔ Pod)
- ❌ **단점**: 운영 복잡 (cert 분배)
- 🎯 **추천 시점**: zero-trust 강화 (service mesh)

### Option E: Service Mesh (Istio/Linkerd) — 자동 mTLS
- ✅ **장점**: mTLS 자동 (cert 발급/배포/회전 자동)
- ❌ **단점**: 매우 무거움
- 🎯 **추천 시점**: 마이크로서비스 ★★★

### Option F: HSM (Hardware Security Module) for CA key
- ✅ **장점**: CA key 절대 안전 (hardware)
- ❌ **단점**: ₩수백만+
- 🎯 **추천 시점**: 진짜 high-security

### 📊 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 외부 사용자에게 cert | A (Let's Encrypt) |
| 컴플라이언스 강화 | B/F |
| zero-trust 강화 | D/E |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🔒 자기 (`03-network-policy.md`) | TLS는 application layer, NetworkPolicy는 network layer (둘 다 필요) |
| 🏛️ 아키텍처 (`02-kubernetes-design.md`) | cert-manager 배치 |
| 🔧 CI/CD | Harbor cert 신뢰 등록 (containerd) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Edge에서 한 번만 종료해도 되지 않나? 내부는 어차피 우리 네트워크?**
A. (1) cluster 내부도 wire 감청 가능 (악성 Pod, compromised node), (2) 단일 점 의존 = 신뢰 경계가 한 곳뿐 → 그곳 뚫리면 전체. 이중이면 다음 layer가 보호.

**Q2. TLS 두 번 종료하면 latency?**
A. TLS handshake 2배 = ~10ms 추가. 우리 워크로드 QPS 낮아서 무시 가능. 고QPS면 TLS termination 한쪽 (Edge) + cluster 내부는 NetworkPolicy로 격리 + Service Mesh mTLS로 대체.

**Q3. 자체 CA 외부 신뢰 X인데 외부 사용자는?**
A. 옵션 A (Let's Encrypt) 도입. 또는 외부 사용자에게 CA cert 미리 배포 (학습 환경엔 demo 시 cert 경고 무시).

**Q4. cert-manager가 발급한 cert는 어디 저장?**
A. K8s Secret (`tls.crt` + `tls.key`). Ingress가 그 Secret 참조 (`tls.secretName`). cert-manager는 90일 전 자동 갱신 → Secret 업데이트 → Ingress reload.

**Q5. CA key 유출 시?**
A. 큰 사고. 모든 cert 무효, 새 CA + 모든 cert 재발급 + 모든 노드 trust store 교체. → CA key 백업 + 접근 제한 + 감사 로그.

**Q6. 자체 CA 9년 후 catalog 어떻게?**
A. 새 CA 만들고 1년 정도 cross-sign (두 CA 모두 trust) → service별 cert 새 CA로 재발급 → 옛 CA trust 제거. 운영 노력 큼.
