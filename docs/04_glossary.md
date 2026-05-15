# 용어집

프로젝트 문서에서 반복 사용되는 AWS, 인프라, 배포 약어 및 핵심 개념 정리

---

## 프로젝트 핵심 개념 (쉽게 알아보기)

| 용어                    | 쉽게 말하면                                                    | 이 프로젝트에서의 의미                         |
| :---------------------- | :------------------------------------------------------------- | :--------------------------------------------- |
| 온프레미스(On-premises) | 직접 소유하거나 직접 관리하는 서버 환경                        | Proxmox 장비와 그 위의 VM, Kubernetes, Ceph    |
| Proxmox                 | 서버 한 대 또는 여러 대에서 VM을 만들고 관리하는 가상화 플랫폼 | 온프레미스 VM과 Ceph 운영 기반                 |
| Kubernetes(K8s)         | 여러 서버 위에 컨테이너 앱을 배포하고 자동 복구하는 플랫폼     | 온프레미스 앱 실행의 중심 후보                 |
| Cluster                 | 여러 서버를 하나의 묶음처럼 관리하는 단위                      | Kubernetes 클러스터 또는 DB 클러스터           |
| Node                    | 클러스터에 참여하는 서버 또는 VM                               | Kubernetes worker node, AWS EC2 node 등        |
| Pod                     | Kubernetes에서 앱 컨테이너가 실행되는 가장 작은 단위           | 웹앱 컨테이너 실행 단위                        |
| Ingress                 | Kubernetes 내부 앱을 외부에서 접근 가능하게 하는 입구          | 온프레미스 웹앱 진입점                         |
| Control Plane(CP)       | Kubernetes 클러스터를 제어하는 관리 계층                       | API Server, Scheduler, Controller Manager 포함 |
| Service                 | Pod 집합 앞에 두는 접근 추상화 계층                            | 내부 통신 안정화와 로드밸런싱 수행             |
| EC2                     | AWS에서 빌려 쓰는 가상 서버                                    | 부하 증가 시 추가 실행되는 burst 서버          |
| ALB                     | HTTP/HTTPS 요청을 여러 서버로 나누어 보내는 AWS 로드밸런서     | AWS burst 영역의 외부 진입점                   |
| NLB                     | 네트워크 트래픽을 여러 서버로 나누어 보내는 AWS 로드밸런서     | AWS burst 영역의 외부 진입점                   |
| Auto Scaling Group(ASG) | 조건에 따라 EC2를 자동으로 늘리거나 줄이는 AWS 기능            | 부하 증가 시 AWS EC2 생성, 부하 감소 시 종료   |
| Launch Template         | 새 EC2를 만들 때 사용할 서버 설정 템플릿                       | AMI, 인스턴스 타입, user data, 보안그룹 정의   |
| CloudWatch              | AWS 로그, 지표, 알람 서비스                                    | CPU, 요청 수, 장애 감지와 scale-out 기준       |
| ECS                     | AWS의 컨테이너 실행 서비스                                     | 기존 fallback 구조. Kubernetes는 아님          |
| Fargate                 | 서버를 직접 관리하지 않고 컨테이너만 실행하는 AWS 방식         | ECS fallback에서 사용 가능                     |
| EKS                     | AWS가 관리해주는 Kubernetes 서비스                             | 비용과 관리 편의성 사이의 선택지               |
| EKS Hybrid Nodes        | 온프레미스 서버를 EKS 클러스터 노드처럼 붙이는 AWS 기능        | 정석적인 hybrid Kubernetes 후보지만 비용 증가  |
| S3                      | AWS 객체 저장소 서비스                                         | 파일, 백업, 정적 자산 저장 후보                |
| Ceph                    | 직접 운영하는 분산 스토리지                                    | 온프레미스 저장소                              |
| Ceph RGW                | Ceph를 S3처럼 사용할 수 있게 해주는 게이트웨이                 | 온프레미스 S3 호환 저장소                      |
| RBD                     | Ceph의 블록 스토리지                                           | Proxmox VM 디스크, Kubernetes PV 후보          |
| CephFS                  | Ceph의 공유 파일 시스템                                        | 여러 노드가 공유하는 파일 저장 후보            |
| PXC                     | MySQL 호환 DB를 여러 노드로 묶는 Percona DB 클러스터           | RDS 대신 직접 운영하는 DB 후보                 |
| Percona Operator        | MySQL 클러스터를 자동화하여 관리하는 도구                      | RDS 대신 직접 운영하는 DB 후보                 |
| ProxySQL                | 앱과 DB 사이에서 DB 접속을 중계하는 프록시                     | 앱은 DB 노드가 아니라 ProxySQL로 접속          |

