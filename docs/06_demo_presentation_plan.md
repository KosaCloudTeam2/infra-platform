# 발표 및 시연 계획

## 1. 발표 구성

1. 문제 정의: 수동 배포와 단일 서버 운영의 한계
2. 목표: 안전하고 반복 가능한 클라우드 배포 플랫폼
3. 아키텍처: VPC, ALB, 온프레미스 Kubernetes, Argo CD, Docker Hub, GitHub Actions, CloudWatch, WAF
4. 구현 내용: IaC, CI/CD, 보안, 관측성
5. 장애 대응: Pod 장애, 배포 실패, Health Check 실패
6. 비용 최적화: EKS 최소 PoC 범위 제한, 운영용 EKS 미전환, EC2 burst, NAT 선택, 로그 보존
7. 데이터 계층: RDS 제외, Percona XtraDB Cluster, ProxySQL, Ceph 백업
8. 한계와 확장: HTTPS, Blue/Green, CloudFront, EKS Hybrid Nodes, AWS Load Balancer Controller,
   운영용 EKS 전환, S3 2차 백업

## 2. 시연 시나리오

### 시연 1: 자동 배포

- GitHub Actions workflow 실행
- Docker 이미지 빌드
- Docker Hub 이미지 push 확인
- Argo CD Application sync 확인
- Kubernetes Deployment rollout 확인
- Service 또는 Ingress URL 접속 확인

### 시연 2: 장애 복구

- 잘못된 이미지 태그 또는 헬스체크 실패 manifest 반영
- Argo CD sync 실패 또는 Kubernetes rollout 실패 확인
- 이전 정상 Git revision 또는 image tag로 복구
- Kubernetes/EC2 로그와 CloudWatch Alarm 확인

### 시연 3: 보안 설명

- GitHub Actions가 Access Key 없이 OIDC Role 사용
- ALB SG와 AWS burst app SG의 참조 기반 접근 제어 설명
- WAF Managed Rule 적용 화면 설명

### 시연 4: DB 백업과 Ceph 활용

- ProxySQL을 통한 앱 DB 접근 구조 설명
- Percona XtraBackup 실행 또는 백업 산출물 확인
- Ceph RGW bucket에 백업 파일 업로드 확인
- 선택 시 AWS S3 2차 복제 구조 설명

## 3. 발표자 분담

발표는 전원이 참여함. 각 담당자는 자기 영역의 설명, 캡처, 시연, 예상 질문 답변을 책임짐.

| 구간                | 발표자 | 내용                                                 |
| :------------------ | :----- | :--------------------------------------------------- |
| 도입/목표           | 팀원 1 | 문제 정의, 목표, 전체 일정                           |
| Cloud / IaC         | 팀원 2 | VPC, Subnet, ALB, SG, WAF, EC2 ASG, 비용 포인트      |
| CI/CD / App Runtime | 팀원 4 | GitHub Actions, Docker Hub, Argo CD, Kubernetes 배포 |
| DB / Storage        | 팀원 3 | PXC, ProxySQL, XtraBackup, Ceph RGW 백업             |
| Observability       | 팀원 1 | Prometheus/Grafana 또는 CloudWatch, 장애 판단 지표   |
| 장애 복구           | 전원   | 각자 담당 영역의 장애 상황과 복구 절차 설명          |
| 마무리              | 전원   | 성과, 한계, 확장 계획, 담당 영역별 Q&A 대응          |

영역별 시연 책임:

- 팀원 1: 관측성 대시보드, 알람, 통합 시연 흐름, 발표 캡처 품질
- 팀원 2: Terraform plan/apply, 네트워크/보안그룹, IAM/OIDC, 비용 제한, ALB/WAF/EC2 ASG 캡처
- 팀원 3: PXC/ProxySQL 상태, 백업 산출물, Ceph RGW 업로드 캡처
- 팀원 4: GitHub Actions, Docker Hub 이미지, Argo CD sync 실행, Kubernetes rollout 캡처

## 4. 발표 자료 체크리스트

- [ ] 전체 아키텍처 다이어그램
- [ ] 배포 흐름 시퀀스 다이어그램
- [ ] 보안 경계 표
- [ ] 장애 대응 시나리오 표
- [ ] 비용 최적화 표
- [ ] 실제 콘솔 또는 CLI 캡처
- [ ] 예상 질문과 답변
