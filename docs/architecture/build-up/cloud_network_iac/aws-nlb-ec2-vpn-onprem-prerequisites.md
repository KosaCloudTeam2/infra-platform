# AWS 하이브리드 연결 사전 준비 체크리스트

> **목적**: 온프레미스-AWS 간 Site-to-Site VPN 구축 전 필요한 네트워크 환경 및 결정 사항을
> 점검합니다. **대상 독자**: 인프라 운영자, 네트워크 관리자 **실행 위치**: 온프레미스(pfSense,
> Bastion), AWS Console

---

## 1. 개요 (Master Plan 연계)

본 문서는 `14-aws-hybrid.md`에서 정의한 **Phase 1(인프라) 및 Phase 2(VPN)** 구축을 위한 사전 설계
단계입니다.

### 핵심 원칙

- **IP 대역 비중첩**: 온프레미스(172.16.0.0/12)와 AWS(10.20.0.0/16) 대역은 절대 겹치지 않아야
  합니다.
- **VPN 주도권**: pfSense가 AWS로 먼저 연결을 시도(Initiator)하므로, 대부분의 상단 공유기 환경에서
  별도 설정 없이 연결 가능합니다.

---

## 2. 필수 실측값 확인 (Value Discovery)

구축 전 아래 명령어를 통해 실제 운영 중인 환경의 값을 확정합니다.

### 2.1 온프레미스 인터넷 출구 공인 IP

AWS CGW(Customer Gateway) 등록 시 pfSense WAN IP가 아닌, **최외곽 라우터의 공인 IP**를 사용해야
합니다.

```bash
# [BASTION] 또는 로컬 단말에서 확인
curl -s https://ifconfig.me/ip
```

> **팀2 실측값**: `125.131.208.229`

### 2.2 온프레미스 백엔드 및 CIDR 범위

AWS HAProxy가 트래픽을 넘길 실제 대상과 라우팅 범위를 확정합니다.

| 항목             | 확인 방법                      | 실측 예시                      |
| :--------------- | :----------------------------- | :----------------------------- |
| **Edge HAProxy** | `hostname -I` (Edge VM)        | `172.16.22.10`, `172.16.22.11` |
| **MetalLB VIP**  | `kubectl get svc -A` (Bastion) | `172.16.23.50`                 |
| **라우팅 범위**  | 현재 AWS 실측 Route Table 기준 | `172.16.0.0/12` (슈퍼넷)       |

---

## 3. 외부 도메인 연결 전략 선결정

`sjkim686.store`를 외부 진입 도메인으로 사용할 경우, 아래 두 방식 중 하나를 선택합니다.

### 방식 A: 외부/내부 Host 통일 (단순)

- 예: `ticket.sjkim686.store`를 전체 구간에 적용.
- 장점: 설정이 단순함.

### 방식 B: 외부 Host -> 내부 Host Rewrite (권장)

- 목표: 외부 `sjkim686.store` 접속 시 내부에서는 `ticket.kosa.team2`로 라우팅.
- **필수 사전 작업**:
  1. Edge HAProxy 인증서 SAN 확장 (`*.kosa.team2` + `sjkim686.store`).
  2. Edge HAProxy `frontend https-in`에 `http-request set-header Host ticket.kosa.team2` 규칙 추가.

---

## 4. 최종 체크리스트

- [ ] **AWS 계정 권한**: EC2, VPC, VPN, Route53 생성 권한 확인.
- [ ] **관리자 공인 IP**: SSH 접속을 허용할 본인 PC의 공인 IP(`/32`) 확인.
- [ ] **pfSense 지원**: FRR 패키지 설치 가능 여부 및 IPsec 메뉴 확인.
- [ ] **NAT-T 확인**: pfSense가 NAT 뒤에 있을 경우 IPsec P1 설정에서 `NAT Traversal: Force`가
      필수임을 인지.

---

[14. AWS 하이브리드 결과 보고서](../../../Project_Study_latest/Project_docs_finals/14-aws-hybrid.md)
| [구현 핸드북 (CLI)](./aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md)
