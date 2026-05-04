# 보안 정책

## 1. 기본 원칙

- 장기 Access Key를 GitHub Secrets에 저장하지 않음
- GitHub Actions는 OpenID Connect(OIDC) 기반 Identity and Access Management(IAM) Role Assume 방식 사용
- Public Subnet에는 ALB만 배치함
- 애플리케이션 Task는 Private Subnet 배치를 기본값으로 함
- ProxySQL과 Percona XtraDB Cluster(PXC) 노드는 Private Data Subnet에만 배치하고 Public IP를 부여하지
  않음
- Security Group(SG)은 출발지 SG 기준으로 최소 허용함
- Secret 값은 Terraform 변수 또는 코드에 직접 저장하지 않음

## 2. IAM 역할

| Role                 | 용도       | 주요 권한                                   |
| :------------------- | :--------- | :------------------------------------------ |
| GitHubDeployRole     | CI/CD 배포 | Elastic Container Registry(ECR) Push, Elastic Container Service(ECS) Deploy, iam:PassRole 제한 |
| ECSTaskExecutionRole | ECS 실행   | ECR Pull, CloudWatch Logs Write                                                                    |
| ECSTaskRole          | 앱 런타임  | Secrets Manager Read, 필요 시 Simple Storage Service(S3) Read/Write                               |

## 3. 팀원 AWS 접근 원칙

팀원 4명에게 AWS 콘솔 또는 Command Line Interface(CLI) 접근을 줄 때는 **하나의 계정을 공유하지 않고 개인별 접근 주체를
분리**함. 공유 계정은 누가 어떤 리소스를 만들었는지 추적하기 어렵고, 비밀번호/MFA/세션 관리와 퇴장
처리가 불명확해짐.

권장 순서:

1. **가장 권장: IAM Identity Center**
   - 팀원별 사용자 1개씩 생성
   - `infra-platform-developer`, `infra-platform-readonly` 같은 그룹으로 권한 부여
   - CLI는 SSO profile을 사용
   - MFA(Multi-Factor Authentication, 다중 인증)를 활성화
2. **대안: 개인별 IAM User**
   - AWS Organizations 또는 IAM Identity Center를 쓰기 어려운 단일 계정 MVP에서만 사용
   - 팀원별 IAM User 1개씩 생성
   - 공통 IAM Group으로 권한 관리
   - 콘솔 비밀번호는 최초 로그인 후 변경하도록 설정
   - MFA 필수
   - Access Key는 기본 생성하지 않고, 꼭 필요한 경우에만 기간을 정해 발급
3. **금지: 3명이 하나의 IAM User 공유**
   - 감사 로그에서 실제 작업자를 구분할 수 없음
   - 한 명이 빠졌을 때 비밀번호와 Access Key 전체를 교체해야 함
   - MFA를 개인별로 강제하기 어려움
   - 실수 또는 비용 사고 발생 시 원인 추적이 어려움

### 3.1 프로젝트 권한 모델

13일 MVP에서는 과도한 권한 분산보다 안전한 운영 경계를 우선함.

| 대상                     | 권장 접근                                    | 설명                           |
| :----------------------- | :------------------------------------------- | :----------------------------- |
| 팀원 1 Project Lead      | ReadOnly + 제한된 운영 확인 권한             | 발표/검수/CloudWatch 확인 중심 |
| 팀원 2 Network/IaC       | Terraform plan 중심, apply는 합의된 담당자만 | VPC, ALB, SG 변경 책임         |
| 팀원 3 DB/Storage        | EC2 Systems Manager(SSM) 접속, CloudWatch/EC2 확인 | PXC/ProxySQL/Ceph 구성 책임    |
| 팀원 4 CI/CD/App Runtime | ECR/ECS/GitHub Actions 확인                  | 배포와 앱 런타임 책임          |
| Terraform apply 담당자   | 별도 관리자 승인 또는 임시 상승 권한         | 팀 apply는 1명으로 제한        |

### 3.2 실습용 단일 그룹 예외

현업 기준은 역할별 최소 권한 분리임. 단, 이번 프로젝트는 13일 실습과 Terraform 학습이 목적이므로
팀원 전원이 동일한 실습 그룹에 속해 인프라 생성과 `terraform apply`를 수행할 수 있음.

권장 구성:

