# 06. Burst Trigger 보안 (webhook 인증)

> ⭐ **한 줄 요약**: **Phase 6에서 Lambda 코드 레벨 token 검증 + URL query string 방식**으로 인증 추가 완료 (2026-05-23). 무인증 호출 401, 올바른 token만 200. 단 token이 git에 평문 노출되는 한계 — 진짜 운영급은 sealed-secrets로 분리 필요.

---

## ✅ 적용된 인증 (2026-05-23)

**최종 방식**: Lambda 코드 안에서 Bearer header 또는 URL query string token 검증.

```python
# Lambda burst-trigger 인증 로직
def _check_auth(event):
    if not WEBHOOK_TOKEN: return True
    # 1. Authorization: Bearer (header)
    auth = (event.get('headers') or {}).get('authorization', '')
    if auth.startswith('Bearer ') and auth[7:] == WEBHOOK_TOKEN: return True
    # 2. ?token=... (query string)
    qs = event.get('queryStringParameters') or {}
    if qs.get('token') == WEBHOOK_TOKEN: return True
    return False
```

**검증 결과 (실측)**:

| 시도 | 응답 |
|---|---|
| 무인증 POST | 401 unauthorized |
| 잘못된 token | 401 unauthorized |
| Bearer header | 200 OK |
| `?token=...` query string | 200 OK |
| AlertManager 실 dispatch | 200, Route 53 weight 자동 변경 |

**원래 계획과 다른 점**: 처음엔 AlertManager `http_config.authorization.Bearer` 사용하려 했으나 **prometheus-operator 0.90.1이 `webhook_configs.http_config` 필드를 generated secret 만들 때 drop**시킴 (operator 버전 호환성 이슈). 우회로 URL query string 방식 채택.

**운영 grade로 가려면**:
1. `alertmanagerSpec.configSecret`으로 우리 secret 직접 사용 (operator 우회)
2. 또는 operator 버전 업그레이드
3. Token을 sealed-secrets / external-secrets로 분리 (현재 git에 평문)

---

## 🎯 처음 상태 (구 설계)

Burst trigger의 인증이 빠져있던 상태. AlertManager가 발사하는 webhook을 누구든 호출할 수 있는 상태였다.

| 항목 | 변경 전 | 변경 후 (2026-05-23) |
|---|---|---|
| Webhook URL | `https://le24sqo79b...amazonaws.com/` | `...amazonaws.com/?token=<64자>` |
| 인증 | **없음** | Bearer header + query string token |
| Lambda IAM | route53:ChangeResourceRecordSets | (변경 없음) |
| 위협 | URL 알면 누구나 호출 → AWS 비용 | token 모르면 401 차단 |

URL은 git commit이나 helm values에 노출돼 있어 사실상 공개 상태였다. 진짜 운영급이면 큰 보안 위험이었다.

---

## 🔍 위협 모델

| 시나리오 | 확률 | 영향 |
|---|---|---|
| URL 유출 (Git에 commit) | 중 | EKS Spot 노드 생성 (월 $30~) |
| 무차별 호출 (bot) | 낮 | Lambda 호출 비용 ($0.2/M) + Spot 생성 |
| AlertManager 사칭 | 낮 | 가짜 burst trigger |

가장 흔한 시나리오는 **URL이 git commit에 노출**되는 케이스다. 우리 환경에선 이미 helm values에 평문으로 박혀있어 git 접근 권한이 있는 사람이면 누구든 URL을 안다. 외부자가 알면 무한 호출로 EKS Spot 노드를 계속 생성시켜 AWS 비용을 발생시킬 수 있다.

실제 피해는 false burst 1시간당 $0.03 정도라 즉시 큰 사고는 아니지만, **반복 호출 시 누적 + AWS budget 초과 위험**이 있다.

---

## 💡 개선 옵션 (Phase 6 권장)

### Option A: ⭐ API Gateway API Key

가장 단순하고 빠른 옵션이다. AWS API Gateway에 Usage Plan + API Key를 생성하고, AlertManager가 webhook 호출 시 `x-api-key` header에 key를 포함시킨다. 잘못된 key면 API Gateway에서 403 응답.

```
작업:
1. API Gateway에 Usage Plan + API Key 생성
2. AlertManager webhook headers에 x-api-key 추가
3. helm values 업데이트
```

- ✅ **장점**: AWS native, 단순, 빠른 적용
- ⏱️ **작업**: 2시간
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option B: HMAC Signature

API Key 위에 무결성 검증을 추가하는 옵션. AlertManager가 webhook payload를 HMAC-SHA256으로 서명하고, Lambda가 그걸 verify. **payload 변조 방어**도 가능. shared secret을 K8s Secret으로 관리.

