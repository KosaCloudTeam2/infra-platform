# 아키텍처 상세: 운영 흐름 / 확장 항목

이 문서는 전체 아키텍처 문서의 **Level 2(상세 시퀀스/운영 절차)** 링크 허브임.

- Level 0(통합): [01_architecture.md](../../01_architecture.md)
- Level 1(서브시스템): [network_and_lb.md](./network_and_lb.md),
  [runtime_cicd_security.md](./runtime_cicd_security.md),
  [data_ceph_observability_cost.md](./data_ceph_observability_cost.md)

## 1. 운영 절차 연결

- 배포: [runbooks/deployment.md](../../runbooks/deployment.md)
- 롤백: [runbooks/rollback.md](../../runbooks/rollback.md)
- 모니터링: [runbooks/monitoring.md](../../runbooks/monitoring.md)
- 장애 시나리오: [runbooks/incident_scenarios.md](../../runbooks/incident_scenarios.md)

## 2. 확장 항목(선택)

- Route 53 / ACM HTTPS
- ProxySQL 2대 + Internal NLB
- PMM 또는 고급 관측성
- EKS 운영 전환 검토(현재 MVP 외)

## 3. 전환 메모

- 본 문서군은 2026-05-09부터 단계적으로 분리 적용함
- 레거시 단일 문서 기준 탐색은 1주(2026-05-16까지) 안내 후 정리함
