# 모니터링 Runbook

> 아키텍처 상세 참조:
> [Data / Ceph / Observability / Cost](../architecture/details/data_ceph_observability_cost.md),
> [Ops Flow / Extensions](../architecture/details/ops_flow_and_extensions.md)

## 1. 관측 대상

| 대상       | 지표                            | 목적                       |
| :--------- | :------------------------------ | :------------------------- |
| ALB        | Request Count                   | 트래픽 추세 확인           |
| ALB        | Target Response Time            | 지연 시간 확인             |
| ALB        | HTTPCode_Target_5XX_Count       | 앱 5xx 응답 감지           |
| ALB        | UnHealthyHostCount              | 앱 인스턴스 장애 감지      |
| EC2 ASG    | CPUUtilization                  | AWS burst 스케일링 판단    |
| Kubernetes | Pod Ready, Rollout              | 온프레미스 앱 상태 확인    |
| Argo CD    | Sync, Health                    | GitOps 배포 상태 확인      |
| PXC        | `wsrep` 상태                    | DB 클러스터 정상 여부 확인 |
| Ceph       | OSD 상태, pool 사용량, RGW 오류 | 스토리지 상태 확인         |
| Logs       | ERROR/WARN                      | 앱 오류 추적               |

## 2. 알람 기준

- ALB Target 5xx 5분 합계 5회 이상
- UnHealthyHostCount 1 이상
- AWS burst EC2 CPU 80% 이상 5분 지속
- Kubernetes Pod Ready 실패 또는 rollout timeout
- 부하 테스트를 수행하는 경우 p95 latency와 5xx 비율을 함께 기록

표현 의미:

- ALB Target 5xx: ALB 뒤의 앱이 반환한 `500`번대 서버 오류 수
- 5분 합계 5회 이상: 5분 동안 서버 오류가 5번 이상이면 장애 후보로 판단
- `wsrep` 상태: PXC가 Galera 복제를 정상 수행하는지 보여주는 DB 클러스터 상태값
- OSD 상태: Ceph에서 실제 디스크 저장을 담당하는 Object Storage Daemon 상태
- pool 사용량: Ceph 저장 공간 묶음별 사용량
- RGW 오류: Ceph의 S3 호환 API Gateway 요청 실패

Terraform 기준:

- `aws_cloudwatch_metric_alarm.alb_5xx`
- `aws_cloudwatch_metric_alarm.alb_unhealthy_hosts`
- `aws_cloudwatch_metric_alarm.app_cpu_high`
- `aws_autoscaling_policy.*`
- Kubernetes 또는 Prometheus/Grafana 지표는 적용 시 별도 대시보드 구성

## 3. 확인 절차

1. CloudWatch Dashboard 확인
2. Argo CD Application `Sync`/`Health` 확인
3. Kubernetes rollout과 Pod 상태 확인
4. Kubernetes logs 또는 EC2 Docker logs에서 오류 검색
5. Target Group Health와 최근 배포 이력 확인
6. PXC `wsrep_cluster_status`, `wsrep_cluster_size` 확인
7. Ceph `ceph health`, OSD, RGW 로그 확인

## 4. 로그 보존 기준

| 로그 유형      | 기본 위치                            | MVP 보존 기준  | 목적                   |
| :------------- | :----------------------------------- | :------------- | :--------------------- |
| 앱 로그        | Kubernetes logs 또는 EC2 Docker logs | 발표 기간 유지 | 장애 분석, 발표 캡처   |
| ALB/WAF 지표   | CloudWatch Metrics                   | 발표 기간 유지 | 트래픽과 차단 근거     |
| DB 로그        | EC2 local + 필요 시 CloudWatch Agent | 발표 기간 유지 | PXC/ProxySQL 장애 분석 |
| Ceph RGW 로그  | 온프레미스 로그 또는 Grafana         | 발표 기간 유지 | 백업 업로드 실패 분석  |
| 보안 감사 로그 | SSM/audit 로그 또는 GitHub Actions   | 필요 시 캡처   | 접근 추적              |

운영 기준:

- Secret, Access Key, 계정 ID가 로그에 노출되지 않도록 마스킹
- 앱 오류 로그는 `ERROR`, `WARN`, HTTP status 기준으로 검색 가능하게 유지
- 장기 보관은 MVP 필수 아님. 필요 시 Ceph RGW 또는 별도 로그 저장소로 아카이브
- 로그 파일 직접 수정 또는 삭제는 장애 분석 근거 훼손으로 간주

## 5. 부하 테스트와 확장 관측 기준

부하 테스트는 AWS EC2 ASG/ALB burst 시연을 안정화하기 위한 선택 검증으로 사용함.

| 도구   | 용도                                                               | 현재 판단                                                |
| :----- | :----------------------------------------------------------------- | :------------------------------------------------------- |
| k6     | JavaScript 기반 HTTP/API 부하 테스트, p95 latency와 threshold 확인 | JMeter 대안으로 사용 가능                                |
| JMeter | GUI/CLI 기반 HTTP/API 부하 테스트                                  | 발표용 부하 테스트 후보                                  |
| iperf  | 네트워크 대역폭 측정                                               | Ceph 스토리지망, Proxmox 노드 간 네트워크, VPN 검증 보조 |

`p95 latency`는 전체 요청 중 95%가 해당 시간 이하로 응답했다는 뜻임. 예를 들어 p95가 300ms이면 요청
100개 중 95개는 300ms 이하로 응답했다는 의미임.

KEDA(Kubernetes Event-driven Autoscaling)는 Prometheus, queue, HTTP add-on 같은 외부 지표로
Kubernetes workload를 autoscaling하는 도구임. 현재 MVP의 AWS burst는 EC2 ASG/ALB 기준이므로 KEDA는
기본 경로가 아니며, EKS 또는 온프레미스 Kubernetes autoscaling 고도화 시 선택 확장으로 검토함.

## 6. 장기 관측성 저장소 후보

Prometheus remote_write, Thanos Receiver, Loki, Fluent Bit, Ceph RGW를 조합하면 장기 지표/로그 저장
구조를 만들 수 있음. 다만 MVP에서는 CloudWatch, Kubernetes logs, EC2 Docker logs 중심으로 검증함.

개념 흐름:

```text
Metrics: Prometheus 또는 Agent → remote_write → Thanos Receiver → Ceph RGW/S3 → Thanos Query → Grafana
Logs:    Fluent Bit → Loki → Ceph RGW/S3 → Grafana
```

주의:

- Thanos Receiver 뒤에 다시 Prometheus를 두는 구조는 일반적이지 않음
- Prometheus local disk는 단기 저장소이고, 장기 보관은 Thanos + object storage가 담당함
- Loki는 로그 저장/조회 도구이고, Sentry는 앱 예외와 stack trace 추적 도구이므로 목적이 다름

## 7. 발표용 관측 포인트

- 배포 전후 Kubernetes 또는 EC2 Docker 로그에서 같은 image tag가 확인되는지 점검
- 장애 Pod 또는 AWS burst app이 비정상 Target으로 표시되는지 확인
- 알람이 어떤 지표를 기준으로 울리는지 설명
- Auto Scaling 정책은 AWS EC2 ASG와 Kubernetes replica 조정 기준을 구분해 설명