- ✅ **장점**: payload 무결성 + 인증
- 🎯 **추천 시점**: A 후 강화

### Option C: IAM SigV4 (AWS native auth)

가장 강력하지만 AlertManager가 SigV4 서명을 직접 지원하지 않아서 proxy가 필요하다. 진짜 production grade에서 검토할 옵션.

- ✅ **장점**: AWS native auth, audit ★★★★★
- ❌ **단점**: AlertManager SigV4 미지원 (proxy 필요)
- 🎯 **추천 시점**: 진짜 production

### Option D: WAF rule (IP 제한)

특정 IP만 webhook 호출 허용. 우리 온프레 IP가 변동 (강의장 NAT)이라 부적합. 고정 IP 환경에선 좋은 옵션.

### Option E: VPN 안에서만 호출 가능

Lambda를 온프레로 옮기거나, AlertManager가 VPN 통해서만 호출. 패턴이 어렵다. 거의 안 함.

---

## 💰 비용

| 옵션 | 추가 비용 |
|---|---|
| A (API Key) | 0 |
| B (HMAC) | 0 |
| C (IAM SigV4) | 0 (proxy 필요시 약간) |

모든 옵션이 비용 추가가 거의 없다. **운영 부담 + 보안 강도** trade-off가 진짜 차이다.

---

## ⚠️ 만약 false trigger 발사 시

가장 자주 받는 질문이 "보안 사고 시 진짜 피해가 얼마인가"다. 정량적으로 계산해보자.

| 영향 | 비용 | 회복 |
|---|---|---|
| EKS Spot 노드 생성 | $0.03/h × 1h = $0.03 | resolve 후 자동 삭제 |
| Route 53 weight 변경 | 0 | 자동 원복 (alert resolved) |
| 트래픽 분산 (정상 사용자 영향 X) | 0 | DNS TTL 60초 후 정상 |

→ **실제 피해는 수십센트 수준**이다. 단발 호출은 큰 사고 아니다. 단, **반복 호출 시 누적**이 위험. 1000번 호출이면 $30 정도 비용 발생.

---

## 🚀 권장 순서

Phase 단계별로 차근차근 강화하는 게 합리적이다.

1. **Phase 6 #1**: Option A (API Key) — 즉시 차단 (2시간 작업)
2. **Phase 6 #2**: Option B (HMAC) — 무결성 강화
3. **Phase 7**: Option C (SigV4) — 진짜 운영급

---

## 🔗 다른 파트와의 연결

이 webhook 보안은 burst 아키텍처 (`architecture/04-burst-architecture.md`)의 시작점이라 직결된다. API Key를 K8s Secret으로 관리 (`05-secrets-rbac.md`)하고, Lambda 코드 배포 시 인증 로직 추가는 CI/CD 작업이다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. webhook 무인증인 거 알고 한 건가요?**

A. **학습 환경 단순화 + 데모 우선**입니다. Phase 6 우선 작업으로 명시했고, 실제 피해는 false burst 시 $0.03/h 정도라 즉시 보안 사고는 아니지만 운영 진입 직전 무조건 해야 할 작업입니다.

**Q2. 어느 인증 방식을 추천하나요?**

A. 단계적으로 갑니다. **API Key가 가장 빠릅니다** (2시간). **HMAC은 무결성 추가** (페이로드 변조 방어). 진짜 운영은 **SigV4** (audit ★★★★★). 우리는 API Key부터 시작 + 단계적 강화 패턴이 합리적이라 봅니다.

**Q3. webhook URL을 어떻게 보호하나요?**

A. 세 가지입니다. **Git에 commit 금지** (helm.values에서 secret reference 패턴), **로그에 출력 X**, **정기 회전** (API Gateway URL은 stable이라 회전 어려움 → API Key 회전이 대안). 현재는 helm values에 URL이 평문으로 박혀있는 게 약점입니다.

**Q4. AlertManager가 SigV4를 지원하나요?**

A. **안 합니다 (HTTP basic auth, bearer token만)**. SigV4를 쓰려면 Lambda 앞에 proxy (Cognito 등) 추가 또는 AlertManager → 자체 proxy → Lambda 패턴이 필요합니다. 그래서 API Key가 더 현실적입니다.

**Q5. AlertManager 자체가 침해되면 어떻게 되나요?**

A. **webhook 무한 호출 가능 → Lambda + EKS 비용 폭발** 위험이 있습니다. 완화책은 (1) **AWS Budget alert**로 비용 임계치 알람, (2) **Lambda concurrency limit** (동시 호출 수 제한), (3) **CloudWatch alarm으로 비정상 호출 패턴 감지**. AlertManager 자체 보안 (K8s RBAC, NetworkPolicy)도 같이 가야 합니다.
