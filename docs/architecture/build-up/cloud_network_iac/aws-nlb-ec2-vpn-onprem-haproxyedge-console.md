# AWS NLB -> EC2(HAProxy 2대) -> VPN -> On-Prem HAProxyEdge 구현 가이드 (콘솔)

> 시작 전 선행 준비:
> [aws-nlb-ec2-vpn-onprem-prerequisites.md](./aws-nlb-ec2-vpn-onprem-prerequisites.md)

## 1. 구조

```text
Internet Client
 -> AWS NLB (Multi-AZ)
 -> EC2 HAProxy #1 / #2
 -> VPN Tunnel
 -> On-Prem HAProxyEdge
 -> On-Prem Kubernetes Ingress/Service
```

## 2. 온프레 공인 IP 유무에 따른 경로

- **경로 A (정석)**: 온프레 고정 공인 IP 있음
  - AWS Site-to-Site VPN(VGW + Customer Gateway)
- **경로 B (대안)**: 온프레 공인 IP 없음
  - AWS EC2(VPN Relay, EIP) + WireGuard

---

## 3. 공통: 콘솔 클릭 + EC2 내부 명령어

### 3.1 EC2 2대 생성 (값까지 고정)

#### 3.1.1 Launch instance 입력값

`haproxy-a`, `haproxy-c`를 각각 생성(서로 다른 AZ).

| 항목                  | 값(권장)                                |
| :-------------------- | :-------------------------------------- |
| Name                  | `haproxy-a` (AZ-A), `haproxy-c` (AZ-C)  |
| AMI                   | **Amazon Linux 2023 (AL2023)**          |
| Instance type         | `t3.small`                              |
| Key pair              | 기존 운영 키페어 선택                   |
| Network               | 대상 VPC 선택                           |
| Subnet                | 서로 다른 AZ의 Public Subnet 2개        |
| Auto-assign public IP | `Enable`                                |
| Storage               | `gp3`, 30 GiB, 암호화 `On`              |
| Metadata options      | **IMDSv2 required**                     |
| IAM instance profile  | (있으면) SSM/CloudWatch 가능한 프로파일 |

#### 3.1.2 Security Group 생성/적용

보안그룹 2개로 분리 권장.

1. `sg-nlb-edge` (NLB용)

| 유형(Type) | 프로토콜 | 포트 범위 | 소스 유형     | 원본(Source) |
| :--------- | :------- | :-------- | :------------ | :----------- |
| HTTPS      | TCP      | 443       | Anywhere-IPv4 | `0.0.0.0/0`  |

2. `sg-haproxy-edge` (EC2용)

| 유형(Type) | 프로토콜 | 포트 범위 | 소스 유형      | 원본(Source)         |
| :--------- | :------- | :-------- | :------------- | :------------------- |
| SSH        | TCP      | 22        | Custom         | `<관리자 공인IP>/32` |
| Custom TCP | TCP      | 443       | Security group | `sg-nlb-edge`        |

- `sg-haproxy-edge`를 `haproxy-a`, `haproxy-c`에 연결.
- NLB 생성 시 `sg-nlb-edge` 연결.

### 3.2 HAProxy 2대에 동일 설정 적용(명령어)

각 인스턴스에 SSH 접속 후 아래 실행:

```bash
sudo apt update
sudo apt install -y haproxy

sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<'CFG'
global
  log /dev/log local0

defaults
  mode tcp
  timeout connect 5s
  timeout client  60s
  timeout server  60s

frontend fe_tls
  bind *:443
  default_backend be_onprem_edge

backend be_onprem_edge
  option tcp-check
  server edge1 172.16.20.10:443 check
  server edge2 172.16.20.11:443 check
CFG

sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

> `172.16.20.10/11`은 실제 On-Prem HAProxyEdge 주소로 교체.

### 3.3 Target Group 생성

1. **EC2 콘솔** → **Target Groups** → **Create target group**
2. Target type: **Instances**
3. Protocol/Port: `TCP:443`
4. Health check: `TCP:443` 또는 `HTTP /healthz`
5. `haproxy-a`, `haproxy-c` 등록

### 3.4 NLB 생성

1. **EC2 콘솔** → **Load Balancers** → **Create load balancer**
2. **Network Load Balancer** 선택
3. Scheme: `internet-facing`
4. IP address type: `IPv4`
5. 2개 AZ 서브넷 선택
6. Security group: `sg-nlb-edge` 연결
7. Listener `TCP:443` 생성
8. 대상 Target Group 연결

---

## 4. 경로 A: 온프레 공인 IP 있음 (Site-to-Site VPN)

> 중요: Site-to-Site VPN은 **터널 2개를 모두 구성/활성화**해야 함.

### 4.0 pfSense에서 BGP 가능 여부 확인

1. **pfSense** → **System > Package Manager**
2. **FRR 패키지 설치 가능 여부** 확인
3. 설치 후 **Services > FRR BGP** 메뉴 확인

- BGP 가능: Dynamic(BGP) 권장
- BGP 불가: Static routing 사용

### 4.1 VGW 생성 및 연결

1. **VPC 콘솔** → **Virtual private gateways** → **Create**
2. 생성 후 **Attach to VPC**

### 4.2 Customer Gateway 생성

1. **VPC 콘솔** → **Customer gateways** → **Create**
2. 온프레미스 공인 IP 입력
3. BGP ASN 입력(Static 모드여도 기본 ASN 값은 유지 가능)

### 4.3 Site-to-Site VPN 생성

1. **VPC 콘솔** → **Site-to-Site VPN connections** → **Create**
2. Target gateway type: **Virtual private gateway**
3. Customer gateway 선택
4. Routing options 선택
   - BGP 가능: **Dynamic (BGP)**
   - BGP 불가: **Static**
5. 생성 후 **Download configuration**
6. 터널 1/터널 2 설정 파일 모두 온프레 장비에 반영

### 4.4 온프레 게이트웨이 반영(명령/설정)

- 다운로드한 벤더 설정 파일을 온프레 장비에 반영
- 터널 2개 모두 구성
- BGP 모드면 BGP peer 2개 확인
- Static 모드면 정적 라우트 양방향 확인

### 4.5 라우팅 반영

1. **VPC 콘솔** → **Route tables**
2. 앱 서브넷 라우트 테이블 선택
3. `온프레미스 CIDR -> VGW` 라우트 추가
4. Static 모드인 경우 VPN Connection의 **Static routes** 메뉴에서 온프레 CIDR 등록 확인

### 4.6 터널 2개 상태 확인/장애 전환 테스트

1. **VPC 콘솔** → **Site-to-Site VPN connections**
2. 대상 VPN 선택 → **Tunnel details** 탭 확인
3. 터널 1, 터널 2 모두 `UP`인지 확인
4. 온프레 장비에서 터널 1을 임시 down
5. 서비스 트래픽이 터널 2로 유지되는지 확인
6. 터널 1 복구 후 두 터널 다시 `UP` 확인

---

## 5. 경로 B: 온프레 공인 IP 없음 (WireGuard Relay)

### 5.1 AWS Relay EC2 준비

1. Public Subnet에 EC2 1대 생성
2. Elastic IP(EIP) 연결
3. Security Group 인바운드 `UDP 51820` 허용

### 5.2 Relay EC2 명령어 (복붙 실행)

```bash
sudo apt update
sudo apt install -y wireguard

