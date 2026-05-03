# 기존 프로젝트와 신규 실구축 프로젝트 비교

`cloug_infra` 기존 문서화 프로젝트와 `new_project_root` 신규 팀 실구축 프로젝트의 범위 차이와 적용
항목 정리

---

## 1. 비교 결론

기존 프로젝트는 Phase 1-7 전체 인프라 학습/문서화 로드맵이고, 신규 프로젝트는 13일 안에 구현하고 3일
안에 발표해야 하는 실구축 프로젝트임. 따라서 기존 프로젝트의 모든 요소를 가져오면 일정이 무너질 수
있음.

신규 프로젝트에는 다음 기준으로 선별 적용함.

- **즉시 적용:** 보안 가드레일, 내부망 분리, Runbook, 백업/복구 검증, 환경 자동화
- **부분 적용:** Ceph, PXC/ProxySQL, CloudWatch/관측성, Marp 발표 자동화
- **보류:** EKS 전면 구축, Istio, Thanos, AI/KEDA 예측 확장, 전체 Proxmox HA

---

## 2. 영역별 비교

| 영역     | 기존 `cloug_infra`                       | 신규 `new_project_root` 적용                      |
| :------- | :--------------------------------------- | :------------------------------------------------ |
| 목적     | Phase 1-7 문서화와 실습 로드맵           | 13+3 일정의 팀 실구축/발표                        |
| 네트워크 | 온프레미스, MacVLAN, VPN, AWS 연동       | AWS VPC, ALB, App/Data Private Subnet             |
| 보안     | SSH 하드닝, auditd, pre-commit, Gitleaks | OIDC, SG 최소 허용, WAF, Gitleaks, DB 내부망      |
| 데이터   | Galera/PXC, ProxySQL, Ceph/MinIO         | RDS 제외, PXC 3노드, ProxySQL, Ceph RGW 백업      |
| 관측성   | Prometheus/Grafana/Thanos, APM           | CloudWatch 우선, DB/Ceph 상태 체크는 Runbook 중심 |
| 자동화   | Terraform, Ansible, GitOps, Helm         | Terraform, GitHub Actions, pre-commit, Marp       |
| 발표     | Marp 기반 발표 자료                      | Marp 원본과 PDF 변환 스크립트 적용                |

---

## 3. 신규 프로젝트에 이미 적용한 항목

- Prettier, Husky, pre-commit, Gitleaks 기반 로컬 품질/보안 검사
- GitHub Actions OIDC 기반 키 없는 배포
- Public/App Private/Data Private 계층 분리
- DB 포트 인터넷 공개 금지 원칙
- SSM Session Manager 기반 DB EC2 운영 접속 원칙
- PXC + ProxySQL + Ceph RGW 백업 전략
- Runbook 기반 배포/롤백/DB 장애/백업 검증
- Marp CLI 기반 발표 PDF 생성

---

## 4. 일정 부족으로 보류한 항목

| 항목              | 보류 이유                                              | 향후 적용 조건                        |
| :---------------- | :----------------------------------------------------- | :------------------------------------ |
| EKS 전면 구축     | 13일 안에 VPC/EKS/Ingress/GitOps/관측성 안정화 부담 큼 | ECS MVP 완료 후 확장                  |
| Istio 서비스 메시 | mTLS와 트래픽 제어 설명은 좋지만 구현/디버깅 비용 큼   | EKS 도입 이후                         |
| Thanos/Loki 통합  | CloudWatch만으로도 MVP 관측성 충분                     | 멀티 클러스터 또는 장기 로그 요구 시  |
| AI/KEDA 예측 확장 | 발표 범위 대비 과도함                                  | 기본 Auto Scaling 검증 이후           |
| Proxmox HA 전체   | 신규 프로젝트는 AWS 실구축 중심                        | 온프레미스 시연 환경이 별도 확보될 때 |

---

## 5. 추가 적용하면 좋은 항목

### 5.1 SSM 우선 운영 접속

DB EC2와 ProxySQL EC2는 SSH 포트를 열지 않고 SSM Session Manager로 접속함. 이는 기존 프로젝트의 SSH
하드닝 원칙을 AWS에 맞게 적용한 방식임.

### 5.2 백업 복구 리허설

백업 업로드만으로는 부족함. 최소 1회는 백업 파일 목록, 체크섬, 복구 절차까지 문서화해야 발표
설득력이 높아짐.

### 5.3 콘솔 수작업의 Runbook 반영

13일 일정에서는 일부 콘솔 수작업이 생길 수 있음. 수작업이 발생하면 반드시 Runbook에 남겨 재현성을
확보함.

### 5.4 DB 내부망 보안 검증

발표 전 다음 항목을 캡처 또는 명령 결과로 확보함.

- DB EC2 Public IP 없음
- ProxySQL `6033`은 ECS SG에서만 허용
- PXC `3306`은 ProxySQL SG에서만 허용
- Galera `4567/4568/4444`는 PXC SG self 참조만 허용
- ProxySQL Admin `6032`는 SSM/Bastion 관리 경로로만 접근

---

## 6. 최종 권장 범위

13+3 일정 기준 최종 범위는 다음으로 고정하는 것을 권장함.

1. ALB + ECS Fargate 첫 배포
2. GitHub Actions OIDC 자동 배포
3. App/Data Private Subnet 분리
4. RDS 제외, PXC 3노드 + ProxySQL 1대 MVP
5. 앱은 ProxySQL endpoint로만 DB 접근
6. 일정 여유 시 ProxySQL 2대 + Internal NLB로 단일 장애점 보완
7. XtraBackup → Ceph RGW 백업 업로드
8. CloudWatch와 Runbook 기반 장애/복구 시연
9. Marp 발표 자료와 PDF 산출
