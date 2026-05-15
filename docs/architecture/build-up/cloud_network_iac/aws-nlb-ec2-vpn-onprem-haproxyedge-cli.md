# AWS NLB -> EC2(HAProxy 2대) -> VPN -> On-Prem HAProxyEdge 구현 가이드 (CLI)

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
  - AWS Site-to-Site VPN(VGW + CGW)
- **경로 B (대안)**: 온프레 공인 IP 없음
  - AWS EC2(VPN Relay, EIP) + WireGuard
  - 온프레는 아웃바운드로만 AWS Relay에 접속

## 2.1 실행 위치 표기 규칙

이 문서의 명령어는 아래 위치에서 실행함.

- `[AWS-OP]` : AWS CLI가 설정된 운영자 터미널(로컬/CloudShell)
- `[EC2-HAP-A/C]` : `haproxy-a`, `haproxy-c` 인스턴스 내부 쉘
- `[EC2-RELAY]` : AWS Relay EC2 내부 쉘
- `[ONPREM-GW]` : 온프레미스 게이트웨이 내부 쉘

---

## 3. 공통: NLB/HAProxy 구성

### 3.1 HAProxy 설치

실행 위치: **[EC2-HAP-A/C]** (두 인스턴스 각각 실행)

```bash
sudo apt update
sudo apt install -y haproxy
```

`/etc/haproxy/haproxy.cfg` 예시:

```cfg
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
```

```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

### 3.2 Target Group/NLB 생성

실행 위치: **[AWS-OP]**

```bash
export AWS_REGION=ap-northeast-2
export VPC_ID=vpc-xxxxxxxx
export SUBNET_A=subnet-aaaa
export SUBNET_C=subnet-cccc
export NLB_NAME=nlb-haproxy-edge
```

```bash
aws elbv2 create-target-group \
  --name tg-haproxy-edge \
  --protocol TCP \
  --port 443 \
  --target-type instance \
  --vpc-id ${VPC_ID} \
  --health-check-protocol TCP \
  --health-check-port 443 \
  --region ${AWS_REGION}

aws elbv2 create-load-balancer \
  --name ${NLB_NAME} \
  --type network \
  --scheme internet-facing \
  --subnets ${SUBNET_A} ${SUBNET_C} \
  --region ${AWS_REGION}

aws elbv2 register-targets \
  --target-group-arn <TG_ARN> \
  --targets Id=<EC2_ID_A> Id=<EC2_ID_C> \
  --region ${AWS_REGION}

aws elbv2 create-listener \
  --load-balancer-arn <NLB_ARN> \
  --protocol TCP \
  --port 443 \
  --default-actions Type=forward,TargetGroupArn=<TG_ARN> \
  --region ${AWS_REGION}
```

---

## 4. 경로 A: 온프레 공인 IP 있음 (Site-to-Site VPN)

> 중요: Site-to-Site VPN은 **터널 2개를 모두 구성/활성화**해야 함.

### 4.0 pfSense에서 BGP 가능 여부 확인

실행 위치: **[ONPREM-GW] (pfSense 콘솔/웹UI)**

1. `System > Package Manager`에서 **FRR 패키지 설치 가능 여부** 확인
2. `Services > FRR BGP` 메뉴가 보이면 BGP 사용 가능

- BGP 가능: `Dynamic(BGP)` 권장
- BGP 불가: `Static routing` 사용

### 4.1 AWS 리소스 생성 (공통)

실행 위치: **[AWS-OP]**

```bash
# VGW 생성
aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn 64512 --region ${AWS_REGION}

# VGW attach
aws ec2 attach-vpn-gateway --vpn-gateway-id <VGW_ID> --vpc-id ${VPC_ID} --region ${AWS_REGION}

# Customer Gateway 생성(온프레 공인 IP 필요)
# ONPREM_ASN은 BGP 미사용이어도 기본 사설 ASN(예: 65000) 입력 가능
aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip <ONPREM_PUBLIC_IP> \
  --bgp-asn <ONPREM_ASN> \
  --region ${AWS_REGION}
```

### 4.2 BGP 모드 (권장)

실행 위치: **[AWS-OP]**

```bash
# VPN 생성(BGP)
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id <CGW_ID> \
  --vpn-gateway-id <VGW_ID> \
  --options StaticRoutesOnly=false \
  --region ${AWS_REGION}

# VPC 라우트 테이블: 온프레 CIDR -> VGW
aws ec2 create-route \
  --route-table-id <RTB_ID> \
  --destination-cidr-block <ONPREM_CIDR> \
  --gateway-id <VGW_ID> \
  --region ${AWS_REGION}
```

실행 위치: **[ONPREM-GW]**

- AWS에서 다운로드한 VPN 벤더 설정 파일 반영
- 터널 2개 모두 구성
- BGP 세션 2개 수립 확인

### 4.3 Static 모드 (BGP 불가 시)

실행 위치: **[AWS-OP]**

```bash
# VPN 생성(Static)
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id <CGW_ID> \
  --vpn-gateway-id <VGW_ID> \
  --options StaticRoutesOnly=true \
  --region ${AWS_REGION}