umask 077
wg genkey | tee /tmp/relay.key | wg pubkey > /tmp/relay.pub
echo "Relay public key: $(cat /tmp/relay.pub)"

sudo tee /etc/wireguard/wg0.conf > /dev/null <<'CFG'
[Interface]
Address = 10.200.0.1/24
ListenPort = 51820
PrivateKey = REPLACE_RELAY_PRIVATE_KEY
PostUp = sysctl -w net.ipv4.ip_forward=1

[Peer]
PublicKey = REPLACE_ONPREM_PUBLIC_KEY
AllowedIPs = 10.200.0.2/32,172.16.20.0/24
CFG

sudo sed -i "s|REPLACE_RELAY_PRIVATE_KEY|$(cat /tmp/relay.key)|" /etc/wireguard/wg0.conf
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
sudo wg show
```

### 5.3 온프레 게이트웨이 명령어 예시(Linux/VM 기준)

```bash
sudo apt update
sudo apt install -y wireguard

umask 077
wg genkey | tee /tmp/onprem.key | wg pubkey > /tmp/onprem.pub
echo "OnPrem public key: $(cat /tmp/onprem.pub)"

sudo tee /etc/wireguard/wg0.conf > /dev/null <<'CFG'
[Interface]
Address = 10.200.0.2/24
PrivateKey = REPLACE_ONPREM_PRIVATE_KEY

[Peer]
PublicKey = REPLACE_RELAY_PUBLIC_KEY
Endpoint = REPLACE_RELAY_EIP:51820
AllowedIPs = REPLACE_AWS_VPC_CIDR,10.200.0.1/32
PersistentKeepalive = 25
CFG

sudo sed -i "s|REPLACE_ONPREM_PRIVATE_KEY|$(cat /tmp/onprem.key)|" /etc/wireguard/wg0.conf
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
sudo wg show
```

> `REPLACE_RELAY_PUBLIC_KEY`, `REPLACE_RELAY_EIP`, `REPLACE_AWS_VPC_CIDR` 값을 실제 값으로 치환.

### 5.4 라우팅 반영

1. **VPC 콘솔** → **Route tables**
2. HAProxy 서브넷 라우트 테이블 선택
3. `온프레미스 CIDR -> Relay ENI` 경로 추가

---

## 6. Route 53 + 가비아(sjkim686.store) 설정

### 6.1 Route 53 Hosted Zone 생성

1. **Route 53 콘솔** → **Hosted zones** → **Create hosted zone**
2. Domain name: `sjkim686.store`
3. Type: **Public hosted zone**
4. 생성 후 NS 레코드 4개 값 복사

### 6.2 가비아 네임서버 변경

1. **가비아 콘솔** → 도메인 관리 → `sjkim686.store`
2. 네임서버 변경 메뉴 진입
3. Route 53 NS 4개를 그대로 입력 후 저장
4. 전파 대기(수분~최대 24~48시간)

> 주의: 기존 가비아 DNS에만 있던 MX/TXT/SPF/DMARC 레코드는 Route 53에 먼저 이관 후 변경.

### 6.3 NLB Alias 레코드 생성

1. **Route 53 콘솔** → `sjkim686.store` Hosted zone
2. **Create record**
3. Record name: `api`
4. Record type: `A`
5. Alias: `On`
6. Route traffic to: **Alias to Network Load Balancer**
7. 대상 NLB 선택 후 저장

### 6.4 DNS 확인

- 로컬 터미널에서 `nslookup api.sjkim686.store`
- 결과가 NLB DNS로 해석되는지 확인

## 7. 검증

- **Target Groups**: 2대 `healthy`
- **Load Balancers**: NLB `active`
- 경로 A: **VPN connections** 터널 2개 `UP`
- 경로 B: Relay/온프레 양쪽 `sudo wg show`에서 handshake 갱신
- `api.sjkim686.store`가 NLB로 해석됨
- 외부 요청이 NLB -> HAProxy -> On-Prem HAProxyEdge로 전달되는지 확인
