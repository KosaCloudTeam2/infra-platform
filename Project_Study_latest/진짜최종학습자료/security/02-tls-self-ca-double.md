# 02. 자체 CA + 이중 TLS (Defense in Depth)

> ⭐ **한 줄 요약**: **자체 CA (KOSA Team2 Internal CA, 10년)를 발급**하고, **TLS를 Edge HAProxy + K8s Ingress에서 두 번 종료**해 내부 트래픽도 wire에서 평문이 안 되게 한다. cert-manager가 service별 cert를 90일 자동 회전한다.

---

## 🎯 우리가 한 선택

### CA 구조

자체 CA를 발급한 이유는 단순하다. **`*.kosa.team2` 같은 내부 도메인은 Let's Encrypt가 안 된다.** Let's Encrypt는 public DNS 검증을 요구하는데 우리 도메인은 public DNS에 없다. 그래서 자체 CA를 만들어 내부에서 신뢰할 수 있는 cert를 발급한다.

| 항목 | 값 |
|---|---|
| Root CA | **KOSA Team2 Internal CA** (자체) |
| 만료 | 10년 (2036) |
| Key 보관 | bastion `~/pki/ca.key` (현재 평문 — 위험) |
| Wildcard cert | `*.kosa.team2` (1년, HAProxy Edge용) |
| Service별 cert | cert-manager가 90일 자동 발급 (`kosa-ca-issuer` ClusterIssuer) |

### 이중 TLS 흐름 — Defense in Depth의 핵심

외부 client가 Grafana에 접속하는 흐름을 보자. TLS가 두 번 종료된다.

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

왜 두 번 종료하는가? **한 layer가 뚫려도 다음 layer가 보호**하기 위함이다. Edge HAProxy가 침해돼서 plaintext로 내부에 트래픽을 보낸다 해도, K8s Ingress 단에서 다시 TLS로 감싸이니 cluster 내부에서 wire 감청은 차단된다.

### 모든 도메인 (5개)에 적용

- ticket.kosa.team2 → ticket-app
- grafana.kosa.team2 → kube-prom-grafana
- argocd.kosa.team2 → argocd-server
- harbor.kosa.team2 → harbor-core
- jenkins.kosa.team2 → jenkins

각 도메인마다 cert-manager가 90일 cert를 자동 발급/갱신한다.

---

## 🔍 고려한 대안들

### CA — 자체 CA vs Let's Encrypt vs Public CA

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **자체 CA (선택)** | 내부 도메인 OK, 무료, 통제 | 외부 신뢰 X (CA cert 배포 필요) | ★★★★ (내부망) |
| Let's Encrypt | 외부 신뢰, 자동 갱신 | DNS-01 필요 (내부 도메인 어려움), public DNS 노출 | ★★ (내부엔 어려움) |
| Public CA (DigiCert 등) | 외부 신뢰 | 비쌈 ($100~/년), 내부 도메인 부적합 | ★ |
| 자체 CA + Let's Encrypt (hybrid) | 내부 자체, 외부 LE | 두 운영 | ★★★★ (이상적) |

Let's Encrypt를 우회해서 자체 CA로 가는 이유는 **`.kosa.team2` 같은 내부 도메인은 public DNS에 없어서 LE가 검증 못함**이다. DNS-01 챌린지로 public TXT를 추가하는 방법이 있긴 하지만 학습 환경엔 과한 작업이다. 자체 CA는 무료고 통제도 자유롭다.

진짜 이상적인 건 **hybrid 패턴** — 내부 도메인은 자체 CA, 외부 노출 도메인은 Let's Encrypt. 우리도 Phase 6에서 외부 도메인 추가 시 LE 도입 검토할 예정이다.

### TLS 종료 위치 — Edge only vs Ingress only vs 이중 (선택)

| 대안 | 장점 | 단점 |
|---|---|---|
| **이중 (Edge + Ingress) 선택** | 내부 트래픽도 암호화, cert 회전 독립 | TLS 핸드셰이크 2배 |
| Edge only | 단순 | 내부 평문 (cluster 내부 tap 위험) |
| Ingress only | 단순 | Edge 거치는 동안 평문 (DMZ 위험) |

Edge only면 외부 → Edge HAProxy까지는 암호화되는데, Edge에서 K8s Ingress까지는 평문. 내부 네트워크가 tap 당하면 인증 정보가 노출된다. Ingress only는 반대로 외부 → K8s Ingress까지가 평문. DMZ가 위험. **둘 다 종료해야 양쪽이 모두 안전**하다.

### Cert 자동화 — cert-manager vs manual vs Vault PKI

