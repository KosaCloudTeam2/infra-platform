# 예상 질문과 답변

## Q1. 왜 ECS Fargate를 선택했나?

13일 구축 일정에서 서버 패치, 오토스케일링, 컨테이너 배포를 모두 직접 관리하기에는 범위가 큼. ECS
Fargate는 서버 관리 부담을 줄이고 컨테이너 배포, ALB 연동, CloudWatch 통합을 빠르게 검증할 수 있음.

## Q2. 왜 ALB를 사용했나?

프로젝트 대상이 HTTP/HTTPS 기반 웹 애플리케이션이므로 L7 라우팅, Health Check, WAF 연동이 가능한
ALB가 적합함. TCP/UDP나 고정 IP가 핵심이면 NLB를 고려함.

## Q3. GitHub Secrets에 AWS Key를 넣지 않은 이유는?

장기 Access Key는 유출 시 피해가 큼. OIDC 기반 Role Assume 방식은 배포 시점에만 임시 자격 증명을
발급받으므로 운영 보안성이 높음.

## Q4. Private Subnet에 Task를 둔 이유는?

애플리케이션이 인터넷에 직접 노출되지 않도록 하기 위함. 외부 요청은 ALB를 통해서만 들어오고, ECS
Security Group은 ALB Security Group에서 오는 앱 포트만 허용함.

## Q5. 비용을 줄이려면 무엇을 조정할 수 있나?

Fargate CPU/Memory를 낮추고, 로그 보존 기간을 제한하고, NAT Gateway 수를 줄일 수 있음. 발표용
MVP에서는 고가용성과 비용 사이의 선택 기준을 명확히 설명함.
