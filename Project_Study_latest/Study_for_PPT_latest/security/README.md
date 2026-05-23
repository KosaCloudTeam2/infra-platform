# 🔒 보안 파트 — README

> 이 폴더는 **pfSense + TLS + NetworkPolicy + WAF + RBAC + 정책 + Backup/DR** 등 모든 보안 결정을 다룸.

---

## 📚 문서 목록

| # | 문서 | 핵심 토픽 |
|---|---|---|
| 01 | `01-pfsense-firewall.md` | pfSense 방화벽 + DNS + IPsec |
| 02 | `02-tls-self-ca-double.md` | 자체 CA + 이중 TLS + cert-manager |
| 03 | `03-network-policy.md` | K8s zero-trust NetworkPolicy |
| 04 | `04-aws-waf-cloudfront.md` | AWS WAF + CloudFront 외부 보호 |
| 05 | `05-secrets-rbac.md` | K8s Secret + RBAC + ServiceAccount |
| 06 | `06-burst-trigger-security.md` | webhook 인증 (현재 미구현 + 개선) |
| 07 | `07-security-policy.md` | 정책/거버넌스 (zero-trust, least privilege 등) |
| 08 | `08-backup-dr-policy.md` | ⭐ **백업 + DR 정책** (시나리오 기반) |

---

## 🎯 보안 담당이 마스터해야 할 8가지

1. **pfSense 이중 역할 (방화벽 + DNS + VPN)** → 01
2. **이중 TLS 왜?** → 02
3. **zero-trust 구현 한계 (ticket-app만)** → 03
4. **WAF Managed Rules vs Custom** → 04
5. **Secret 평문 base64 위험 + 개선** → 05
6. **webhook 인증 어떻게 추가?** → 06
7. **보안 정책 5원칙** → 07
8. **Backup/DR 시나리오 (PXC/Ceph/etcd)** → 08

---

## 🤝 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 아키텍처 | pfSense, 이중 TLS, NetworkPolicy 모두 아키텍처와 결합 |
| 💾 데이터 | DB 데이터 보호, 백업 암호화, replication 인증 |
| 🔧 CI/CD | Jenkins credentials, image scan, ArgoCD RBAC |

→ 보안은 cross-cutting의 가장 강한 영역.

---

## 🧪 자가 테스트

```
□ pfSense 방화벽 룰 어디서 확인?
□ Edge HAProxy cert와 K8s Ingress cert 차이?
□ NetworkPolicy 적용된 ns와 안 된 ns 차이?
□ AWS WAF Managed Rules 종류?
□ K8s Secret 평문 위험 어떻게 개선?
□ AlertManager webhook 누가 인증?
□ 보안 정책 5원칙은?
□ etcd 사고 시 복구 절차?
□ PXC 데이터 손실 시 복구?
```