- 그룹명: `infra-platform-lab-admin`
- 대상: 팀원 4명 개인 IAM User 또는 IAM Identity Center 사용자
- 권한: 실습 계정 한정 `AdministratorAccess`
- 비용 권한: 별도 부여하지 않음
- MFA: 전원 필수
- 공유 계정: 금지
- Access Key: 기본 미발급, 로컬 CLI 실습 필요 시 개인별 발급 후 프로젝트 종료 시 삭제

IAM User 생성 기준:

- `Provide user access to the AWS Management Console`: 체크
- 사용자 유형: `IAM user`
- 콘솔 비밀번호: 임시 비밀번호 또는 자동 생성
- `User must create a new password at next sign-in`: 체크
- 권한 부여: 사용자 직접 정책 연결보다 `infra-platform-lab-admin` 그룹 추가
- Access Key: 최초 생성 시 만들지 않음

운영 제한:

- `terraform apply` 동시 실행 금지
- apply 전 팀 채널 승인 또는 구두 합의
- apply 담당자와 시간 기록
- `terraform plan` 결과 공유 후 apply
- 실습 종료 후 그룹 권한 제거 또는 사용자 비활성화
- 발표 후 비용 리소스 정리

### 3.3 실무 적용 기준

- 루트 계정은 사용하지 않고 MFA를 반드시 활성화함
- 팀원별 콘솔 로그인은 개인 계정 또는 개인 IAM Identity Center 사용자로 수행함
- Terraform apply 권한은 현업 기준으로 필요한 시점에만 부여하는 방식을 우선함
- 실습 예외 적용 시에도 실제 apply는 한 번에 1명만 수행함
- GitHub Actions 배포는 개인 Access Key가 아니라 OIDC Role을 사용함
- 개인 IAM User를 만들더라도 장기 Access Key는 기본 발급하지 않음
- 프로젝트 종료 또는 팀원 변경 시 해당 사용자만 비활성화함

## 4. 네트워크 보안

| 대상        | Inbound                                           | Outbound           |
| :---------- | :------------------------------------------------ | :----------------- |
| ALB SG      | 80/443 from Internet                              | App Port to ECS SG |
| ECS SG      | App Port from ALB SG                              | HTTPS 443          |
| ProxySQL SG | 6033 from ECS SG                                  | 3306 to PXC SG     |
| PXC SG      | 3306 from ProxySQL SG, 4567/4568/4444 from PXC SG | 제한               |
| Ceph RGW    | HTTPS from allowed CIDR/VPN only                  | 제한               |

DB 관련 포트는 인터넷 전체(`0.0.0.0/0`)에 열지 않음. 운영 접속은 Secure Shell(SSH) 공개보다 SSM
Session Manager 또는 제한된 Bastion 접근을 우선함.

## 5. WAF 정책

- AWS Managed Core Rule Set
- Known Bad Inputs Rule Set
- SQL Injection Rule Set
- Rate-based Rule

## 6. Secret 관리

- `APP_SECRET`, `DB_PASSWORD`, `JWT_SECRET` 등은 Secrets Manager에 저장함
- `PROXYSQL_PASSWORD`, `PXC_BACKUP_KEY`, `CEPH_RGW_ACCESS_KEY`, `CEPH_RGW_SECRET_KEY` 등도 Secrets
  Manager 또는 CI Secret에 저장함
- Argo CD admin 초기 비밀번호, repository credential, deploy key는 저장소에 저장하지 않음
- GitHub Secrets에는 AWS Role ARN, AWS Region 등 민감도가 낮은 설정만 저장함
- `.env` 파일은 커밋 금지

## 7. 점검 체크리스트

- [ ] Access Key가 저장소에 없음
- [ ] `.tfstate`가 커밋되지 않음
- [ ] ALB 외 리소스가 인터넷에 직접 노출되지 않음
- [ ] ECS Task Role 권한이 와일드카드로 열려 있지 않음
- [ ] 팀원별 AWS 접근 주체가 분리되어 있음
- [ ] 공유 IAM User를 사용하지 않음
- [ ] 콘솔 접근 사용자에 MFA가 활성화되어 있음
- [ ] 실습용 단일 그룹 사용 시 apply 담당자와 실행 시간이 기록됨
- [ ] WAF가 ALB에 연결됨
- [ ] CloudWatch 로그 보존 기간이 설정됨
- [ ] ProxySQL Admin 포트 `6032`가 인터넷에 노출되지 않음
- [ ] PXC Galera 포트 `4567/4568/4444`는 PXC 노드 간에만 허용됨
- [ ] Ceph RGW access/secret key가 저장소와 Terraform state에 노출되지 않음
- [ ] Argo CD admin password와 repository credential이 저장소에 없음