---

## AWS / 네트워크

| 약어                 | Full name                         | 의미                                                             |
| :------------------- | :-------------------------------- | :--------------------------------------------------------------- |
| ACM                  | AWS Certificate Manager           | HTTPS 인증서 발급/관리 서비스                                    |
| ALB                  | Application Load Balancer         | HTTP/HTTPS 요청을 여러 대상에 분산하는 L7 로드밸런서             |
| NLB                  | Network Load Balancer             | TCP/UDP 트래픽을 분산하는 L4 로드밸런서                          |
| NLB Target 5xx       | Network Load Balancer Target 5xx  | NLB 뒤의 앱 서버가 반환한 `500`번대 서버 오류 수                 |
| ASG                  | Auto Scaling Group                | 부하나 정책에 따라 EC2 인스턴스 수를 자동 조정하는 그룹          |
| AZ                   | Availability Zone                 | AWS 리전 안의 독립 데이터센터 영역                               |
| CloudWatch           | Amazon CloudWatch                 | AWS 로그, 지표, 알람을 수집하고 확인하는 운영 관측 서비스        |
| EC2                  | Elastic Compute Cloud             | AWS 가상 서버 서비스                                             |
| EKS                  | Elastic Kubernetes Service        | AWS 관리형 Kubernetes 서비스. MVP에서는 최소 PoC로 사용          |
| ENI                  | Elastic Network Interface         | EC2에 부착하는 가상 NIC                                          |
| Secondary Private IP | Secondary Private IP              | ENI/EC2에 추가로 부여 가능한 보조 사설 IP                        |
| EventBridge cron     | Amazon EventBridge Scheduler/cron | cron 표현식 기반 스케줄 실행 서비스                              |
| Health Check         | Health Check                      | NLB나 Kubernetes가 앱이 정상 응답하는지 주기적으로 확인하는 검사 |
| IGW                  | Internet Gateway                  | VPC와 인터넷 연결 게이트웨이                                     |
| NAT                  | Network Address Translation       | Private Subnet 리소스의 외부 통신 경로                           |
| VIP                  | Virtual IP                        | 장애 전환을 위해 여러 서버 앞에 두는 공유 가상 IP                |
| Multi DC             | Multi Data Center                 | 여러 데이터센터를 동시에 운영하는 구조                           |
| RDS                  | Relational Database Service       | AWS 관리형 관계형 데이터베이스 서비스                            |
| S3                   | Simple Storage Service            | AWS 객체 스토리지 서비스                                         |
| SG                   | Security Group                    | AWS 리소스 단위 가상 방화벽                                      |
| Target Group         | Target Group                      | NLB/NLB가 트래픽을 전달할 EC2, IP, 컨테이너 대상 묶음            |
| VPC                  | Virtual Private Cloud             | AWS 계정 안의 격리된 가상 네트워크                               |
| WAF                  | Web Application Firewall          | 웹 요청 필터링과 공격 차단 서비스                                |

## 배포 / 컨테이너

