# AWS 하이브리드 연결 구현 가이드 (Index)

> **목적**: 온프레미스-AWS 간 하이브리드 네트워크를 구축하기 위한 전체 가이드를 제공합니다.

---

## 1. 구축 로드맵

하이브리드 연결은 다음 순서로 진행됩니다.

1.  **[사전 준비 체크리스트](./aws-nlb-ec2-vpn-onprem-prerequisites.md)**
    - IP 대역 설계, 공인 IP 확인, 도메인 전략(Host Rewrite) 결정.
2.  **구현 핸드북 선택**
    - **[CLI 버전 (권장)](./aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md)**: 빠른 구축 및 자동화
      스크립트 기반.
    - **[콘솔 버전](./aws-nlb-ec2-vpn-onprem-haproxyedge-console.md)**: UI를 통한 단계별 구축 및
      교육용.
3.  **결과 확인 및 트러블슈팅**
    - **[마스터 보고서 (14. AWS 하이브리드)](../../../Project_Study_latest/Project_docs_finals/14-aws-hybrid.md)**:
      구축 결과, 비용, 트러블슈팅 사례.

---

## 2. 자동화 스캐폴드 (Draft)

반복적인 구축을 위해 아래 경로의 코드를 참고할 수 있습니다.

- **Terraform**: `./aws-nlb-ec2-vpn-onprem-automation-draft/terraform/`
- **Ansible**: `./aws-nlb-ec2-vpn-onprem-automation-draft/ansible/`

---

[14. AWS 하이브리드 마스터 보고서](../../../Project_Study_latest/Project_docs_finals/14-aws-hybrid.md)