| 대안 | 장점 | 단점 |
|---|---|---|
| **cert-manager (선택)** | K8s native, ClusterIssuer, 자동 갱신 | K8s만 (외부 cert X) |
| Manual | 통제 | 만료 risk, 갱신 부담 |
| HashiCorp Vault PKI | 강력, 동적 | Vault 운영 부담 |

cert-manager는 K8s에서 cert 발급/갱신을 declarative하게 만든다. ClusterIssuer 한 번 설정하면 Ingress annotation 한 줄로 각 service의 cert가 자동 발급되고 90일 전 자동 갱신된다. **운영 부담이 거의 0**이다.

---

## 💡 왜 자체 CA + 이중 TLS?

### 1. 이중 TLS = Defense in Depth

> 🔥 **핵심**: Edge가 뚫려도 내부 평문이 아니다. 한 layer 무력화돼도 다음이 보호.

cluster 내부도 wire에서 암호화돼 있어 악성 Pod이나 침해된 노드에서 다른 service의 트래픽을 감청해도 cleartext가 아니다. 10G NIC tap/감청 위험을 차단하는 의미가 크다.

### 2. 내부 도메인은 Let's Encrypt 안 된다

`.kosa.team2`는 public DNS에 없어 LE 검증 불가. DNS-01에 public TXT 추가하는 방법은 있지만 학습 환경엔 과하다. 자체 CA가 합리적이다.

### 3. 무료

DigiCert wildcard cert는 연 $200+. 자체 CA는 openssl 한 명령으로 만든다. 10년 만료라 9년에 한 번 catalog만 잡으면 운영 부담 거의 0.

### 4. cert-manager 자동화

ClusterIssuer 한 번 설정 → 모든 service cert 자동 90일 회전. Ingress annotation 한 줄 (`cert-manager.io/cluster-issuer: kosa-ca-issuer`)로 cert 발급 자동.

### 5. 학습 가치

PKI를 깊이 다뤄볼 수 있다. CA chain, cert 회전, trust store 같은 보안 실무 경험은 어디서 사기 어렵다.

---

## 💰 비용 분석

| 항목 | 비용 |
|---|---|
| 자체 CA (openssl) | 무료 |
| cert-manager (K8s) | 무료 (자원 ~100MB) |
| Wildcard *.kosa.team2 cert | 무료 (자체 발급) |
| 운영 부담 | 9년에 한 번 CA 갱신 + 가끔 cert manual 갱신 |

DigiCert wildcard 연 $200 회피 + cert-manager 자동화로 운영 부담 거의 0.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 무료 + 통제 | 외부 신뢰 X (브라우저 cert 경고) |
| 내부 도메인 가능 | 외부 client에 CA cert 배포 부담 |
| 이중 TLS 보안 | TLS 핸드셰이크 2배 (성능 영향 미미) |
| cert-manager 자동화 | cert-manager 운영 부담 |
| 9년 만료 | 진짜 운영엔 catalog 필요 |

가장 큰 trade-off는 **외부 client가 우리 CA를 모른다**는 점이다. 외부에서 https://grafana.kosa.team2 접속하면 cert 경고가 뜬다. 학습 환경엔 cert 경고를 무시하고 진행하지만, 진짜 외부 사용자에게 service 제공하려면 (1) 우리 CA cert를 client에 배포, (2) 외부 도메인엔 Let's Encrypt 도입 같은 hybrid 패턴이 필요하다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **자체 CA 만료 (10년)** | 모든 cert 망가짐 | 9년 catalog로 사전 회전 |
| **CA key 손실/유출** | 새 CA 만들고 모든 cert 재발급 + 모든 노드 trust 교체 | bastion key 백업 + KMS 등 |
| **cert-manager 죽음** | 새 cert 발급 안 됨 (기존 cert는 OK) | Pod 재시작 |
| **wildcard cert 만료 (1년)** | Edge HAProxy 죽음 | catalog 11개월 후 갱신 |
| **service cert 만료 (90일)** | 자동 갱신 (cert-manager) | 자동 |

가장 critical한 시나리오는 **CA key 유출**이다. 그 key로 가짜 cert를 발급할 수 있어 MITM 공격이 가능해진다. 발생 시 새 CA 만들고 모든 cert 재발급 + 모든 노드 trust store 교체 → ★★★★★ 작업. 그래서 CA key 백업 + 접근 제한 + 감사 로그가 중요하다.

자체 CA 10년 만료가 그 다음 critical인데, 9년 catalog로 사전 회전하면 안전. cert-manager 자동 갱신은 사고 시 일시적 영향이고 Pod 재시작으로 회복 가능.

---

## 🚀 확장 가능성

### Option A: ⭐ Let's Encrypt 추가 (외부 도메인)

