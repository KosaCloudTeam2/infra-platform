# AWS NLB-EC2-VPN-OnPrem 자동화 초안

> Status: Unverified

관련 문서:

- `../aws-nlb-ec2-vpn-onprem-prerequisites.md`
- `../aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`

이 폴더는 **미검증(terraform/ansible) 초안**을 보관함.

## 구성

- `terraform/`: VPC/NLB/EC2/VPN/Route53 자동화 초안
- `ansible/`: HAProxy/WireGuard 설정 자동화 초안

## 운영 원칙

- 사용자 실행 검증 전까지 `infra/` 승격 금지
- 검증 완료 후 필요한 파일만 `infra/`로 이동
- 이동 시 문서 경로/명령어/change_log 동시 업데이트
