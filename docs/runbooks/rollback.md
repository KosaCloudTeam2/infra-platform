# 롤백 Runbook

## 1. 롤백 대상

- 배포 후 ALB Health Check 실패
- Kubernetes Pod 또는 AWS burst 앱 반복 재시작
- 앱 5xx 증가
- 주요 기능 응답 실패

## 2. 자동 롤백

Argo CD auto-sync와 self-heal은 발표 전 안정화 이후에만 활성화함. MVP 기본값은 수동 sync와 명시적
롤백임.

확인 항목

- Argo CD Application `Sync`/`Health`
- Kubernetes Deployment rollout 상태
- CloudWatch Logs 오류 메시지

## 3. 수동 롤백 절차

1. 이전 정상 Git revision 또는 image tag 확인
2. Kubernetes manifest의 image tag를 이전 값으로 복원
3. Argo CD Application sync 실행
4. ALB URL 응답 확인

```powershell
kubectl rollout undo deployment/<APP_DEPLOYMENT> -n <APP_NAMESPACE>
argocd app sync <APP_NAME>
```

AWS-only ECS fallback을 시연하는 경우에만 이전 Task Definition revision으로 ECS Service를
업데이트함.

## 4. 발표용 롤백 시연

- 실패 이미지 또는 잘못된 환경 변수로 배포
- Health Check 실패 확인
- 이전 Git revision 또는 image tag로 롤백
- 정상 응답 복구 확인

## 5. 사후 기록

- 실패 원인
- 감지 지표
- 복구 시간
- 재발 방지 조치