| 약어                    | Full name                                    | 의미                                                                        |
| :---------------------- | :------------------------------------------- | :-------------------------------------------------------------------------- |
| Argo CD                 | Argo Continuous Delivery                     | Git 저장소의 Kubernetes manifest를 클러스터에 동기화하는 GitOps 배포 도구   |
| CI/CD                   | Continuous Integration / Continuous Delivery | 코드 통합, 빌드, 테스트, 배포 자동화 흐름                                   |
| Drift                   | Configuration Drift                          | Git에 선언된 상태와 실제 클러스터 상태가 달라진 상황                        |
| Docker Hub              | Docker Hub                                   | Docker 이미지 저장소. MVP 기본 이미지 레지스트리                            |
| Private Registry        | Private Registry                             | 팀 내부망 또는 온프레미스에 직접 운영하는 이미지 저장소                     |
| Harbor                  | Harbor                                       | 권한, 프로젝트, 이미지 스캔 기능을 제공하는 Private Registry 구현체         |
| ECR                     | Elastic Container Registry                   | AWS 관리형 Docker 이미지 저장소. AWS-only 비교안 대체안                     |
| ECS                     | Elastic Container Service                    | AWS 컨테이너 실행 서비스                                                    |
| Fargate                 | AWS Fargate                                  | 서버를 직접 관리하지 않고 ECS/EKS 컨테이너를 실행하는 방식                  |
| KEDA                    | Kubernetes Event-driven Autoscaling          | 외부 이벤트나 지표를 기준으로 Kubernetes workload를 자동 확장하는 도구      |
| Argo Rollouts           | Argo Rollouts                                | Kubernetes Blue/Green, Canary 배포를 지원하는 progressive delivery 도구     |
| GitOps                  | Git Operations                               | Git 저장소 선언 상태를 실제 인프라/클러스터 상태로 동기화하는 운영 방식     |
| Kubernetes Deployment   | Kubernetes Deployment                        | Pod 개수와 배포 버전을 선언하고 rolling update를 수행하는 Kubernetes 리소스 |
| Kubernetes Ingress      | Kubernetes Ingress                           | 클러스터 외부 HTTP/HTTPS 요청을 Service로 연결하는 Kubernetes 리소스        |
| Ingress Controller      | Ingress Controller                           | Ingress 규칙을 실제로 처리하는 컨트롤러(예: HAProxy Ingress, ingress-nginx) |
| Kubernetes Service      | Kubernetes Service                           | Pod 집합에 안정적인 내부 접근 경로를 제공하는 Kubernetes 리소스             |
| ClusterIP               | Kubernetes Service Type ClusterIP            | 클러스터 내부 전용 Service IP 타입                                          |
| NodePort                | Kubernetes Service Type NodePort             | 노드 포트를 직접 개방해 접근하는 Service 타입                               |
| Karpenter               | Karpenter                                    | Kubernetes 노드 자동 확장/축소 도구                                         |
| Karpenter Consolidation | Karpenter Consolidation                      | 불필요한 노드를 자동 정리해 비용을 줄이는 기능                              |
| Leader Election         | Leader Election                              | 다중 인스턴스 중 대표 1개를 선출해 중복 동작을 방지하는 메커니즘            |
| podAntiAffinity         | Pod Anti-Affinity                            | 동일 계열 Pod가 한 노드에 몰리지 않게 분산 배치하는 스케줄 정책             |
| OIDC                    | OpenID Connect                               | GitHub Actions가 AWS 임시 권한을 받기 위한 인증 방식                        |
| Pod                     | Kubernetes Pod                               | Kubernetes에서 컨테이너가 실행되는 가장 작은 배포 단위                      |
| PR                      | Pull Request                                 | 변경사항 병합 전 리뷰 요청                                                  |

## 보안 / 운영

| 약어        | Full name                      | 의미                                                            |
| :---------- | :----------------------------- | :-------------------------------------------------------------- |
| CLI         | Command Line Interface         | 터미널 기반 명령 실행 도구                                      |
| Bastion     | Bastion Host                   | 내부망 서버에 접속하기 위한 제한된 관리용 진입 서버             |
| DMZ         | Demilitarized Zone             | 외부 접근을 허용하되 내부망과 분리된 중간 보안 네트워크 영역    |
| Edge        | Edge Layer                     | 외부 네트워크가 처음 진입하는 경계 계층                         |
| GHCR        | GitHub Container Registry      | GitHub 제공 컨테이너 이미지 레지스트리                          |
| IAM         | Identity and Access Management | AWS 사용자, 역할, 권한 관리 서비스                              |
| Keepalived  | Keepalived                     | VIP를 active/standby 서버 사이에서 넘겨주는 고가용성 도구       |
| Keycloak    | Keycloak                       | SSO, MFA, 사용자 인증과 권한 관리를 제공하는 오픈소스 IAM 도구  |
| MFA         | Multi-Factor Authentication    | 비밀번호 외 추가 인증 방식                                      |
| PKI         | Public Key Infrastructure      | 인증서 발급, 검증, 폐기를 관리하는 공개키 기반 구조             |
| Role Assume | AssumeRole                     | 사용자나 GitHub Actions가 IAM Role의 임시 권한을 빌려 쓰는 동작 |
| SSM         | Systems Manager                | EC2 접속, 명령 실행, 운영 자동화 서비스                         |
| Vault       | HashiCorp Vault                | 비밀번호, 토큰, 인증서 같은 시크릿을 중앙 관리하는 도구         |

