# 학습용 문서 목차 (초보자 + 중급자)

> 작성일: 2026-05-13
> 기반 자료: `inventory.md` (컴포넌트 32 / 함정 17 / 시연 시나리오 7)

---

## 1. 학습용 — 초보자 트랙

> **타깃 독자:** K8s/Docker 개념만 들어봄, kubectl 처음 침, Linux는 익숙
> **분량 총합:** 약 40~50페이지
> **목표:** 따라 하면서 동작하는 K8s + 워크로드 한 세트 직접 구축 가능

| # | 챕터 제목 | 한 줄 메시지 | 의존성 | 분량 |
|---|---|---|---|---|
| 1 | 프로젝트 개요 + 환경 둘러보기 | "온프레미스 K8s + AWS 하이브리드 클라우드의 전체 그림" | - | 3p |
| 2 | Proxmox 가상화 기초 | "Proxmox + Cloud-init으로 VM을 코드처럼 만든다" | 1 | 5p |
| 3 | Terraform으로 VM 7대 만들기 | "선언적 IaC — yaml 한 번 작성하고 `terraform apply`" | 2 | 6p |
| 4 | K8s 클러스터 부트스트랩 | "Ansible playbook으로 kubeadm 자동화, kubectl 첫 시도" | 3 | 6p |
| 5 | K8s 네트워크 기초 | "Pod, Service, LoadBalancer 그리고 Calico CNI" | 4 | 5p |
| 6 | Ceph 스토리지 연결 (PVC) | "Helm으로 ceph-csi-rbd 설치 → PVC 한 번에 Bound" | 4, 5 | 6p |
| 7 | Helm으로 워크로드 배포 | "PXC, Redis, Prometheus + Grafana — 한 줄로 설치" | 5, 6 | 7p |
| 8 | 우리만의 앱 배포 | "FastAPI 컨테이너 빌드 → GHCR → K8s Deployment" | 7 | 5p |
| 9 | 자동 스케일 (HPA + 부하 테스트) | "k6로 부하 만들고 Pod이 2 → 10으로 자동 늘어남" | 8 | 4p |
| 10 | 기본 트러블슈팅 | "describe / logs / port-forward — 3가지 도구로 90% 해결" | 4 이후 | 3p |

### 의존성 그래프 (초보자)

```
1 프로젝트 개요
    ↓
2 Proxmox 가상화
    ↓
3 Terraform VM
    ↓
4 K8s 부트스트랩
    ↓
    ├── 5 네트워크 ─────────┐
    └── 6 스토리지 (Ceph) ──┤
                            ↓
                         7 Helm 워크로드
                            ↓
                         8 앱 배포
                            ↓
                         9 부하 테스트
                            
10 트러블슈팅 (4 이후 어디서든 참조)
```

---

## 2. 학습용 — 중급자 트랙

> **타깃 독자:** K8s 운영 경험 있음, HA/CSI/HPA 개념 알지만 실제 구축 경험은 X
> **분량 총합:** 약 60~80페이지
> **목표:** 설계 결정 + 운영 함정 + 디버깅 노하우 흡수

