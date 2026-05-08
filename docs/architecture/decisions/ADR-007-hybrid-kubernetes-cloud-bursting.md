# ADR-007: 비용 우선 하이브리드 Kubernetes와 AWS EC2 버스팅

## 상태

Accepted

## 날짜

2026-05-04

## 배경

프로젝트 목표가 온프레미스 Proxmox에서 Kubernetes를 직접 운영하고, 부하가 높아질 때 AWS 클라우드
자원을 일시적으로 늘린 뒤 부하가 줄면 다시 release하는 구조로 조정됨.

처음 검토한 EKS Hybrid Nodes 구조는 온프레미스와 AWS 노드를 하나의 EKS 관리형 Kubernetes 운영 모델로
묶을 수 있다는 장점이 있음. 그러나 비용을 최대한 줄이는 것이 우선 조건이므로 EKS control plane 상시
비용과 EKS Hybrid Nodes 비용을 피하는 방향을 우선함.

2026-05-08 보강: AWS에서 Kubernetes를 구성할 때 EKS는 필수는 아니지만 관리형 Kubernetes 경험 확보
측면에서는 권장됨. 따라서 본 프로젝트는 EKS를 운영 런타임으로 전환하지는 않되, 클러스터 생성, 샘플
앱 배포, 삭제 검증 수준의 EKS 최소 PoC를 MVP 보조 산출물로 포함함.

## 결정

MVP 운영 구조는 **온프레미스 Kubernetes + AWS EC2 ASG/ALB burst**로 잡고, EKS는 최소 PoC로 제한해
포함함.

권장 목표 구조:

- 온프레미스 Proxmox VM 위에 Kubernetes 직접 구성
- 기본 트래픽은 온프레미스 Kubernetes에서 처리
- AWS는 별도 burst 영역으로 구성
- AWS burst 영역은 EC2 Auto Scaling Group, Launch Template, ALB Target Group, CloudWatch Alarm을
  사용
- 부하 증가 시 AWS EC2 인스턴스를 자동 생성하고 ALB Target Group에 등록
- 부하 감소 시 AWS EC2 인스턴스를 scale-in으로 종료
- Ceph RBD/CephFS는 온프레미스 Kubernetes와 Proxmox 볼륨 용도로 사용
- Ceph RGW는 DB 백업 또는 앱 파일 저장용 S3 호환 객체 저장소로 사용

이 구조는 **단일 Kubernetes 클러스터의 node autoscaling**이 아니라, **온프레미스 Kubernetes + AWS
EC2 Auto Scaling 기반 하이브리드 운영**임을 명확히 구분함.

## 대안

1. **EKS Hybrid Nodes + AWS cloud nodes**
   - 가장 정석적인 managed hybrid Kubernetes 구조
   - EKS control plane과 hybrid node 비용이 추가됨
   - AWS 관리형 기능을 쓰는 대신 비용 우선 조건과 맞지 않음

2. **EKS 최소 PoC**
   - 관리형 Kubernetes 생성, `kubectl` 연결, 샘플 앱 배포, 삭제 검증까지 MVP 보조 산출물로 포함
   - 운영 트래픽 처리, 고급 애드온, 하이브리드 노드 연결은 포함하지 않음
   - 비용과 일정 부담을 제한하면서 EKS 경험을 설명할 수 있음

3. **ECS Fargate 비교안 유지**
   - AWS 안에서 ECS Task Auto Scaling을 빠르게 검증 가능
   - 온프레미스 Kubernetes 운영 경험과는 맞지 않음
   - 기존 Terraform과 CI/CD를 재사용하기 쉬운 fallback 또는 비교안으로 유지 가능

4. **온프레미스 Kubernetes + AWS EC2 ASG/ALB burst**
   - EKS 비용 없이 구현 가능
   - AWS 실습 경험인 CloudWatch, Auto Scaling Group, Launch Template, ALB 흐름을 재사용 가능
   - 단일 Kubernetes 클러스터 확장은 아니지만 발표 가능한 비용 우선 하이브리드 구조로 적합함

## 영향

장점:

- EKS control plane 상시 비용을 피할 수 있음
- Proxmox와 Kubernetes 직접 운영 경험을 프로젝트 핵심으로 가져갈 수 있음
- AWS burst 영역은 EC2 Auto Scaling과 ALB로 단순하게 설명 가능함
- 부하 증가 시 클라우드 자원을 일시적으로 사용하고 줄어들면 release한다는 메시지가 명확함

감수할 점:

- 온프레미스 Kubernetes와 AWS EC2 ASG는 같은 Kubernetes cluster가 아님
- 앱 배포 방식이 온프레미스 Kubernetes와 AWS EC2 burst 영역으로 나뉠 수 있음
- 세션, 파일 업로드, DB 연결, 배포 버전 동기화 기준을 별도로 정해야 함
- Terraform, GitHub Actions, Runbook 기본 경로는 EC2 ASG/ALB burst 기준으로 재정렬됨
- EKS 경험은 MVP 운영 경로가 아니라 최소 PoC 보조 산출물로 별도 설명해야 함

## 권장 적용 방식

13일 일정에서는 아래처럼 범위를 나눔.

### MVP

- EKS 최소 PoC: 클러스터 생성, Managed Node Group 최소 구성, `kubectl` 연결, 샘플 앱 배포, 삭제 검증
- Proxmox VM 기반 온프레미스 Kubernetes 구성
- 임시 앱 또는 실제 앱을 Kubernetes Deployment/Service/Ingress로 배포
- AWS에는 EC2 Auto Scaling Group, Launch Template, ALB 기반 burst 영역 구성
- CloudWatch Alarm으로 AWS EC2 scale-out/scale-in 기준 정의
- DB는 기존 원칙대로 RDS를 제외하고 PXC/ProxySQL 또는 비용상 단순화한 DB 운영안을 별도 결정
- Ceph는 온프레미스 Kubernetes PV와 RGW 백업 저장소로 역할 분리

### 선택 확장

- AWS Load Balancer Controller(ALB Ingress Controller) 기반 EKS/클라우드 Kubernetes 외부 노출 검토
- EKS Hybrid Nodes 검토
- 운영용 EKS 전환 검토
- VPN/WireGuard 기반 온프레미스-AWS 사설 통신

### 이번 범위에서 제외

- AWS EC2에 직접 Kubernetes를 설치해 온프레미스 클러스터의 worker로 붙이는 구성
- 직접 구축 단일 Kubernetes 클러스터의 AWS node 자동 증감

## 관련 문서

- [Architecture](../../01_architecture.md)
- [Implementation Scope](../../04_implementation_scope.md)
- [Structure Review](../../15_structure_review.md)
