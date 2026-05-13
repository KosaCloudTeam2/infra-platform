# Cloud Infra Deployment Platform (Demo Version)

> **주의**: 본 프로젝트는 현재 **데모(Demo) 버전** 또는 **임시 구조**로 운영되고 있습니다. 향후
> 전체적인 프로젝트 구조가 변경될 예정이므로 참고하시기 바랍니다.

13일 시스템 구축 + 3일 시연 포함 발표 준비를 목표로 하는 4인 팀 클라우드 인프라 프로젝트 저장소

## 1. 프로젝트 목표

기존에 준비된 간단한 애플리케이션을 대상으로 클라우드 기반 배포 플랫폼을 구축함.

- AWS 기반 네트워크, EC2 burst, 배포, 보안, 관측성 체계 구성
- GitHub Actions와 OpenID Connect(OIDC)를 이용한 키 없는 이미지 빌드 자동화
- Argo CD 기반 GitOps 배포로 Kubernetes manifest 동기화
- 네트워크 로드 밸런서(Network Load Balancer, NLB), Docker Hub 기반 이미지 저장소, EC2 Auto Scaling
  Group 기반 burst 영역 구성
- CloudWatch Alarm, 웹 방화벽(Web Application Firewall, WAF), Kubernetes/GitHub Secret 기반 운영
  가드레일 구성
- 장애 상황과 롤백 시나리오를 포함한 발표 데모 준비

## 2. 권장 MVP 범위 (데모 기준)

| 영역        | 구현 내용                                                            | 담당 문서                                              |
| :---------- | :------------------------------------------------------------------- | :----------------------------------------------------- |
| 네트워크    | VPC, Public/Private Subnet, IGW, Security Group                      | [Security Policy](docs/01_security_policy.md)          |
| 컴퓨팅      | 온프레미스 Kubernetes, AWS EC2 burst, NLB Target Group               | [Definition of Done](docs/02_definition_of_done.md)    |
| CI/CD       | GitHub Actions, Docker Build, Docker Hub Push, Argo CD GitOps Deploy | [Docs Index](docs/index.md)                            |
| 보안        | IAM OIDC Role, 최소 권한, WAF, Kubernetes/GitHub Secret              | [Security Policy](docs/01_security_policy.md)          |
| 데이터      | Percona Operator, Ceph 백업                                          | [Glossary](docs/11_glossary.md)                        |
| 역할별 구축 | 팀원별 상세 구현 가이드                                              | [Build-up Guide](docs/architecture/build-up/README.md) |
| 관측성      | CloudWatch 또는 Prometheus/Grafana, 배포 상태 추적                   | [Monitoring Runbook](docs/runbooks/monitoring.md)      |

## 3. 저장소 구조

```text
.
├── .github/workflows/          # CI/CD 파이프라인 템플릿
├── app/                        # 임시 배포 검증용 샘플 앱
├── docs/                       # 일정, 역할, 설계, 발표 자료
├── infra/
│   ├── terraform/              # AWS IaC 템플릿
│   └── ansible/                # EC2 운영 자동화
├── k8s/                        # K8s 확장 매니페스트
├── scripts/                    # 운영 보조 스크립트
└── tests/                      # 인프라 검증 체크리스트
```

## 4. 문서 홈

문서를 처음 읽을 때는 [Docs Index](docs/index.md)의 순서와 역할별 링크를 기준으로 함. 모든 문서는
현재 데모 버전에 맞춰 재구성되었습니다.
