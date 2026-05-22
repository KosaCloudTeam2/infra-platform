# 04. AWS WAF + CloudFront

> ⭐ **한 줄 요약**: **CloudFront**가 외부 진입점 (CDN + DDoS 흡수), **WAF**가 SQL injection/XSS/Bot 차단. AWS Managed Rules로 빠른 시작.

---

## 🎯 우리가 한 선택

### CloudFront
| 항목 | 값 |
|---|---|
| Origin | NLB (kosa-tickets-nlb-...elb.ap-northeast-2.amazonaws.com) |
| Protocol | HTTPS only (HTTP redirect) |
| Cache | Default behavior (static caching) |
| Edge locations | 글로벌 (CloudFront 표준) |

### WAF
| Rule Group | 종류 | 우선순위 |
|---|---|---|
| AWS-AWSManagedRulesCommonRuleSet | Common (XSS, RFI, LFI, SQL injection 일부) | 1 |
| AWS-AWSManagedRulesSQLiRuleSet | SQL injection 깊이 | 2 |
| AWS-AWSManagedRulesKnownBadInputsRuleSet | 알려진 악성 패턴 | 3 |
| ~~RateLimit~~ | ~~2000/5min~~ | ~~제거됨~~ (k6 부하 테스트 차단으로 임시 제거) |

---

## 🔍 고려한 대안

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **AWS WAF + CloudFront (선택)** | AWS 통합, Managed Rules, 빠른 시작 | AWS lock-in, 비용 ($5 + rules) | ★★★★ |
| Cloudflare WAF | 무료 tier 강력, 빠름 | 외부 SaaS 의존 | ★★★★ |
| ModSecurity (HAProxy/Nginx) | 자체 호스팅, 무료 | OWASP rule set 운영 부담 | ★★★ |
| 자체 정책 (HAProxy ACL) | 통제 | rule 작성 부담 | ★★ |

---

## 💡 왜 AWS WAF?

### 1. 🛡️ **Managed Rules = 빠른 시작**
- AWS가 관리하는 rule set (CommonRule, SQLi, KnownBadInputs 등)
- 자동 update (새 위협 추가)
- 직접 rule 작성 안 해도 OWASP Top 10 커버

### 2. 🌐 **CloudFront 통합 = DDoS 흡수**
- CloudFront edge가 트래픽 흡수
- AWS Shield Standard 무료 (DDoS L3/L4)
- WAF가 L7

### 3. 💰 **저렴**
- WAF: $5/Web ACL + $1/rule + $0.60/M req
- 우리 traffic 적어 월 $10~

### 4. ⚡ **빠름**
- CloudFront edge에서 차단 → origin 보호
- latency 영향 최소

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

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| Managed Rules | rule 직접 작성 학습 X |
| DDoS 흡수 | CloudFront 캐시 정책 학습 필요 |
| 빠른 시작 | AWS lock-in (다른 cloud에선 새 도구) |
| false positive 적음 (Managed Rules 검증됨) | rate limit 잘못 (k6 차단) |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **WAF rule false positive** | 정상 트래픽 차단 | rule 일시 disable + investigation |
| **CloudFront 캐시 오염** | 옛 응답 계속 반환 | invalidation (수동) |
| **CloudFront down (매우 드뭄)** | 외부 진입 X | NLB direct 우회 (DNS 변경) |
| **WAF rate limit 너무 낮음** | k6 부하 테스트 차단 (우리 경험) | rate limit 조정 또는 제거 |

---

## 🚀 확장 가능성

### Option A: ⭐ 커스텀 rule 추가
- ✅ **장점**: 우리 앱 특화 (예: specific URL pattern 차단)
- 💰 **비용**: $1/rule/월
- 🎯 **추천 시점**: 특정 공격 패턴 발견

### Option B: Bot Control (별도 Managed Rule)
- ✅ **장점**: 알려진 bot 차단 (scraper, vulnerability scanner)
- 💰 **비용**: $10/월 + $1/M req
- 🎯 **추천 시점**: bot 트래픽 증가

### Option C: AWS Shield Advanced
- ✅ **장점**: $3000/월, 대규모 DDoS 보호 + 24/7 support
- ❌ **단점**: 매우 비쌈
- 🎯 **추천 시점**: 고가치 운영 + DDoS 자주

### Option D: CloudFront 캐시 정책 튜닝
- 현재: default (대부분 캐시 안 됨)
- 확장: static asset (image, CSS, JS)은 cache-Control 1년
- ✅ **장점**: origin 부하 ↓, latency ↓
- 🎯 **추천 시점**: 정적 컨텐츠 많을 때

### Option E: Origin Shield (CloudFront 추가 layer)
- ✅ **장점**: origin 부하 ↓
- 💰 **비용**: 약간 추가
- 🎯 **추천 시점**: cache hit 늘리고 싶을 때

### Option F: 자체 ModSecurity 도입 (AWS 안 쓸 때)
- 🎯 **추천 시점**: 온프레만 운영 시

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 (`architecture/03-aws-hybrid.md`) | CloudFront/WAF는 AWS 외부 진입점 |
| 🔧 CI/CD | (해당 적음) |
| 🔒 자기 (`07-security-policy.md`) | 위협 모델 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. Cloudflare 무료 tier도 강력한데 왜 AWS WAF?**
A. (1) AWS 인프라와 같은 vendor (single console), (2) IAM 통합, (3) CloudWatch 통합 (메트릭). Cloudflare도 좋지만 외부 SaaS 의존. 트래픽 무료라면 Cloudflare 검토 가치 있음.

**Q2. WAF Managed Rules false positive 어떻게?**
A. (1) Count 모드로 시작 (차단 안 하고 메트릭만), (2) 패턴 분석 → 정상이면 exception 추가, (3) 실 차단 모드 전환. 우리는 RateLimit이 k6 부하 테스트 차단 → 제거.

**Q3. CloudFront 캐시 무효화 어떻게?**
A. Console/CLI에서 invalidation 생성: `aws cloudfront create-invalidation --paths "/*"`. 비용: 월 1000 path 무료, 초과 시 $0.005/path.

**Q4. DDoS 시나리오?**
A. AWS Shield Standard (CloudFront/Route53 무료) L3/L4 자동 흡수. L7 (HTTP flood)는 WAF rate limit. 대규모 (Tbps)면 Shield Advanced 검토.

**Q5. WAF 보고서 어디서?**
A. CloudWatch Logs로 sample request 저장. AWS WAF Console에서 blocked/allowed 통계. 우리는 Prometheus도 통합 가능.

**Q6. CloudFront origin이 NLB인데 SSL 종료?**
A. CloudFront ↔ Origin은 우리가 선택 (HTTP only / HTTPS only / Match Viewer). 우리는 HTTP only (NLB cert 직접 관리 회피). CloudFront ↔ Viewer는 HTTPS only.
