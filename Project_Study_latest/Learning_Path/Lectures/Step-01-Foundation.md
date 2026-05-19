# [Step 1] 아키텍처 비전과 물리적 토대 (Lecture)

1. 학습 목표
   - 프로젝트 비즈니스 배경 및 오픈런 시나리오 이해
   - 하이브리드 클라우드 채택 근거 및 타당성 습득
   - 물리 네트워크(VLAN) 및 가상화(Proxmox) 아키텍처 파악

2. 주요 아키텍처 결정 사항 (Architecture Decision)
   - 영역별 선택 사항 및 결정 사유 요약
     - 인프라 모델: 하이브리드 (AWS + 온프레미스) / 비용 절감 및 탄력성 확보
     - 가상화: Proxmox (KVM 기반) / 오픈소스 표준 준수 및 라이선스 비용 절감
     - 네트워크 HA: pfSense (CARP) / 게이트웨이 가용성 확보 및 SPoF 제거

3. 네트워크 토폴로지 분석 (Big Picture)
   - ![전체 시스템 토폴로지](../../Project_docs_finals/assets/01-big-picture.png)
   - 핵심 구성 요소 및 역할
     - Edge HAProxy: 외부 트래픽 수용 및 로드밸런싱 (VLAN 20)
     - pfSense HA: L3 라우팅, 방화벽 및 CARP VIP 기반 이중화 수행
     - 10G Spine-Leaf: Ceph 스토리지 전용 고속 백본망 구축

4. pfSense 이중화 메커니즘 (Mermaid Diagram)
   - ```mermaid
     graph TD
         Client[사용자 요청] --> VIP[pfSense CARP VIP]
         VIP --> Master[pfSense Primary: MASTER]
         Master -. pfsync 세션 동기화 .-> Backup[pfSense Secondary: BACKUP]
         Master -- 장애 발생 시 --> Backup
         Backup --> Internal[내부 VLAN 트래픽]
     ```

5. 발표용 질의응답 대응 (Talking Points)
   - 하이브리드 채택 이유: 피크 트래픽 대응의 경제성 및 클라우드 버스팅(Cloud Bursting) 효율성 강조
   - pfSense 이중화 검증: CARP 기반 VIP 공유 및 3초 이내 페일오버, pfsync를 통한 무중단 세션 보장
     설명
   - 10G 전용망 필요성: 스토리지 복제 트래픽과 서비스 트래픽의 물리적 분리를 통한 성능 간섭 방지
     명시

---

[Step 2로 이동 →](./Step-02-Storage.md)
