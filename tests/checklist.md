# 테스트 체크리스트

## 로컬

- [ ] `docker build -t cloud-infra-app:local ./app`
- [ ] `docker run --rm -p 8080:8080 cloud-infra-app:local`
- [ ] `scripts/smoke-test.ps1 -BaseUrl http://localhost:8080`

## Terraform

- [ ] `terraform fmt -recursive`
- [ ] `terraform validate`
- [ ] `terraform plan -var-file=env/dev.tfvars`

## AWS

- [ ] ALB DNS 접속
- [ ] Target Group Health 정상
- [ ] ECS Service Desired/Running Count 일치
- [ ] CloudWatch Logs 기록 확인
- [ ] GitHub Actions 배포 성공
