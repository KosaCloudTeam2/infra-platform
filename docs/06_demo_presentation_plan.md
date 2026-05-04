# 발표 및 시연 계획

## 1. 발표 구성

1. 문제 정의: 수동 배포와 단일 서버 운영의 한계
2. 목표: 안전하고 반복 가능한 클라우드 배포 플랫폼
3. 아키텍처: VPC, ALB, 온프레미스 Kubernetes, Argo CD, ECR, GitHub Actions, CloudWatch, WAF
4. 구현 내용: IaC, CI/CD, 보안, 관측성
5. 장애 대응: Task 장애, 배포 실패, Health Check 실패
6. 비용 최적화: EKS 미사용, EC2 burst, NAT 선택, 로그 보존
7. 데이터 계층: RDS 제외, Percona XtraDB Cluster, ProxySQL, Ceph 백업
8. 한계와 확장: HTTPS, Blue/Green, CloudFront, EKS, S3 2차 백업

## 2. 시연 시나리오

### 시연 1: 자동 배포

- GitHub Actions workflow 실행
- Docker 이미지 빌드
- ECR 이미지 push 확인
- Argo CD Application sync 확인
- Kubernetes Deployment rollout 확인
- Service 또는 Ingress URL 접속 확인

### 시연 2: 장애 복구

- 잘못된 이미지 태그 또는 헬스체크 실패 manifest 반영
- Argo CD sync 실패 또는 Kubernetes rollout 실패 확인
- 이전 정상 Git revision 또는 image tag로 복구
- CloudWatch Logs와 Alarm 확인

### 시연 3: 보안 설명

- GitHub Actions가 Access Key 없이 OIDC Role 사용
- ALB SG와 ECS SG의 참조 기반 접근 제어 설명
- WAF Managed Rule 적용 화면 설명

### 시연 4: DB 백업과 Ceph 활용

- ProxySQL을 통한 앱 DB 접근 구조 설명
- Percona XtraBackup 실행 또는 백업 산출물 확인
- Ceph RGW bucket에 백업 파일 업로드 확인
- 선택 시 AWS S3 2차 복제 구조 설명

## 3. 발표자 분담

| 구간            | 발표자 | 내용                        |
| :-------------- | :----- | :-------------------------- |
| 도입/목표       | 팀원 1 | 문제 정의, 목표, 전체 일정  |
| 아키텍처        | 팀원 2 | VPC, Subnet, ALB, SG        |
| 배포/런타임     | 팀원 4 | GitHub Actions, Argo CD, ECR, Kubernetes |
| 데이터/스토리지 | 팀원 3 | PXC, ProxySQL, Ceph 백업    |
| 보안/운영       | 팀원 4 | OIDC, WAF, CloudWatch, 롤백 |
| 마무리          | 팀원 1 | 성과, 한계, 확장 계획       |

## 4. 발표 자료 체크리스트

- [ ] 전체 아키텍처 다이어그램
- [ ] 배포 흐름 시퀀스 다이어그램
- [ ] 보안 경계 표
- [ ] 장애 대응 시나리오 표
- [ ] 비용 최적화 표
- [ ] 실제 콘솔 또는 CLI 캡처
- [ ] 예상 질문과 답변