| # | 챕터 제목 | 한 줄 메시지 | 의존성 | 분량 |
|---|---|---|---|---|
| 1 | 아키텍처 설계 결정 사항 | "왜 Proxmox? 왜 외부 Ceph? 왜 PXC? — 트레이드오프 정리" | - | 5p |
| 2 | IaC 분리 패턴 (Terraform vs Ansible) | "VM 생성은 Terraform, 부트스트랩은 Ansible — 책임 경계" | 1 | 6p |
| 3 | 네트워크 설계 (VLAN + dual-NIC) | "K8s 노드에 10G Ceph NIC 추가, MTU 9000 jumbo frame" | 1, 2 | 8p |
| 4 | Ceph CSI 깊이 다이브 | "4가지 Secret 참조, ConfigMap fsid 캐시, Released PV finalizer" | 3 | 10p |
| 5 | StatefulSet 워크로드 운영 (PXC) | "Operator namespace, immutable storageClassName, Galera join 패턴" | 4 | 10p |
| 6 | HA + 장애 도메인 분리 | "etcd quorum, MetalLB ARP, cp1을 kosa4로 마이그레이션한 이유" | 1~5 | 8p |
| 7 | 관찰성 (Prometheus + Grafana) | "메트릭 수집 흐름, 핵심 대시보드, alert rule 패턴" | 5 | 6p |
| 8 | 부하 테스트 + HPA 튜닝 | "k6 시나리오 설계, scaleUp/scaleDown 정책, 결과 해석" | 7 | 6p |
| 9 | GitOps (ArgoCD) | "ApplicationSet으로 멀티 클러스터 동기화 — 패턴과 함정" | 5~7 | 5p |
| 10 | 운영 중 발견 + 개선 사이클 | "kosa3 다운 패턴 → 분석 → bastion 재배치 + 메모리 증설" | 6 | 6p |
| 11 | 디버깅 도구 모음 (advanced) | "etcdctl, ceph-csi 로그, finalizer 강제 제거, dmesg" | 4~10 | 6p |
| 12 | (보너스) AWS 하이브리드 burst 설계 | "Karpenter + Route 53 + ArgoCD ApplicationSet 향후 로드맵" | 9 | 5p |

### 의존성 그래프 (중급자)

```
1 설계 결정
    ↓
2 IaC 분리
    ↓
3 네트워크 (dual-NIC)
    ↓
4 Ceph CSI 깊이
    ↓
5 StatefulSet (PXC)
    ↓
    ├── 6 HA 패턴
    ├── 7 관찰성
    └── 8 부하/HPA
            ↓
         9 GitOps
            ↓
         10 운영 사이클
            ↓
         11 디버깅 도구
            ↓
         12 AWS 확장 (보너스)
```

---

## 3. 인벤토리 → 챕터 매핑

### 3.1 인프라 컴포넌트 (32개) → 챕터

| 컴포넌트 | 초보자 챕터 | 중급자 챕터 |
|---|---|---|
| Proxmox VE × 4 | 2 | 1, 2 |
| pfSense HA (CARP) | 2 | 3, 6 |
| Cloud-init 템플릿 | 2 | 2 |
| k8s-cp1~3 (HA control plane) | 4 | 1, 6, 10 |
| k8s-w1~3 (workers) | 4 | 1 |
| bastion | 4 | 2, 6, 10 |
| containerd 2.2.1 | 4 | 2 |
| Calico CNI | 5 | 3 |
| MetalLB | 5 | 3, 6 |
| cert-manager | 5 (간단 언급) | 7 |
| Ceph 클러스터 (외부 6노드) | 6 | 4 |
| Ceph Pool ceph-rbd-team2 (Proxmox) | 6 | 4 |
| Ceph Pool team2-k8s-pvc-rbd | 6 | 4 |
| ceph-csi-rbd 3.16.2 | 6 | 4 |
| StorageClass team2-rbd-block | 6 | 4 |
| ceph-csi Secret 4종 | 6 | 4 |
| Ceph User client.team2-k8s-csi | 6 | 4 |
| Percona Operator | 7 | 5 |
| PXC 8.0.36-28.1 | 7 | 5 |
| ProxySQL | 7 | 5 |
| Redis Sentinel | 7 | 5 |
| Prometheus | 7 | 7 |
| Grafana | 7 | 7 |
| ArgoCD | 7 (간단) | 9 |
| ticket-app (FastAPI) | 8 | 8 |
| ticket-app DB Secret | 8 | 8 |
| ticket-app DB schema | 8 | 5 |

### 3.2 디버깅 함정 (17개) → 챕터

