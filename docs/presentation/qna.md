# 예상 질문과 답변

## Q1. 왜 온프레미스 Kubernetes와 Argo CD를 MVP에 포함했나?

비용을 줄이면서 Kubernetes 운영 경험과 GitOps 배포 흐름을 보여주기 위함. 기본 앱은 온프레미스
Kubernetes에서 실행하고, Argo CD는 Git 저장소의 manifest를 클러스터에 동기화함. ECS Fargate는
AWS-only fallback 또는 비교안으로만 유지함.

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

EKS control plane을 제외하고, EC2 burst 최소/최대 용량을 낮추고, NAT Gateway 수와 로그 보존 기간을
제한할 수 있음. 발표용 MVP에서는 고가용성과 비용 사이의 선택 기준을 명확히 설명함.
