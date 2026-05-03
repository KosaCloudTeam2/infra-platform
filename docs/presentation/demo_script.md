# 시연 스크립트

## 1. 자동 배포 시연

> "main 브랜치에 변경 사항이 반영되면 GitHub Actions가 Docker 이미지를 빌드하고 ECR에 업로드합니다.
> 이후 ECS Task Definition을 갱신하고 Service를 업데이트합니다."

확인 화면

- GitHub Actions workflow
- ECR image tag
- ECS Service deployment
- ALB URL

## 2. 장애 복구 시연

> "잘못된 배포가 발생하면 Health Check가 실패하고 ECS는 정상 Task로 서비스를 유지하거나 이전 Task
> Definition으로 롤백할 수 있습니다."

확인 화면

- ECS Service Events
- Target Group Health
- CloudWatch Logs
- 복구 후 ALB 응답

## 3. 보안 설명

> "배포 파이프라인은 장기 Access Key를 사용하지 않고 GitHub OIDC로 임시 권한을 받아 AWS에
> 접근합니다. 애플리케이션은 ALB를 통해서만 접근되고, Task는 Private Subnet에서 실행됩니다."

확인 화면

- IAM Role trust policy
- Security Group inbound rule
- WAF association