현재 자체 CA로 `*.kosa.team2`만 발급한다. 외부 도메인 (예: ticket.caffeinism.cloud) 노출 시점엔 LE로 정식 cert가 필요. cert-manager에 LE ClusterIssuer 추가 + DNS-01 (Route 53) 인증.

- 🎯 **추천 시점**: 외부 사용자 service 제공

### Option B: HashiCorp Vault PKI

동적 cert 발급, 강력한 audit, key 회전. Vault 운영 부담이 크지만 진짜 컴플라이언스급에서 가치 ↑.

- 🎯 **추천 시점**: 컴플라이언스 강화

### Option C: cert key 회전 정책

현재는 cert만 90일 회전, key는 그대로 재사용. cert-manager 옵션으로 key도 함께 회전 가능. 보안 강화.

### Option D: mTLS (양방향 인증)

현재는 server cert만 (client는 익명). 확장으론 client cert도 요구해서 Pod ↔ Pod 양방향 인증. 운영 복잡 (cert 분배)이 크지만 zero-trust 강화 가능.

### Option E: Service Mesh (Istio/Linkerd) — 자동 mTLS

mTLS의 cert 발급/배포/회전을 모두 자동화. 매우 무거운 운영 부담이지만 모든 service 간 통신이 자동 mTLS화된다.

### Option F: HSM (Hardware Security Module) for CA key

CA key를 hardware에 가두면 절대 안전. ₩수백만+ 비용. high-security 환경에서나.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 외부 사용자 cert | A (Let's Encrypt) |
| 컴플라이언스 강화 | B/F |
| zero-trust 강화 | D/E |

---

## 🔗 다른 파트와의 연결

이중 TLS는 application layer 보안이고, NetworkPolicy (`03-network-policy.md`)는 network layer 보안이다. 둘 다 zero-trust의 layer를 구성한다. 아키텍처 측면에선 cert-manager 배치 (`architecture/02-kubernetes-design.md`)가 관련되고, CI/CD에선 Harbor cert 신뢰 등록 (containerd 설정)이 중요하다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Edge에서 한 번만 종료해도 되지 않나요? 내부는 어차피 우리 네트워크 아닌가요?**

A. 두 가지 이유로 부족합니다. **첫째, cluster 내부도 wire 감청이 가능**합니다 (악성 Pod, compromised node, 10G NIC tap). **둘째, 단일 점 의존 = 신뢰 경계가 한 곳뿐**이라 그곳 뚫리면 전체 노출. 이중이면 다음 layer가 보호 (Defense in Depth).

**Q2. TLS 두 번 종료하면 latency가 크지 않나요?**

A. **TLS handshake 2배 = ~10ms 추가**입니다. 우리 워크로드 QPS가 낮아 무시 가능한 수준입니다. 고QPS 환경이면 한쪽 (Edge)만 종료 + cluster 내부는 NetworkPolicy로 격리 + Service Mesh mTLS로 대체하는 패턴도 가능합니다.

**Q3. 자체 CA 외부 신뢰 X인데 외부 사용자는 어떻게요?**

A. 두 가지 옵션입니다. **Option A (Let's Encrypt) 도입** — 외부 도메인엔 LE cert. **외부 사용자에게 CA cert 미리 배포** — 노트북/모바일에 우리 CA를 trust로 등록. 학습 환경에선 demo 시 cert 경고 무시로 진행합니다.

**Q4. cert-manager가 발급한 cert는 어디 저장되나요?**

A. **K8s Secret으로 저장** (`tls.crt` + `tls.key`). Ingress가 그 Secret을 참조 (`tls.secretName`)하고, cert-manager는 90일 전 자동으로 새 cert 발급해서 Secret을 업데이트합니다. Ingress가 그걸 자동으로 reload합니다.

**Q5. CA key 유출 시 어떻게 대응하나요?**

A. **★★★★★ 사고**입니다. 절차: (1) 모든 cert 즉시 무효 선언, (2) 새 CA 발급, (3) 모든 service cert 재발급 (cert-manager 자동), (4) 모든 노드 trust store 교체 (자체 CA cert 배포), (5) 외부 client에도 새 CA cert 배포. 1주+ 작업이라 CA key 보호가 최우선입니다.

**Q6. 자체 CA 9년 후 catalog는 어떻게요?**

A. **새 CA 만들고 1년 정도 cross-sign** (두 CA 모두 trust) → service별 cert를 새 CA로 재발급 → 옛 CA trust 제거. 운영 노력이 ★★★★ 큽니다. 그래서 9년 catalog로 사전 준비 + 새 CA 도입 절차를 명문화해 두는 게 정석입니다.
