# 예상 질문과 답변

## Q1. 왜 온프레미스 Kubernetes와 Argo CD를 MVP에 포함했나?

비용을 줄이면서 Kubernetes 운영 경험과 GitOps 배포 흐름을 보여주기 위함. 기본 앱은 온프레미스
Kubernetes에서 실행하고, Argo CD는 Git 저장소의 manifest를 클러스터에 동기화함. ECS Fargate는
MVP에서 제외하고 AWS-only 비교안으로만 유지함.

## Q2. 왜 ALB를 사용했나?

프로젝트 대상이 HTTP/HTTPS 기반 웹 애플리케이션이므로 L7 라우팅, Health Check, WAF 연동이 가능한
ALB가 적합함. TCP/UDP나 고정 IP가 핵심이면 NLB를 고려함.

## Q3. GitHub Secrets에 AWS Key를 넣지 않은 이유는?

장기 Access Key는 유출 시 피해가 큼. OIDC 기반 Role Assume 방식은 배포 시점에만 임시 자격 증명을
발급받으므로 운영 보안성이 높음.

## Q4. AWS burst 앱과 DB를 Private Subnet에 두는 이유는?

애플리케이션과 DB가 인터넷에 직접 노출되지 않도록 하기 위함. 외부 요청은 ALB 또는 온프레미스
Ingress를 통해 들어오고, DB 접근은 ProxySQL endpoint로 제한함.

## Q5. 비용을 줄이려면 무엇을 조정할 수 있나?

EKS 최소 PoC는 생성, 샘플 앱 배포, 삭제 검증까지만 수행하고, 운영용 EKS control plane 전환은 제외함.
EC2 burst 최소/최대 용량을 낮추고, NAT Gateway 수와 로그 보존 기간을 제한할 수 있음. 발표용
MVP에서는 고가용성과 비용 사이의 선택 기준을 명확히 설명함.

## Q6. EKS를 어느 범위까지 사용했나?

AWS에서 Kubernetes를 운영하는 표준 관리형 선택지는 EKS이므로, 본 MVP에는 EKS 최소 PoC를 포함함.
범위는 클러스터 생성, `kubectl` 연결, 샘플 앱 배포, 삭제 검증까지로 제한함. 운영 트래픽 처리는
온프레미스 Proxmox Kubernetes와 AWS EC2 Auto Scaling Group/ALB burst 구조가 담당하며, 운영용 EKS
전환은 비용과 일정상 향후 확장으로 분리함.

## Q7. ALB Ingress Controller와 현재 ALB burst는 무엇이 다른가?

현재 MVP의 ALB는 Terraform으로 생성한 AWS ALB와 Target Group이며, AWS EC2 ASG의 앱 인스턴스로
트래픽을 분산함. AWS Load Balancer Controller(ALB Ingress Controller)는 Kubernetes Ingress를 AWS
ALB와 연동하는 EKS/클라우드 Kubernetes 확장 기능이므로 MVP 경로와 분리함.

## Q8. PXC를 쓰면 active-active DB 구조인가?

PXC는 Galera/wsrep 기반이라 multi-primary 쓰기를 지원하지만, MVP에서는 ProxySQL로 writer를 1대로
제한하는 Single Writer 운영을 우선함. active-active write는 충돌과 장애 분석이 복잡하므로 발표에서는
복제와 고가용성 기반으로 설명함.

## Q9. k6, JMeter, iperf는 어디에 쓰나?

k6 또는 JMeter는 ALB endpoint에 HTTP 부하를 만들어 AWS EC2 ASG scale-out과 p95 latency를 확인하는 데
사용함. iperf는 앱 부하가 아니라 Proxmox/Ceph 스토리지망, VPN 같은 네트워크 대역폭 검증에 사용함.

## Q10. KEDA나 Karpenter를 쓰지 않는 이유는?

KEDA는 Kubernetes workload autoscaling, Karpenter는 주로 EKS node provisioning 고도화에 적합함. 현재
MVP의 AWS burst는 EC2 ASG/ALB 기준이므로 기본 경로에 넣지 않음. EKS 운영 전환이나 Kubernetes 기반
autoscaling 고도화 시 선택 확장으로 검토함.
