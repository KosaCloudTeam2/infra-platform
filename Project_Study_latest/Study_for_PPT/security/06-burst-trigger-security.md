# 06. Burst Trigger 보안 (webhook 인증)

> ⭐ **한 줄 요약**: 현재 AlertManager → Lambda webhook **무인증** (학습 환경). 위협: 누구나 webhook 호출 시 false burst → 비용 발생. 개선: API Gateway IAM/API key 또는 HMAC.

---

## 🎯 현재 상태

| 항목 | 값 |
|---|---|
| Webhook URL | https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com/ |
| 인증 | **없음** (누구나 호출 가능) |
| Lambda IAM | route53:ChangeResourceRecordSets 권한 |
| 위협 | 외부자가 URL 알면 false burst 발사 → AWS 비용 |

---

## 🔍 위협 모델

| 시나리오 | 확률 | 영향 |
|---|---|---|
| URL 유출 (Git에 commit 등) | 중 | EKS Spot 노드 생성 (월 $30~) |
| 무차별 호출 (bot) | 낮 | Lambda 호출 비용 ($0.2/M) + Spot 생성 |
| AlertManager 사칭 | 낮 | 가짜 burst trigger |

---

## 💡 개선 옵션 (Phase 6 권장)

### Option A: ⭐ API Gateway API Key
- ✅ **장점**: 단순, AWS native
- 작업:
  ```
  1. API Gateway에 Usage Plan + API Key 생성
  2. AlertManager webhook headers에 x-api-key 추가
  3. helm values 업데이트
  ```
- ⏱️ **작업**: 2시간
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option B: HMAC Signature
- ✅ **장점**: payload 무결성 + 인증
- 작업:
  ```
  1. AlertManager → Lambda payload HMAC-SHA256
  2. Lambda가 verify
  3. shared secret = K8s Secret
  ```
- 🎯 **추천 시점**: A 후 강화

### Option C: IAM SigV4 (AWS native auth)
- ✅ **장점**: 가장 안전, audit ★★★★★
- ❌ **단점**: AlertManager가 SigV4 안 지원 (proxy 필요)
- 🎯 **추천 시점**: 진짜 production

### Option D: WAF rule (IP 제한)
- ✅ **장점**: 단순
- ❌ **단점**: 우리 온프레 IP 변동 (강의장 NAT)
- 🎯 **추천 시점**: 고정 IP 환경

### Option E: VPN 안에서만 호출 가능 (Lambda → 온프레)
- ✅ **장점**: 외부 접근 불가
- ❌ **단점**: Lambda → 온프레 webhook은 패턴 어려움
- 🎯 **추천 시점**: 거의 안 함

---

## 💰 비용

| 옵션 | 추가 비용 |
|---|---|
| A (API Key) | 0 |
| B (HMAC) | 0 |
| C (IAM SigV4) | 0 (proxy 필요시 약간) |

---

## ⚠️ 만약 false trigger 발사 시

| 영향 | 비용 | 회복 |
|---|---|---|
| EKS Spot 노드 생성 | $0.03/h × 1h = $0.03 | resolve 후 자동 삭제 |
| Route 53 weight 변경 | 0 | 자동 원복 (alert resolved) |
| 트래픽 분산 (정상 사용자 영향 X) | 0 | DNS TTL 60초 후 정상 |

→ **실제 피해 적음** (수십센트). 단, 반복 호출 시 누적.

---

## 🚀 권장 순서

1. **Phase 6 #1**: Option A (API Key) — 즉시 차단
2. **Phase 6 #2**: Option B (HMAC) — 무결성 강화
3. **Phase 7**: Option C (SigV4) — 진짜 운영

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 (`architecture/04-burst-architecture.md`) | webhook이 burst trigger의 시작 |
| 🔒 자기 (`05-secrets-rbac.md`) | API Key를 K8s Secret으로 |
| 🔧 CI/CD | Lambda 코드 배포 시 인증 로직 추가 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. webhook 무인증인 거 알고 한 거?**
A. 학습 환경 단순화 + 데모 우선. Phase 6 우선 작업. 실제 피해는 false burst 시 $0.03/h 정도라 즉시 보안 사고 아님.

**Q2. 어느 인증 방식 추천?**
A. **API Key가 가장 빠름** (2시간). HMAC은 무결성 추가 (페이로드 변조 방어). 진짜 운영은 SigV4 (audit ★★★★★).

**Q3. webhook URL 어떻게 보호?**
A. (1) Git에 commit X (helm.values에서 secret reference), (2) 로그에 출력 X, (3) 정기 회전 (API Gateway URL은 stable이라 회전 어려움 → API Key 회전이 대안).

**Q4. AlertManager가 SigV4 지원하나?**
A. **안 함** (HTTP basic auth, bearer token만). SigV4 쓰려면 Lambda 앞에 proxy (Cognito 등) 또는 AlertManager → 자체 proxy → Lambda.

**Q5. AlertManager 자체가 침해되면?**
A. webhook 무한 호출 가능 (Lambda + EKS 비용 폭발). 완화: AWS Budget alert + Lambda concurrency limit + CloudWatch alarm.