## 네트워크 / 트래픽 심화

| 약어/용어       | Full name                          | 의미                                                                 |
| :-------------- | :--------------------------------- | :------------------------------------------------------------------- |
| ARP             | Address Resolution Protocol        | IP 주소를 MAC 주소로 매핑하는 L2 네트워크 프로토콜                   |
| BGP             | Border Gateway Protocol            | 라우터 간 경로 정보를 교환하는 인터넷 핵심 라우팅 프로토콜           |
| ECMP            | Equal-Cost Multi-Path              | 동일 비용 경로를 여러 개 동시에 사용해 분산/가용성을 높이는 기법     |
| CARP            | Common Address Redundancy Protocol | pfSense에서 VIP failover에 사용하는 이중화 프로토콜                  |
| VRRP            | Virtual Router Redundancy Protocol | 라우터/VIP 장애조치를 위한 표준 이중화 프로토콜                      |
| FRR             | Free Range Routing                 | BGP/OSPF 등 동적 라우팅을 지원하는 오픈소스 라우팅 소프트웨어        |
| L4              | Layer 4                            | TCP/UDP 전송 계층 기준 트래픽 처리 계층                              |
| L7              | Layer 7                            | HTTP/HTTPS 애플리케이션 계층 기준 트래픽 처리 계층                   |
| Reverse Proxy   | Reverse Proxy                      | 클라이언트 대신 백엔드와 통신하며 요청을 중계/제어하는 프록시        |
| HAProxy         | High Availability Proxy            | L4/L7 로드밸런서 및 리버스 프록시 구현체                             |
| TLS             | Transport Layer Security           | HTTPS 통신 암호화 및 무결성 보호 프로토콜                            |
| LoadBalancer IP | LoadBalancer IP                    | 외부 서비스 접근용 대표 IP(예: MetalLB/kube-vip로 제공)              |
| kube-vip        | kube-vip                           | Kubernetes에서 VIP를 제공해 Control Plane/Service HA를 지원하는 도구 |
| MetalLB         | MetalLB                            | Bare Metal Kubernetes에서 LoadBalancer 타입 Service를 구현하는 도구  |

## 데이터 / 스토리지

| 약어             | Full name                         | 의미                                                                                |
| :--------------- | :-------------------------------- | :---------------------------------------------------------------------------------- |
| Ceph OSD         | Ceph Object Storage Daemon        | Ceph에서 실제 데이터를 디스크에 저장하고 복제하는 프로세스                          |
| Ceph pool        | Ceph Storage Pool                 | Ceph 객체를 저장하는 논리 저장 공간 묶음                                            |
| Grafana          | Grafana                           | Prometheus, CloudWatch 같은 지표를 대시보드로 보여주는 도구                         |
| garbd            | Galera Arbitrator Daemon          | Galera/Percona Operator quorum 보조용 비저장 투표 구성원                            |
| GSLB             | Global Server Load Balancing      | 여러 지역 또는 endpoint로 트래픽을 분산하거나 장애 시 우회하는 전역 로드밸런싱 개념 |
| iperf            | iperf                             | 네트워크 대역폭과 품질을 측정하는 도구                                              |
| JMeter           | Apache JMeter                     | HTTP/API 부하 테스트와 성능 검증 도구                                               |
| k6               | k6                                | JavaScript 기반 HTTP/API 부하 테스트 도구                                           |
| Locust           | Locust                            | Python 코드로 사용자 행동을 작성하는 부하 테스트 도구                               |
| Loki             | Grafana Loki                      | Kubernetes와 앱 로그를 label 기반으로 수집하고 조회하는 로그 도구                   |
| PMM              | Percona Monitoring and Management | Percona DB 모니터링 도구                                                            |
| p95 latency      | 95th percentile latency           | 요청 중 95%가 해당 시간 이하로 응답했다는 지연 시간 지표                            |
| Prometheus       | Prometheus                        | Kubernetes와 앱 지표를 주기적으로 수집하는 오픈소스 모니터링 도구                   |
| Thanos           | Thanos                            | Prometheus 지표 장기 보관, 통합 조회, 고가용성을 제공하는 확장 도구                 |
| Percona Operator | Percona Operator                  | MySQL 호환 데이터베이스 클러스터를 관리하는 쿠버네티스 오퍼레이터                   |
| RBD              | RADOS Block Device                | Ceph 블록 스토리지                                                                  |
| RGW              | RADOS Gateway                     | Ceph S3 호환 객체 스토리지 게이트웨이                                               |
| Sentry           | Sentry                            | 앱 예외, stack trace, release별 오류 추적 도구                                      |
| Single Writer    | Single Writer                     | DB 클러스터에서 쓰기 노드를 1대로 정해 쓰기 충돌을 줄이는 운영 방식                 |
| wsrep            | Write Set Replication             | Percona Operator/Galera Cluster의 복제 상태를 보여주는 상태 변수 접두어             |

