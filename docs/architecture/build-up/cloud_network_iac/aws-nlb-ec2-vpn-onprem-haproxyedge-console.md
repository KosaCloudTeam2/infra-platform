# AWS 하이브리드 연결 구현 가이드 (콘솔)

> **목적**: AWS Management Console UI를 사용하여 하이브리드 인프라를 단계별로 구축합니다. **대상
> 독자**: GUI 환경 선호자, 인프라 구축 초심자 **실행 위치**:
> [AWS Management Console](https://console.aws.amazon.com/)

---

## 1. 아키텍처 흐름도

```mermaid
graph TD
    A[VPC 생성] --> B[Security Group 설정]
    B --> C[EC2 및 NLB 생성]
    C --> D[VPN 연결 (CGW/VGW)]
    D --> E[라우팅 및 검증]
```

---

## 2. Phase 1: AWS 인프라 셋업

### 2.1 VPC 생성 (VPC and more)

1. **VPC 서비스** → **Create VPC** 클릭.
2. **VPC and more** 선택.
3. **Name tag generation**: `kosa-tickets` 입력.
4. **IPv4 CIDR**: `10.20.0.0/16`.
5. **Availability Zones (AZs)**: `2` 선택.
6. **Public subnets**: `2`, **Private subnets**: `2` 선택.
7. **NAT gateways**: `1 per AZ` (권장) 또는 `None` (비용 절감 시).
8. **Create VPC** 클릭.

### 2.2 Security Group 구성

- **kosa-sg-public**: 80/443 (Anywhere), 22 (My IP).
- **kosa-sg-private**: 80/443 (from public SG), ICMP (from `172.16.0.0/12`).

---

## 3. Phase 2: Site-to-Site VPN 연결

### 3.1 Customer Gateway (CGW) 생성

1. **VPC 콘솔** → **Customer gateways** → **Create customer gateway**.
2. **Name**: `kosa-cgw-pfsense`.
3. **IP Address**: 온프레미스 인터넷 출구 공인 IP 입력 (예: `125.131.208.229`).
4. **BGP ASN**: `65000`.

### 3.2 Virtual Private Gateway (VGW) 생성

1. **VPC 콘솔** → **Virtual private gateways** → **Create virtual private gateway**.
2. 생성 후 **Actions** → **Attach to VPC** → 위에서 만든 VPC 선택.

### 3.3 VPN Connection 생성

1. **VPC 콘솔** → **Site-to-Site VPN connections** → **Create VPN connection**.
2. **Target gateway type**: `Virtual private gateway` 선택.
3. **Routing options**: `Static` 선택.
4. **Static IP prefixes**: `172.16.0.0/12` 입력.
5. 생성 후 **Download configuration** (Vendor: pfSense) 클릭하여 설정 파일 보관.

### 3.4 Route Propagation 활성화 (필수)

1. **VPC 콘솔** → **Route tables** → Private Subnet에 연결된 RT 선택.
2. **Route propagation** 탭 → **Edit route propagation** → VGW 체크 후 **Save**.

---

## 4. 검증

1. **VPN 터널 상태**: VPN Connection의 **Tunnel details** 탭에서 두 터널이 `UP`인지 확인.
2. **통신 테스트**: EC2(Private)에서 온프레미스 Bastion으로 `ping` 시도.

---

[사전 준비 체크리스트](./aws-nlb-ec2-vpn-onprem-prerequisites.md) |
[구현 핸드북 (CLI)](./aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md)
