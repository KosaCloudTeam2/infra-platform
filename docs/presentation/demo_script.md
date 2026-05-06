# 시연 스크립트

## 1. 자동 배포 시연

> "main 브랜치에 변경 사항이 반영되면 GitHub Actions가 Docker 이미지를 빌드하고 Docker Hub에
> 업로드합니다. 이후 Kubernetes manifest의 이미지 태그를 갱신하고, Argo CD가 Git 상태를 클러스터에
> 동기화합니다."

확인 화면

- GitHub Actions workflow
- Docker Hub image tag
- Argo CD Application sync
- Kubernetes rollout
- Service 또는 Ingress URL

## 2. 장애 복구 시연

> "잘못된 배포가 발생하면 Argo CD sync 상태나 Kubernetes rollout 상태에서 이상을 확인하고, 이전 정상
> Git revision 또는 image tag로 복구할 수 있습니다."

확인 화면

- Argo CD Application 상태
- Kubernetes rollout 상태
- CloudWatch Logs
- 복구 후 Service 또는 Ingress 응답

## 3. 보안 설명

> "배포 파이프라인은 장기 Access Key를 사용하지 않고 GitHub OIDC로 임시 권한을 받아 AWS에
> 접근합니다. AWS burst 영역의 외부 진입점은 ALB로 제한하고, DB 접근은 ProxySQL endpoint로
> 제한합니다."

확인 화면

- IAM Role trust policy
- Security Group inbound rule
- WAF association
