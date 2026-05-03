# 모니터링 Runbook

## 1. 관측 대상

| 대상 | 지표                      | 목적             |
| :--- | :------------------------ | :--------------- |
| ALB  | Request Count             | 트래픽 추세 확인 |
| ALB  | Target Response Time      | 지연 시간 확인   |
| ALB  | HTTPCode_Target_5XX_Count | 앱 오류 감지     |
| ALB  | UnHealthyHostCount        | Task 장애 감지   |
| ECS  | CPUUtilization            | 스케일링 판단    |
| ECS  | MemoryUtilization         | 메모리 부족 감지 |
| ECS  | RunningTaskCount          | 서비스 유지 확인 |
| Logs | ERROR/WARN                | 앱 오류 추적     |

## 2. 알람 기준

- ALB Target 5xx 5분 합계 5회 이상
- UnHealthyHostCount 1 이상
- ECS CPU 80% 이상 5분 지속
- ECS Memory 80% 이상 5분 지속

Terraform 기준:

- `aws_cloudwatch_metric_alarm.alb_5xx`
- `aws_cloudwatch_metric_alarm.alb_unhealthy_hosts`
- `aws_cloudwatch_metric_alarm.ecs_cpu_high`
- `aws_cloudwatch_metric_alarm.ecs_memory_high`
- `aws_appautoscaling_policy.ecs_cpu`

## 3. 확인 절차

1. CloudWatch Dashboard 확인
2. ECS Service Events 확인
3. CloudWatch Logs에서 오류 검색
4. Target Group Health 확인
5. 최근 배포 이력 확인

## 4. 발표용 관측 포인트

- 배포 전후 로그가 같은 Log Group에 쌓이는지 확인
- 장애 Task가 비정상 Target으로 표시되는지 확인
- 알람이 어떤 지표를 기준으로 울리는지 설명
- Auto Scaling 정책은 CPU target tracking이며, Memory 알람은 감지용임을 구분해 설명
