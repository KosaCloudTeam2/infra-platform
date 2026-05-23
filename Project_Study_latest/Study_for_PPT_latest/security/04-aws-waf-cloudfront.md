# 04. AWS WAF + CloudFront

> ⭐ **한 줄 요약**: **CloudFront가 외부 진입점**으로 DDoS를 흡수하고 캐싱하고, **AWS WAF가 SQL injection/XSS/Bot을 차단**한다. AWS Managed Rules로 빠르게 시작했고, 우리 트래픽 규모엔 월 ~$10 정도다.

---

## 🎯 우리가 한 선택

CloudFront는 글로벌 CDN으로 AWS의 edge location에서 트래픽을 받는다. 외부 사용자는 CloudFront를 통해 우리 NLB로 도달하고, 그 사이에 AWS WAF가 위협 패턴을 차단한다.

### CloudFront

| 항목 | 값 |
|---|---|
| Origin | NLB (kosa-tickets-nlb-...elb.ap-northeast-2.amazonaws.com) |
| Protocol | HTTPS only (HTTP redirect) |
| Cache | Default behavior (static caching) |
| Edge locations | 글로벌 (CloudFront 표준) |

### WAF Rule Groups

AWS Managed Rules를 활용해서 위협 패턴별 rule group을 적용한다.

| Rule Group | 종류 | 우선순위 |
|---|---|---|
| AWS-AWSManagedRulesCommonRuleSet | Common (XSS, RFI, LFI, SQL injection 일부) | 1 |
| AWS-AWSManagedRulesSQLiRuleSet | SQL injection 깊이 | 2 |
| AWS-AWSManagedRulesKnownBadInputsRuleSet | 알려진 악성 패턴 | 3 |
| ~~RateLimit~~ | ~~2000/5min~~ | ~~제거됨~~ (k6 부하 테스트 차단으로 임시 제거) |

RateLimit rule을 처음에 추가했는데 k6 부하 테스트가 차단되어 임시 제거했다. 진짜 운영급은 RateLimit이 필수지만 우리 학습 환경엔 부하 테스트 우선이라 제거 상태.

---

## 🔍 고려한 대안

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **AWS WAF + CloudFront (선택)** | AWS 통합, Managed Rules, 빠른 시작 | AWS lock-in, 비용 | ★★★★ |
| Cloudflare WAF | 무료 tier 강력, 빠름 | 외부 SaaS 의존 | ★★★★ |
| ModSecurity (HAProxy/Nginx) | 자체 호스팅, 무료 | OWASP rule set 운영 부담 | ★★★ |
| 자체 정책 (HAProxy ACL) | 통제 | rule 작성 부담 | ★★ |

### AWS WAF vs Cloudflare WAF

Cloudflare WAF가 사실 무료 tier가 더 강력하고 글로벌 latency도 ↓이다. 우리가 AWS WAF를 선택한 이유는 **이미 AWS 인프라를 쓰고 있어 같은 vendor + 통합 console 관리**가 편하다는 점이다. CloudWatch와 통합 + IAM 통합도 자연스럽다.

진짜 비용 + 성능 최우선이면 Cloudflare가 매력적이다. 다만 외부 SaaS 의존이 추가된다.

### ModSecurity 직접

ModSecurity는 OWASP Core Rule Set을 HAProxy/Nginx에 통합해서 자체 호스팅하는 옵션. **비용 0**이지만 rule 운영 부담이 크다. 새 위협 발견 시 직접 rule 작성/업데이트해야 한다. AWS Managed Rules는 AWS가 자동 update하니 운영 부담 ↓.

---

## 💡 왜 AWS WAF?

### 1. Managed Rules = 빠른 시작

AWS가 관리하는 rule set이라 직접 rule 작성 안 해도 OWASP Top 10이 커버된다. 새 위협 발견 시 AWS가 자동 update. **운영 부담 거의 0**.

### 2. CloudFront 통합 = DDoS 흡수

CloudFront edge가 트래픽을 받아주니 DDoS 트래픽이 우리 origin까지 안 도달한다. AWS Shield Standard (무료) + WAF로 L3/L4/L7 모두 보호.

### 3. 비용 저렴

월 $10 정도. WAF Web ACL $5 + rule $1 × 3개 + request 약간. 우리 트래픽 규모엔 부담 없는 수준.

### 4. 빠름 (edge 차단)

CloudFront edge에서 차단하니 origin까지 도달하지 않는다. latency 영향 최소.

---

## 💰 비용 분석

| 항목 | 단가 | 우리 사용 | 월 비용 |
|---|---|---|---|
| WAF Web ACL | $5/월 | 1 | $5 |
| Managed Rule Group (3개) | $1/월 × 3 | 3 | $3 |
| WAF Request | $0.60/1M | ~10K | <$1 |
| CloudFront 데이터 OUT (Asia) | $0.085/GB | ~5GB | $0.4 |
| CloudFront 요청 | $0.0075/10K | ~10K | <$1 |
| **합계** | | | **~$10/월** |

진짜 운영급 트래픽 (수백만 request/일)이면 비용이 누적되지만, 학습 환경엔 $10 수준이라 부담 없다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| Managed Rules | rule 직접 작성 학습 X |
| DDoS 흡수 | CloudFront 캐시 정책 학습 필요 |
| 빠른 시작 | AWS lock-in (다른 cloud에선 새 도구) |
| false positive 적음 | rate limit 잘못으로 k6 차단 |

