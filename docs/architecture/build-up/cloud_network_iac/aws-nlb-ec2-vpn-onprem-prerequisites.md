# AWS NLB-EC2-VPN-OnPrem 구성 전 사전 준비 체크리스트

> Status: Unverified

본 문서는 아래 구현 문서의 공통 선행 조건을 정리함.

- CLI: `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`
- 콘솔: `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md`

---

## 1. 사전 결정값

| 항목            | 예시 값              | 비고                    |
| :-------------- | :------------------- | :---------------------- |
| AWS Region      | `ap-northeast-2`     | 전체 리소스 동일 리전   |
| 도메인          | `sjkim686.store`     | Route 53 위임 대상      |
| 앱 FQDN         | `api.sjkim686.store` | NLB Alias 연결          |
| VPC CIDR        | `10.30.0.0/16`       | 온프레 CIDR과 중복 금지 |
| Public Subnet A | `10.30.1.0/24`       | AZ-a                    |
| Public Subnet C | `10.30.2.0/24`       | AZ-c                    |
| 온프레 CIDR     | 예: `172.16.20.0/24` | 라우팅 목적지           |
| 관리자 공인 IP  | `x.x.x.x/32`         | SSH 최소 허용           |

---

## 2. AWS 계정/권한

필요 권한(최소):

- EC2, VPC, ELBv2, Route53, CloudWatch
- Site-to-Site VPN(VGW/CGW/VPN connection)
- (대안 경로) EIP/ENI/Route table 수정

---

## 3. VPC 기본 구성 (콘솔)

## 3.1 VPC 생성

1. **VPC 콘솔** → **Your VPCs** → **Create VPC**
2. Resources: `VPC only`
3. Name: `vpc-hybrid-edge`
4. IPv4 CIDR: 예) `10.30.0.0/16`
5. Tenancy: `Default`

## 3.2 Public Subnet 2개 생성

1. **Subnets** → **Create subnet**
2. `subnet-public-a` (AZ-a, `10.30.1.0/24`)
3. `subnet-public-c` (AZ-c, `10.30.2.0/24`)

## 3.3 Internet Gateway 연결

1. **Internet gateways** → **Create** (`igw-hybrid-edge`)
2. 생성 후 **Attach to VPC**

## 3.4 Route Table 설정

1. **Route tables** 생성 (`rtb-public-edge`)
2. Route 추가: `0.0.0.0/0 -> igw-hybrid-edge`
3. Subnet associations: `subnet-public-a`, `subnet-public-c`

## 3.5 Public IP 자동할당

- Subnet 설정에서 `Enable auto-assign public IPv4` 활성화

---

## 4. 키페어/접속 준비

## 4.1 키페어

- **EC2 콘솔** → **Key Pairs** → 기존 키 선택 또는 생성
- PEM 권한 설정 확인 (`chmod 400`)

## 4.2 접속 방식

- 기본: SSH (`관리자IP/32`)
- 선택: SSM Session Manager(운영 고도화 시)

---

## 5. 네트워크 중복/방화벽 점검

- AWS VPC CIDR ↔ 온프레 CIDR 중복 없는지 확인
- 온프레 방화벽에서 VPN/WireGuard 포트 허용 가능 여부 확인
- Site-to-Site VPN 경로는 온프레 공인 고정 IP 필요

---

## 6. 가비아/Route 53 준비

- 가비아 도메인 관리 권한 확인
- Route 53 Hosted Zone 생성 권한 확인
- 네임서버 전환 시 기존 MX/TXT 레코드 이관 계획 수립

---

## 7. 시작 전 최종 체크

- [ ] Region/VPC/Subnet/CIDR 확정
- [ ] 관리자 공인 IP(/32) 확정
- [ ] 온프레 공인 IP 유무 확인 (경로 A/B 결정)
- [ ] pfSense FRR/BGP 가능 여부 확인
- [ ] 도메인/레코드(`api.sjkim686.store`) 확정
