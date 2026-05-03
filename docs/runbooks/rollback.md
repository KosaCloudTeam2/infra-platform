# 롤백 Runbook

## 1. 롤백 대상

- 배포 후 ALB Health Check 실패
- ECS Task 반복 재시작
- 앱 5xx 증가
- 주요 기능 응답 실패

## 2. 자동 롤백

ECS Deployment Circuit Breaker가 활성화되어 있으면 배포 실패 시 이전 안정 버전으로 자동 복구됨.

확인 항목

- ECS Service Events
- Deployment `rolloutState`
- CloudWatch Logs 오류 메시지

## 3. 수동 롤백 절차

1. 이전 Task Definition revision 확인
2. ECS Service를 이전 revision으로 업데이트
3. Target Group Health Check 확인
4. ALB URL 응답 확인

```powershell
aws ecs update-service `
  --cluster cloud-infra-dev `
  --service cloud-infra-app `
  --task-definition cloud-infra-app:<PREVIOUS_REVISION> `
  --region ap-northeast-2
```

## 4. 발표용 롤백 시연

- 실패 이미지 또는 잘못된 환경 변수로 배포
- Health Check 실패 확인
- 이전 Task Definition으로 롤백
- 정상 응답 복구 확인

## 5. 사후 기록

- 실패 원인
- 감지 지표
- 복구 시간
- 재발 방지 조치
