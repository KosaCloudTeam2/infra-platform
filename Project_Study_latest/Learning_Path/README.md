# KOSA Team2 온프레미스 인프라: 단계별 학습 경로

1. 프로젝트 개요

- 프로젝트 핵심 내용을 5단계로 구분하여 정리한 학습 가이드임.
- 신입 엔지니어 대상 전체 아키텍처 이해 및 최종 발표 핵심 Talking Point 학습을 목표로 함.

2. 📂 문서 구조

- 학습 목적에 따른 두 가지 형태의 문서 제공
  - [가이드 (Guides)](./Guides/): 상세 설명 및 이야기 형식의 입문용 상세 문서임.
  - [강의교안 (Lectures)](./Lectures/): 핵심 요약, 불렛 포인트, 발표 멘트 위주의 복습 및 발표 준비용
    문서임.

3. 🗺️ 학습 로드맵 (5 Steps)

- [Step 1] 아키텍처 비전과 물리적 토대
  - 핵심: 티켓 오픈런 시나리오 기반의 인프라 구축 배경 및 비전 이해
  - 주요 내용: 하이브리드 클라우드 결정, VLAN 격리 설계, pfSense HA 구성, Proxmox 가상화 환경 구축
  - 문서: [가이드](./Guides/Step-01-Foundation.md) | [교안](./Lectures/Step-01-Foundation.md)
- [Step 2] 소프트웨어 정의 스토리지 (Ceph)
  - 핵심: 데이터의 안전한 저장 및 분산 처리 메커니즘 파악
  - 주요 내용: Ceph 분산 스토리지 아키텍처, CRUSH 알고리즘, RBD(블록) 및 RGW(S3) 인터페이스 활용
  - 문서: [가이드](./Guides/Step-02-Storage.md) | [교안](./Lectures/Step-02-Storage.md)
- [Step 3] 견고한 플랫폼 구축 (K8s & Security)
  - 핵심: 고가용성 서비스 실행을 위한 플랫폼 인프라 및 보안 체계 수립
  - 주요 내용: HA Kubernetes 클러스터 구성, CNI(Calico) 및 MetalLB 적용, 자체 CA 및 이중 TLS 보안
    강화
  - 문서: [가이드](./Guides/Step-03-Platform.md) | [교안](./Lectures/Step-03-Platform.md)
- [Step 4] 지속적 전달의 자동화 (CI/CD & GitOps)
  - 핵심: 코드 변경사항의 자동 배포 및 운영 효율성 극대화
  - 주요 내용: ArgoCD 기반 Pull 모델 구현, Harbor(Registry), Jenkins(Agent-as-Pod), Kaniko 이미지
    빌드 프로세스 구축
  - 문서: [가이드](./Guides/Step-04-CICD.md) | [교안](./Lectures/Step-04-CICD.md)
- [Step 5] 운영의 실제와 클라우드 확장
  - 핵심: 시스템 가용성 유지 및 하이브리드 클라우드 확장 전략 실행
  - 주요 내용: Prometheus/Grafana 통합 관측성 확보, 장애 대응(Failover) 검증, AWS 하이브리드 VPN
    연동 및 확장
  - 문서: [가이드](./Guides/Step-05-OpsCloud.md) | [교안](./Lectures/Step-05-OpsCloud.md)

4. 💡 학습 팁

- 각 단계별 의사결정 배경("Why") 섹션 학습을 통한 발표 논리 보강 권장
- 기술 용어 이해 필요 시 `Project_docs_finals/00-README.md` 내 사전 지식 체크리스트 활용 요망
- 상세 명령어 및 IP 정보 확인은 프로젝트 루트의 `CLAUDE.md` 참조함.