---

## 숙지해야 할 표현

| 표현                                 | 의미                                                                                       |
| :----------------------------------- | :----------------------------------------------------------------------------------------- |
| `NLB Target 5xx 5분 합계 5회 이상`   | 5분 동안 NLB 뒤 앱 서버가 `500`, `502`, `503`, `504` 같은 서버 오류를 5번 이상 반환한 상태 |
| `Target Response Time`               | NLB가 앱 대상에게 요청을 보내고 응답을 받을 때까지 걸린 시간                               |
| `Target Group Health Check`          | NLB Target Group이 각 앱 대상의 `/health` 같은 경로를 호출해 정상 여부를 판단하는 검사     |
| `Target Health = healthy`            | NLB가 해당 앱 대상을 정상으로 판단해 트래픽을 보낼 수 있는 상태                            |
| `Target Health = unhealthy`          | NLB가 해당 앱 대상을 비정상으로 판단해 트래픽 전달을 제한하는 상태                         |
| `UnHealthyHostCount 1 이상`          | NLB Target Group 안의 앱 대상 중 Health Check 실패 대상이 1개 이상인 상태                  |
| `ASG desired capacity`               | Auto Scaling Group이 유지하려는 EC2 인스턴스 수                                            |
| `ASG scale-out`                      | 부하 증가로 EC2 인스턴스 수를 늘리는 동작                                                  |
| `ASG scale-in`                       | 부하 감소로 EC2 인스턴스 수를 줄이는 동작                                                  |
| `Launch Template`                    | EC2를 만들 때 사용할 AMI, 인스턴스 타입, 보안그룹, bootstrap 설정 묶음                     |
| `NAT Gateway 비용 발생`              | Private Subnet 리소스의 외부 통신을 위해 NAT Gateway를 켜두면 시간당 비용이 발생하는 상태  |
| `WAF Count 모드`                     | 요청을 차단하지 않고 규칙 매칭 횟수만 기록하는 관찰 모드                                   |
| `WAF Block 모드`                     | WAF 규칙에 걸린 요청을 실제로 차단하는 모드                                                |
| `OIDC Role Assume 성공`              | GitHub Actions가 장기 Access Key 없이 AWS IAM Role 임시 권한을 받는 데 성공한 상태         |
| `iam:PassRole 제한`                  | 배포 workflow가 지정된 IAM Role만 서비스에 넘길 수 있도록 제한하는 보안 설정               |
| `SSM Session Manager 접속`           | Public IP나 SSH 포트 없이 AWS Systems Manager를 통해 EC2에 접속하는 방식                   |
| `Argo CD Synced`                     | Git 저장소의 manifest와 Kubernetes 실제 리소스 상태가 일치하는 상태                        |
| `Argo CD OutOfSync`                  | Git 저장소 선언 상태와 Kubernetes 실제 상태가 달라진 상태                                  |
| `Argo CD Healthy`                    | Argo CD가 관리하는 앱 리소스가 정상 실행 중이라고 판단한 상태                              |
| `Argo CD Degraded`                   | Argo CD가 관리하는 앱 리소스 중 일부가 비정상이라고 판단한 상태                            |
| `Argo CD manual sync`                | 사용자가 버튼이나 명령으로 직접 Git 상태를 클러스터에 반영하는 방식                        |
| `Argo CD auto-sync`                  | Git 변경을 Argo CD가 자동으로 클러스터에 반영하는 방식                                     |
| `Self Heal`                          | 클러스터 상태가 Git 선언값과 달라졌을 때 Argo CD가 자동 복구하는 기능                      |
| `Kubernetes rollout 성공`            | 새 버전 Pod가 정상 준비되고 이전 버전 교체가 완료된 상태                                   |
| `rollout timeout`                    | 새 버전 Pod가 정해진 시간 안에 정상 상태가 되지 못한 상황                                  |
| `Pod Ready`                          | Pod가 트래픽을 받을 준비가 됐다고 Kubernetes가 판단한 상태                                 |
| `CrashLoopBackOff`                   | 컨테이너가 계속 죽고 재시작을 반복하는 Kubernetes 상태                                     |
| `ImagePullBackOff`                   | Kubernetes가 컨테이너 이미지를 registry에서 가져오지 못한 상태                             |
| `Ingress URL`                        | 외부 사용자가 Kubernetes 앱에 접근하는 HTTP/HTTPS 주소                                     |
| `Service endpoint`                   | Kubernetes Service가 연결하는 실제 Pod IP와 포트 목록                                      |
| `ProxySQL endpoint`                  | 앱이 DB에 접속할 때 사용하는 ProxySQL 주소                                                 |
| `ProxySQL backend status`            | ProxySQL이 뒤쪽 DB 노드를 정상 DB 서버로 보고 있는지 나타내는 상태                         |
| `DB 노드 1대 장애`                   | DB 클러스터 노드 중 1대가 중지되거나 클러스터에서 빠진 상황                                |
| `wsrep_cluster_status = Primary`     | DB 클러스터가 정상 Primary 구성으로 동작 중인 상태                                         |
| `wsrep_cluster_size = 3`             | DB 클러스터에 정상 참여 중인 노드가 3대인 상태                                             |
| `wsrep_local_state_comment = Synced` | 해당 DB 노드가 클러스터 데이터와 동기화된 상태                                             |
| `XtraBackup 산출물`                  | Percona XtraBackup으로 만든 DB 백업 파일                                                   |
| `체크섬 파일`                        | 백업 파일이 깨지지 않았는지 검증하기 위한 해시 값 파일                                     |
| `Ceph OSD 상태`                      | Ceph 저장 디스크 담당 프로세스가 `up/in` 상태인지 확인하는 항목                            |
| `Ceph pool 사용량`                   | 백업이나 파일 저장 공간이 얼마나 사용됐는지 확인하는 항목                                  |
| `RGW 오류`                           | S3 호환 API 요청 실패, 인증 실패, bucket 접근 실패 같은 Ceph Gateway 오류                  |
| `Ceph health = HEALTH_OK`            | Ceph 클러스터가 정상 상태라고 판단한 상태                                                  |
| `Ceph health = HEALTH_WARN`          | Ceph 클러스터가 동작은 하지만 확인이 필요한 경고가 있는 상태                               |
| `Ceph RGW bucket`                    | DB 백업 파일이나 앱 파일을 저장하는 S3 호환 객체 저장소 버킷                               |
| `PMM 선택 확장`                      | DB/ProxySQL 상세 지표를 보고 싶을 때 추가하는 DB 모니터링 확장                             |
| `Prometheus scrape`                  | Prometheus가 정해진 주기로 앱이나 Kubernetes 지표 endpoint를 수집하는 동작                 |
| `Grafana dashboard`                  | 수집된 지표를 그래프와 표로 보는 화면                                                      |
| `CloudWatch Logs`                    | AWS 리소스나 앱 로그가 저장되는 CloudWatch 로그 영역                                       |
| `CloudWatch Alarm`                   | 지표가 정해진 조건을 넘으면 경고 상태로 바뀌는 규칙                                        |
| `CloudWatch Agent`                   | EC2 내부 로그와 지표를 CloudWatch로 보내는 에이전트                                        |
| `ECS comparison`                     | 현재 MVP 기본 경로가 아니라 AWS-only 비교 시연용 ECS 배포 경로                             |
| `ECS Task`                           | ECS에서 실행되는 컨테이너 작업 단위                                                        |
| `ECS Service`                        | ECS Task 수를 유지하고 배포를 관리하는 ECS 리소스                                          |
| `Task Definition`                    | ECS Task가 사용할 이미지, 포트, 환경변수, 로그 설정 정의                                   |
