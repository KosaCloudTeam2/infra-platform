# Risk Register

| 위험                                   | 영향                             | 가능성 | 대응                                                                       |
| :------------------------------------- | :------------------------------- | :----- | :------------------------------------------------------------------------- |
| AWS 권한 부족                          | Terraform/배포 실패              | 중     | Day 1에 권한 확인, OIDC Role 최소 권한 우선 구성                           |
| EKS 상시 비용 부담                     | 비용 초과                        | 중     | MVP에서는 EKS를 제외하고 온프레미스 K8s + AWS EC2 ASG/ALB로 구성           |
| 기존 앱 헬스체크 없음                  | ALB Target 비정상                | 높음   | `/health` 엔드포인트 추가 또는 루트 경로 Health Check 사용                 |
| Dockerfile 미완성                      | 첫 배포 지연                     | 중     | Day 2 로컬 컨테이너 실행 검증                                              |
| Terraform state 충돌                   | 인프라 드리프트                  | 중     | S3 Backend 또는 단일 담당자 apply 규칙 적용                                |
| WAF 오탐                               | 정상 요청 차단                   | 낮음   | Count 모드로 먼저 검증 후 Block 적용                                       |
| 발표 직전 기능 추가                    | 시연 불안정                      | 높음   | Day 14 이후 신규 기능 금지                                                 |
| 장기 Access Key 유출                   | 보안 사고                        | 낮음   | OIDC 사용, Access Key 미사용 원칙                                          |
| GitHub OIDC 저장소 제한 누락           | 외부 저장소에서 Role Assume 가능 | 중     | `github_repository` 값을 실제 저장소로 제한하고 plan에서 trust policy 확인 |
| ProxySQL 1대 장애                      | 앱 DB 접속 중단                  | 중     | MVP 한계로 명시, 여유 시 ProxySQL 2대 + Internal NLB 적용                  |
| PXC/ProxySQL 수동 설치 지연            | DB 계층 시연 지연                | 중     | Day 8 전 수동 Runbook 확정, 시간이 남으면 Ansible 전환                     |
| Ceph RGW 연결 방식 미확정              | 백업 업로드 실패 또는 보안 노출  | 중     | VPN 또는 제한된 IP 기반 HTTPS 중 하나를 Day 8 전 결정                      |
| Proxmox 관리 UI 노출                   | 온프레미스 관리 계층 침해        | 낮음   | 관리 UI 인터넷 공개 금지, RGW endpoint만 제한 공개                         |
| 임시 샘플 앱과 실제 앱 차이            | 교체 시 배포 실패                | 중     | Dockerfile, 포트, `/health`, Secret 주입 조건을 app README 기준으로 확인   |
| MkDocs 의존성 누락                     | 문서 사이트 실행 실패            | 낮음   | `uv sync --group dev` 후 `mkdocs-material` 설치 확인                       |
| Terraform state 로컬 보관              | 담당자 PC 장애 또는 apply 충돌   | 중     | MVP는 apply 담당자 1명, 협업 고도화 시 S3 Backend 전환                     |
| 온프레미스 K8s와 AWS burst 버전 불일치 | 장애 또는 응답 차이              | 중     | 이미지 태그를 `git-sha` 기준으로 통일하고 배포 체크리스트에 버전 확인 추가 |
| AWS burst 인스턴스 과다 생성           | 비용 초과                        | 중     | ASG Max Size를 낮게 시작하고 부하 테스트 시간을 제한                       |
| 단일 K8s 클러스터 확장으로 오해        | 발표 Q&A 혼선                    | 중     | MVP는 온프레미스 K8s + AWS EC2 ASG/ALB 별도 런타임이라고 명확히 설명       |
