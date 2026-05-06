# Definition of Done

## 1. 시스템 구축 완료 기준

- [ ] Terraform으로 AWS burst 네트워크, ALB, EC2 Auto Scaling 리소스를 재현 가능함
- [ ] 온프레미스 Proxmox VM 기반 Kubernetes 클러스터가 구성됨
- [ ] 기존 앱이 Docker 이미지로 빌드됨
- [ ] Docker Hub 또는 팀 표준 컨테이너 레지스트리에 이미지가 저장됨
- [ ] Kubernetes Deployment/Service/Ingress가 정상 동작함
- [ ] AWS burst ALB Health Check가 정상임
- [ ] CloudWatch Alarm으로 AWS EC2 scale-out/scale-in 기준이 확인됨
- [ ] GitHub Actions로 배포가 자동화됨
- [ ] Kubernetes logs 또는 EC2 Docker logs에서 앱 로그를 확인할 수 있음
- [ ] 최소 1개 이상의 CloudWatch Alarm이 동작함
- [ ] WAF 또는 SG 기반 보안 정책이 적용됨
- [ ] 배포 실패 또는 앱 장애 롤백 시나리오가 검증됨

## 2. 문서 완료 기준

- [ ] 아키텍처 문서 최신화
- [ ] 주요 설계 결정 ADR 작성
- [ ] Terraform 실행 절차 문서화
- [ ] AWS 인증 전/후 Terraform 검증 절차 문서화
- [ ] 임시 샘플 앱과 실제 앱 교체 기준 문서화
- [ ] 배포 runbook 작성
- [ ] 롤백 runbook 작성
- [ ] 보안 정책 문서화
- [ ] MkDocs 문서 홈과 navigation 최신화
- [ ] 발표 자료 초안 작성

## 3. 발표 완료 기준

- [ ] 10-15분 내 발표 가능
- [ ] 시연 순서가 끊기지 않음
- [ ] 장애 상황을 의도적으로 만들고 복구 가능
- [ ] 팀원별 담당 질문에 답변 가능
