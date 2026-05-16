# EKS Cloud Bursting with Karpenter Terraform 초안

> Status: Unverified

관련 문서:

- `../eks-cloud-bursting-with-karpenter.md`

이 폴더는 `eks-cloud-bursting-with-karpenter.md` 구현을 Terraform으로 옮기기 위한 **초안**임.

## 자동화 대상(초안)

- EKS/OIDC/IRSA 준비
- Karpenter Helm 설치에 필요한 IAM
- EventBridge Scheduler + Lambda (baseline MNG pre-scale)

## 운영 원칙

- 검증 전 `infra/` 승격 금지
- 사용자 실검증 후 Verified 시 승격 후보 선정
