# ADR-005: GitHub Actions OIDC 기반 배포

## 상태

Accepted

## 날짜

2026-05-03

## 배경

GitHub Actions에서 AWS에 배포하려면 AWS 권한이 필요함. 장기 Access Key를 GitHub Secrets에 저장하면
유출 위험과 키 회전 부담이 생김.

## 결정

GitHub Actions는 OIDC(OpenID Connect)를 통해 AWS IAM Role을 Assume함. GitHub Secrets에는
`AWS_DEPLOY_ROLE_ARN`처럼 민감도가 낮은 설정만 저장하고, 장기 AWS Access Key는 저장하지 않음.

## 대안

- GitHub Secrets에 AWS Access Key 저장
- 로컬에서 수동 배포
- 별도 CI 서버 운영

## 영향

장점:

- 장기 Access Key 없이 배포 가능
- IAM Trust Policy에서 저장소 단위로 접근 제한 가능
- 보안 발표 포인트가 명확함

감수할 점:

- GitHub OIDC Provider와 IAM Role 설정이 필요함
- `github_repository` 값을 실제 저장소로 정확히 제한해야 함
- `iam:PassRole` 범위 관리가 필요함

## 관련 문서

- [Security Policy](../../05_security_policy.md)
- [GitHub Setup](../../11_github_setup.md)
- [Deployment Runbook](../../runbooks/deployment.md)
