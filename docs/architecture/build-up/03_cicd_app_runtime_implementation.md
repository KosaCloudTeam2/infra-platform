# 03 CI/CD / App Runtime Implementation

담당: 팀원 4

## 1. 목표

GitHub Actions OIDC 기반으로 Docker 이미지를 ECR에 push하고 ECS Fargate Service를 갱신함. 앱은 ALB
뒤의 App Private Subnet에서 실행되고 ProxySQL endpoint를 통해 DB에 연결함.

## 2. 사전 조건

- `AWS_DEPLOY_ROLE_ARN` GitHub Secret 등록
- Terraform output에서 ECR repository, ECS Cluster, ECS Service 이름 확인
- `.github/task-definition.json`의 역할명과 Terraform 리소스명이 일치함
- 앱 포트와 ALB Health Check 경로가 `container_port`, `health_check_path`와 일치함
- DB 담당자로부터 ProxySQL endpoint와 Secret 전달 방식 인계

## 3. 구현 순서

1. 로컬 Docker build와 `/health` 응답 확인
2. ECR repository 이름과 GitHub Actions env 값 확인
3. GitHub OIDC Role assume 가능 여부 확인
4. workflow에서 Docker image를 `github.sha`, `latest`로 push
5. Task Definition의 image를 신규 태그로 렌더링
6. ECS Service update 실행
7. ALB Target Group health check 확인
8. 앱 로그가 CloudWatch Logs에 기록되는지 확인
9. 앱에서 ProxySQL endpoint 접속 확인
10. 실패 배포 롤백 절차를 Runbook에 반영

## 4. 로컬 앱 검증

```powershell
docker build -t cloud-infra-app:local ./app
docker run --rm -p 8080:8080 cloud-infra-app:local
```

다른 터미널에서 확인:

```powershell
.\scripts\smoke-test.ps1 -BaseUrl http://localhost:8080
```

## 5. GitHub Actions 검증

확인 항목:

- `Configure AWS credentials` 단계 성공
- `Login to Amazon ECR` 단계 성공
- ECR에 `github.sha` 태그와 `latest` 태그 생성
- `Prepare ECS task definition` 단계에서 AWS Account ID 동적 치환
- `Deploy ECS service` 단계가 stability 대기 후 성공

## 6. ECS 검증

```powershell
aws ecs describe-services `
  --cluster cloud-infra-dev-cluster `
  --services cloud-infra-dev-app `
  --region ap-northeast-2
```

완료 기준:

- `runningCount`가 `desiredCount`와 같음
- 최신 deployment가 `PRIMARY` 상태
- Target Group health가 `healthy`
- ALB URL에서 앱 응답 확인

## 7. 앱-DB 연결 기준

환경변수/Secret 기준:

- `DB_HOST`: ProxySQL private IP 또는 Internal NLB DNS
- `DB_PORT`: `6033`
- `DB_USER`: 앱 전용 계정
- `DB_PASSWORD`: Secrets Manager secret

앱은 PXC 노드 private IP를 직접 참조하지 않음.

## 8. 산출물

- GitHub Actions 실행 결과 캡처
- ECR 이미지 태그 목록
- ECS Service deployment 상태
- ALB Target Group health 결과
- CloudWatch Logs 캡처
- 앱-DB 연결 확인 결과
- 롤백 Runbook 업데이트

## 9. 주의 사항

- GitHub에 AWS Access Key를 저장하지 않음
- `.github/task-definition.json`에 실제 AWS Account ID를 커밋하지 않음
- Day 14 이후에는 자동 배포보다 수동 `workflow_dispatch` 기반 안정화를 우선 검토함
- 실패 배포 시 새 기능 수정이 아니라 이전 정상 Task Definition으로 롤백함
