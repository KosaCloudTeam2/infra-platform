# 03 CI/CD / App Runtime Implementation

담당: 팀원 4

## 1. 목표

GitHub Actions 기반으로 Docker 이미지를 Docker Hub에 push하고, Argo CD 기반 GitOps로 온프레미스
Kubernetes Deployment를 갱신함. AWS burst 영역은 EC2 ASG instance refresh를 수동 실행하는 방식으로
분리함. 앱-DB 연결은 설정값 준비와 전달까지 담당하고 최종 검증은 Observability / Integration / Demo
담당이 주관함.

## 2. 사전 조건

- `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` GitHub Secret 등록
- Docker Hub repository 이름 확인
- 온프레미스 Kubernetes 클러스터 접근 가능
- Argo CD 설치 namespace와 접속 경로 확인
- Argo CD Application이 추적할 manifest 또는 Helm chart 경로 확정
- 앱 포트와 ALB Health Check 경로가 `container_port`, `health_check_path`와 일치함
- DB 담당자로부터 ProxySQL endpoint와 Secret 전달 방식 인계

## 3. 구현 순서

1. 로컬 Docker build와 `/health` 응답 확인
2. Docker Hub repository 이름과 GitHub Actions env 값 확인
3. AWS fallback이 필요하면 GitHub OIDC Role assume 가능 여부 확인
4. Argo CD 설치
5. Argo CD admin 초기 비밀번호 변경과 초기 Secret 삭제
6. Argo CD Application 생성
7. Argo CD 수동 sync 성공 확인
8. Drift 감지와 Self Heal 검증
9. `Build and Push Image` workflow에서 Docker image를 `github.sha`, `latest`로 push
10. Kubernetes manifest 또는 Helm values의 image tag 갱신
11. Argo CD Application sync 실행
12. Kubernetes Deployment rollout 확인
13. 앱 로그 확인
14. Observability 담당 검증용으로 ProxySQL endpoint/Secret 설정값 전달
15. AWS burst app image 반영 필요 시 `Refresh AWS Burst ASG` workflow 수동 실행
16. 실패 배포 롤백 절차를 Runbook에 반영

## 4. 로컬 앱 검증

```powershell
docker build -t cloud-infra-app:local ./app
docker run --rm -p 8080:8080 cloud-infra-app:local
```

다른 터미널에서 확인:

```powershell
.\scripts\smoke-test.ps1 -BaseUrl http://localhost:8080
```

## 5. GitHub Actions / Argo CD 검증

확인 항목:

- Docker Hub login 단계 성공
- Docker Hub에 `github.sha` 태그와 `latest` 태그 생성
- `argocd-server` deployment rollout 성공
- `argocd-initial-admin-secret` 삭제 또는 비밀번호 변경 완료
- Application 수동 sync 성공
- Drift 발생 시 `OutOfSync` 표시 확인
- `selfHeal: true` 적용 시 Git 선언값 복구 확인
- manifest image tag 갱신 확인
- Argo CD Application `Synced` 상태
- Argo CD Application `Healthy` 상태

## 6. Kubernetes 검증

```powershell
kubectl get application -n argocd
kubectl rollout status deployment/<app-deployment-name> -n <app-namespace>
```

완료 기준:

- Argo CD Application이 `Synced`와 `Healthy` 상태
- Kubernetes Deployment rollout 성공
- Service 또는 Ingress URL에서 앱 응답 확인
- AWS burst fallback 사용 시 Target Group health가 `healthy`

## 7. 앱-DB 연결 설정 기준

환경변수/Secret 기준:

- `DB_HOST`: ProxySQL private IP 또는 Internal NLB DNS
- `DB_PORT`: `6033`
- `DB_USER`: 앱 전용 계정
- `DB_PASSWORD`: Kubernetes Secret 또는 선택 확장 Secrets Manager secret

앱은 PXC 노드 private IP를 직접 참조하지 않음. 웹 서버 기동/접속과 DB 연결 최종 검증은 Observability
/ Integration / Demo 담당이 수행함.

## 8. 산출물

- GitHub Actions 실행 결과 캡처
- Docker Hub 이미지 태그 목록
- Argo CD Application 상태
- Kubernetes rollout 결과
- 필요 시 ASG instance refresh와 ALB Target Group health 결과
- Kubernetes 또는 EC2 Docker logs 캡처
- 앱-DB 연결 설정값 전달 결과
- 롤백 Runbook 업데이트

## 9. 주의 사항

- GitHub에 AWS Access Key를 저장하지 않음
- AWS 계정 ID, Access Key, Argo CD 초기 비밀번호를 저장소에 커밋하지 않음
- Argo CD admin 초기 비밀번호를 저장소에 커밋하지 않음
- 강의 실습은 NodePort 접속 방식이었으나, 프로젝트에서는 사설망 또는 제한된 실습망에서만 사용함
- Argo CD auto-sync는 Day 13 이전 안정화 후 활성화함
- Day 14부터는 자동 배포보다 수동 `workflow_dispatch` 기반 안정화를 우선 검토함
- 실패 배포 시 새 기능 수정이 아니라 이전 정상 Git revision 또는 image tag로 롤백함