# VPN connection에 온프레 CIDR 정적 경로 등록
aws ec2 create-vpn-connection-route \
  --vpn-connection-id <VPN_ID> \
  --destination-cidr-block <ONPREM_CIDR> \
  --region ${AWS_REGION}

# VPC 라우트 테이블: 온프레 CIDR -> VGW
aws ec2 create-route \
  --route-table-id <RTB_ID> \
  --destination-cidr-block <ONPREM_CIDR> \
  --gateway-id <VGW_ID> \
  --region ${AWS_REGION}
```

실행 위치: **[ONPREM-GW]**

- AWS 다운로드 설정파일의 Static 라우팅 정보 반영
- 터널 2개 모두 구성
- 온프레 장비에 AWS VPC CIDR 정적 라우트 확인

## 4.4 터널 2개 상태 확인/장애 전환 테스트

실행 위치: **[AWS-OP]**

```bash
aws ec2 describe-vpn-connections \
  --vpn-connection-ids <VPN_ID> \
  --region ${AWS_REGION} \
  --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status,StatusMessage]' \
  --output table
```

- 정상 기준: 두 터널 모두 `Status=UP`

실행 위치: **[ONPREM-GW]**

- 터널 1 down 테스트
- 트래픽이 터널 2로 유지되는지 확인
- 터널 1 복구 후 양쪽 터널 재확인

---

## 5. 경로 B: 온프레 공인 IP 없음 (WireGuard Relay)

## 5.1 AWS Relay EC2 준비

실행 위치: **[AWS-OP]**

- Public Subnet에 EC2 1대 생성 + EIP 연결
- SG 인바운드: `UDP 51820`(온프레 NAT 공인IP 또는 허용 대역)

실행 위치: **[EC2-RELAY]**

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

## 5.2 온프레 게이트웨이 설정

실행 위치: **[ONPREM-GW]**

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

## 5.3 AWS 라우팅

실행 위치: **[AWS-OP]**

- HAProxy EC2가 있는 서브넷 라우트 테이블에
  - `ONPREM_CIDR -> AWS Relay ENI` 경로 추가

---

## 6. Route 53 + 가비아(sjkim686.store) 설정

실행 위치: **[AWS-OP]**

### 6.1 Route 53 Hosted Zone 생성

```bash
aws route53 create-hosted-zone \
  --name sjkim686.store \
  --caller-reference "sjkim686-store-$(date +%s)"
```

Hosted Zone ID 조회:

```bash
HZ_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name sjkim686.store \
  --query "HostedZones[0].Id" --output text)
echo $HZ_ID
```

Route 53 NS 조회:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id ${HZ_ID} \
  --query "ResourceRecordSets[?Type=='NS' && Name=='sjkim686.store.'].ResourceRecords[].Value" \
  --output text
```

### 6.2 가비아에서 네임서버 변경

실행 위치: **[가비아 콘솔]**

1. `sjkim686.store` 도메인 관리 진입
2. 네임서버(기본 DNS) 변경 메뉴 진입
3. Route 53 NS 4개를 그대로 입력
4. 저장 후 전파 대기(수분~최대 24~48시간)

> 주의: 기존 메일/MX/TXT 레코드가 가비아 DNS에만 있었다면 Route 53으로 먼저 이관해야 함.

### 6.3 NLB Alias 레코드 생성

실행 위치: **[AWS-OP]**

NLB DNS/Hosted Zone ID 조회:

```bash
NLB_DNS=$(aws elbv2 describe-load-balancers --names ${NLB_NAME} --region ${AWS_REGION} --query "LoadBalancers[0].DNSName" --output text)
NLB_ZONE_ID=$(aws elbv2 describe-load-balancers --names ${NLB_NAME} --region ${AWS_REGION} --query "LoadBalancers[0].CanonicalHostedZoneId" --output text)
echo ${NLB_DNS}
echo ${NLB_ZONE_ID}
```

`api.sjkim686.store` Alias A 생성:

```bash
cat > r53-alias.json <<EOF
{
  "Comment": "api.sjkim686.store -> NLB alias",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.sjkim686.store",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${NLB_ZONE_ID}",
          "DNSName": "dualstack.${NLB_DNS}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id ${HZ_ID} \
  --change-batch file://r53-alias.json
```

DNS 조회 확인:

```bash
nslookup api.sjkim686.store
```

## 7. 검증

실행 위치: **[AWS-OP]**

```bash
# NLB 타깃 헬스
aws elbv2 describe-target-health --target-group-arn <TG_ARN> --region ${AWS_REGION}

# Site-to-Site 경로일 때
aws ec2 describe-vpn-connections --vpn-connection-ids <VPN_ID> --region ${AWS_REGION}
```

실행 위치: **[EC2-RELAY]**, **[ONPREM-GW]** (경로 B)

```bash
sudo wg show
```

- Target `healthy`
- (경로 A) 터널 2개 `UP`
- (경로 B) `latest handshake` 갱신
- `api.sjkim686.store`가 NLB로 해석됨
- 외부에서 `api.sjkim686.store:443` 접속 성공