| 함정 | 초보자 챕터 | 중급자 챕터 |
|---|---|---|
| 1. PVC Pending — finalizer 잔재 | 10 | 4, 11 |
| 2. ceph-csi Secret 참조 4종 누락 | (X) | 4 |
| 3. ConfigMap fsid placeholder 캐시 | (X) | 4 |
| 4. PXC Operator WATCH_NAMESPACE | (X) | 5 |
| 5. PXC storageClassName immutable | (X) | 5 |
| 6. 옛 STS + PVC 잔재 | (X) | 5, 11 |
| 7. MetalLB IP pool VLAN 불일치 | 5 | 3, 6 |
| 8. ImagePullBackOff (GHCR private) | 8 | 9 |
| 9. Docker 이미지 이름 대문자 | 8 | 2, 9 |
| 10. cp1 자주 OOM | 10 | 6, 10 |
| 11. kosa3 호스트 다운 | 10 | 10 |
| 12. etcd leader change 빈번 | 10 | 6, 10, 11 |
| 13. K8s API connection refused | 10 | 6, 11 |
| 14. newgrp docker 비밀번호 요구 | 10 | (X) |
| 15. docker 그룹 변경 미적용 | 10 | (X) |
| 16. helm install 이름 중복 | 7 | 9 |
| 17. ticket-app env 이름 미스매치 | 8 | 5 |

### 3.3 시연 시나리오 (7개) → 챕터

| 시나리오 | 초보자 챕터 | 중급자 챕터 |
|---|---|---|
| 1. 좌석 페이지 + 예약 | 8 | 5, 8 |
| 2. PXC 동기 복제 | 7 | 5 |
| 3. HPA 자동 스케일 | 9 | 8 |
| 4. Pod 강제 삭제 후 복구 | 9 | 6, 8 |
| 5. VM 강제 종료 (HA) | (X — 위험) | 6, 10 |
| 6. Grafana 대시보드 | 9 | 7 |
| 7. Ceph RBD 직접 확인 | 6 (간단) | 4 |

---

## 4. 작성 우선순위

### 초보자 트랙 (먼저 작성)
```
[1순위] 4 (K8s 부트스트랩), 6 (Ceph), 7 (Helm)  ← 핵심 작업
[2순위] 8 (앱 배포), 9 (HPA)                     ← 발표 어필
[3순위] 1, 2, 3 (개요+IaC)                       ← 도입부
[4순위] 5 (네트워크), 10 (트러블슈팅)             ← 보강
```

### 중급자 트랙 (그 다음)
```
[1순위] 4 (Ceph CSI 깊이), 5 (PXC), 10 (운영 사이클)  ← 차별성
[2순위] 6 (HA), 8 (부하 테스트)                       ← 핵심 어필
[3순위] 1, 2, 3 (설계 결정)                           ← 도입부
[4순위] 7, 9, 11, 12                                  ← 보강/확장
```

---

## 5. 챕터 작성 시 표준 메타 프롬프트

```
[챕터 N: 제목]
독자: 초보자 또는 중급자
분량: N페이지
구조:
  1. 한 줄 핵심 메시지
  2. 개념 (1~2 문단)
  3. 실습 (실제 명령어 + 우리 환경 결과)
  4. 함정 + 해결 (해당 챕터의 함정 매핑)
  5. 검증 체크리스트
포함 자료:
  - 인벤토리의 컴포넌트 [목록]
  - 함정 [목록]
  - 시연 시나리오 [목록]
참고 파일:
  - /Users/sangjjang/kosa_infra_project/[관련 파일들]
```

---

## 다음 단계

1. 이 목차 검토 + 확정
2. 챕터 1개씩 작성 (또는 2~3개씩 묶어서)
3. 각 챕터 작성 후 검증 (명령어 동작, 페르소나 시점)
4. 전체 통일성 보정
5. 프로젝트용 목차 별도 작성

`/Users/sangjjang/kosa_infra_project/toc-learning.md` 저장됨.
