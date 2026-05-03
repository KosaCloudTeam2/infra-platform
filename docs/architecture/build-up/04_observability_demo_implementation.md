# 04 Observability / Demo Implementation

담당: 팀원 1 겸임, 팀원 4 보조

## 1. 목표

CloudWatch 기반 최소 관측 체계를 구성하고 발표에서 보여줄 정상 배포, 앱 장애, DB/백업 확인
시나리오를 안정적으로 준비함.

## 2. 사전 조건

- ECS Service와 ALB Target Group이 생성되어 있음
- CloudWatch Log Group이 Terraform으로 생성되어 있음
- DB 담당자가 PXC/ProxySQL/Ceph 상태 확인 명령을 제공함
- CI/CD 담당자가 배포 성공/실패 케이스를 재현할 수 있음

## 3. 구현 순서

1. ECS container log가 CloudWatch Logs에 기록되는지 확인
2. ALB Target 5xx, UnHealthyHostCount 지표 확인
3. ECS CPU/Memory 지표 확인
4. 최소 알람 기준을 Terraform 또는 콘솔 설정으로 확인
5. PXC/ProxySQL/Ceph 상태 확인 명령을 Runbook에 연결
6. 정상 배포 시연 순서 작성
7. 앱 장애/롤백 시연 순서 작성
8. DB/백업 확인 시연 순서 작성
9. 발표용 캡처와 예상 질문 정리

## 4. CloudWatch 확인 항목

| 대상       | 확인 항목          | 기준                            |
| :--------- | :----------------- | :------------------------------ |
| ECS Logs   | 앱 stdout/stderr   | 신규 배포 후 로그 생성          |
| ALB        | Target 5xx         | 장애 시 증가 확인               |
| ALB        | UnHealthyHostCount | Health Check 실패 시 증가       |
| ECS        | CPU/Memory         | 부하 테스트 또는 기본 지표 확인 |
| ECS Events | 배포/롤백 이벤트   | 실패 원인 추적 가능             |

## 5. 시연 절차

### 5.1 정상 배포

1. GitHub Actions workflow 실행
2. ECR 이미지 태그 확인
3. ECS Service deployment 확인
4. ALB Target Group healthy 확인
5. ALB URL로 앱 응답 확인

### 5.2 앱 장애와 롤백

1. Health Check 실패 또는 잘못된 이미지 배포 유도
2. ECS Event와 Target Group unhealthy 확인
3. Deployment Circuit Breaker 또는 수동 롤백 확인
4. 정상 응답 복구 확인

### 5.3 DB/백업 확인

1. 앱이 ProxySQL endpoint를 사용함을 확인
2. PXC `wsrep` 상태 확인
3. ProxySQL backend status 확인
4. XtraBackup 산출물과 Ceph RGW 업로드 파일 확인

## 6. 산출물

- CloudWatch Logs 캡처
- ALB/ECS 지표 캡처
- ECS Event 캡처
- DB/Ceph 상태 확인 명령과 결과
- Demo Script 업데이트
- 발표 Q&A 후보

## 7. 주의 사항

- 발표용 장애는 리허설에서 재현 시간을 측정함
- Day 14 이후에는 신규 관측 도구 추가보다 캡처와 Runbook 검증을 우선함
- Prometheus, Grafana, PMM은 선택 확장으로 분리함
- 장애 유도 후 리소스가 정상 상태로 돌아왔는지 반드시 확인함