가장 큰 trade-off는 **AWS lock-in**이다. 다른 cloud (GCP, Azure)로 옮기면 WAF + CloudFront 모두 다른 도구로 재구성. 단, S3 API 같은 vendor-neutral 표준이 아니라 vendor-specific service라 lock-in이 본질적이다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **WAF rule false positive** | 정상 트래픽 차단 | rule 일시 disable + investigation |
| **CloudFront 캐시 오염** | 옛 응답 계속 반환 | invalidation (수동) |
| **CloudFront down** | 외부 진입 X | NLB direct 우회 (DNS 변경) |
| **WAF rate limit 너무 낮음** | k6 부하 테스트 차단 (우리 경험) | rate limit 조정 또는 제거 |

CloudFront 자체가 down되는 경우는 매우 드물지만 (AWS의 critical 인프라), 만약 발생하면 NLB direct로 우회하면 된다. WAF rule false positive가 더 흔한 함정인데, count 모드로 먼저 검증 후 활성화하는 게 안전하다.

---

## 🚀 확장 가능성

### Option A: ⭐ 커스텀 rule 추가

특정 공격 패턴 발견 시 (예: 우리 앱 특정 URL 공격) 커스텀 rule 추가. $1/rule/월. Managed Rules로 못 막는 specific case에 효과적.

### Option B: Bot Control (별도 Managed Rule)

알려진 bot 차단 (scraper, vulnerability scanner 등). $10/월 + request 비용. 트래픽 분석해서 bot 비중 높으면 가치.

### Option C: AWS Shield Advanced

$3000/월. 대규모 DDoS 보호 + 24/7 support + DDoS 비용 보호. 진짜 critical 운영 + DDoS 자주 발생 시.

### Option D: CloudFront 캐시 정책 튜닝

현재 default 정책. static asset (image, CSS, JS)에 cache-Control 1년 등 설정하면 origin 부하 ↓ + latency ↓. 정적 컨텐츠 많은 환경에서 가치.

### Option E: Origin Shield

CloudFront의 추가 cache layer. cache hit rate ↑ + origin 부하 ↓. cache hit 늘리고 싶을 때.

### Option F: 자체 ModSecurity 도입

AWS 안 쓰고 온프레만 운영 시 검토.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 특정 공격 발견 | A (커스텀 rule) |
| Bot 트래픽 ↑ | B (Bot Control) |
| 정적 컨텐츠 많음 | D (캐시 튜닝) |

---

## 🔗 다른 파트와의 연결

이 외부 보호 layer는 `architecture/03-aws-hybrid.md`의 AWS 측 진입점 구조와 직결된다. CI/CD 측면에선 거의 무관하지만, 보안 정책 (`07-security-policy.md`)의 위협 모델과 연결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Cloudflare 무료 tier도 강력한데 왜 AWS WAF인가요?**

A. 세 가지 이유입니다. **AWS 인프라와 같은 vendor** (single console + IAM 통합), **CloudWatch 메트릭 통합**, **이미 AWS Stack이라 추가 학습 ↓**. Cloudflare도 좋지만 외부 SaaS 의존 추가됩니다. 트래픽 무료 우선이면 Cloudflare 검토 가치 있습니다.

**Q2. WAF Managed Rules false positive 어떻게 처리하나요?**

A. 세 단계입니다. **Count 모드로 시작** (차단 안 하고 메트릭만 수집) → **패턴 분석** (정상이면 exception 추가) → **실 차단 모드 전환**. 우리는 RateLimit가 k6 부하 테스트를 차단해서 제거했습니다. 진짜 운영은 RateLimit 필수지만 우리 환경엔 부하 테스트 우선이었습니다.

**Q3. CloudFront 캐시 무효화는 어떻게요?**

A. **Console/CLI에서 invalidation 생성**: `aws cloudfront create-invalidation --paths "/*"`. 비용은 월 1000 path 무료, 초과 시 $0.005/path. 잘못된 응답을 일시 차단할 때 유용합니다.

**Q4. DDoS 시나리오에선 어떻게 대응하나요?**

A. **AWS Shield Standard** (CloudFront/Route53 무료)가 L3/L4 자동 흡수합니다. L7 (HTTP flood)는 WAF rate limit + Bot Control로 차단. 대규모 (Tbps급) DDoS면 Shield Advanced ($3000/월) 검토. 학습 환경엔 Standard로 충분합니다.

**Q5. WAF 보고서/통계는 어디서 봐요?**

A. **CloudWatch Logs로 sample request 저장** + AWS WAF Console에서 blocked/allowed 통계 시각화. Prometheus 통합도 가능합니다 (AWS metric을 remote_write).

**Q6. CloudFront origin이 NLB인데 SSL 종료는 어디서요?**

A. 두 layer로 분리합니다. **CloudFront ↔ Viewer는 HTTPS only**. **CloudFront ↔ Origin은 우리가 선택** (HTTP only / HTTPS only / Match Viewer). 우리는 HTTP only로 설정해 NLB cert 직접 관리를 회피했습니다. CloudFront가 client 측 TLS를 종료하고, origin 측은 internal AWS 네트워크라 plaintext OK라 판단했습니다.
