# AWS NLB-EC2-VPN-OnPrem 구성 전 사전 준비 체크리스트

> Status: Unverified

본 문서는 아래 구현 문서의 공통 선행 조건을 정리함.

- CLI: `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`
- 콘솔: `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md`

자동화 스캐폴드:

- Terraform: `./aws-nlb-ec2-vpn-onprem-automation-draft/terraform/`
- Ansible: `./aws-nlb-ec2-vpn-onprem-automation-draft/ansible/`

값 확인 가이드:

- `aws-nlb-ec2-vpn-onprem-value-discovery-guide.md`

---

## 1. 사전 결정값

| 항목            | 예시 값             | 비고                                  |
| :-------------- | :------------------ | :------------------------------------ |
| AWS Region      | `ap-northeast-2`    | 전체 리소스 동일 리전                 |
| 도메인          | `sjkim686.store`    | Route 53 위임 대상                    |
| 앱 FQDN         | `ticket.kosa.team2` | 기본값(현재 Edge ACL 허용 Host)       |
| VPC CIDR        | `10.20.0.0/16`      | 현재 AWS 실측 VPC CIDR                |
| Public Subnet A | `10.20.1.0/24`      | AZ-a                                  |
| Public Subnet C | `10.20.2.0/24`      | AZ-c                                  |
| 온프레 CIDR     | `172.16.0.0/12`     | 현재 AWS RTB에 VGW 경로로 반영된 범위 |
| 관리자 공인 IP  | `x.x.x.x/32`        | SSH 최소 허용                         |

## 1.1 현재 실측 반영 예시 (팀2)

- On-Prem Edge HAProxy #1: `172.16.22.10:443`
- On-Prem Edge HAProxy #2: `172.16.22.11:443`
- Kubernetes Ingress LB VIP(MetalLB): `172.16.23.50:443`
- 온프레 인터넷 출구 공인 IP(= CGW endpoint 공인 IP): `125.131.208.229`

검증 요약(2026-05-18):

- Site-to-Site VPN 터널 2개 `UP`
- EC2 -> `172.16.22.10/11:443` TCP 연결 성공

> 실제 운영값이 다르면 이 값을 우선 갱신함.

## 1.2 온프레 CIDR 범위 선택

현재 AWS 실측 기준:

- Private Route Table에 `172.16.0.0/12 -> VGW` 경로가 존재함
- 이 범위 안에 `172.16.22.0/24`(Edge), `172.16.23.0/24`(Internal/MetalLB),
  `172.16.24.0/24`(Bastion)가 포함됨

운영 선택지:

- 최소 범위: `172.16.22.0/24`
  - AWS -> OnPrem 경로에서 Edge HAProxy(172.16.22.10/11)만 접근하면 충분한 경우
- 중간 범위: `172.16.22.0/23`
  - Edge 뒤 MetalLB VIP 대역(`172.16.23.x`)까지 AWS에서 직접 라우팅/점검해야 하는 경우
- 현재 실측 범위: `172.16.0.0/12`
  - 온프레 전체 172.16 대역을 AWS에서 접근/검증해야 하는 경우

## 1.3 외부 도메인 연결 전략 선결정 (중요)

`sjkim686.store`를 실제 외부 진입 도메인으로 쓸 경우, 아래 두 방식 중 하나를 먼저 결정함.

### 방식 A: 외부/내부 Host 통일

- 예: `ticket.sjkim686.store`를 Edge ACL + Ingress + Route53에 동일 적용
- 장점: 단순함 (Host rewrite 불필요)

### 방식 B: 외부 Host -> 내부 Host rewrite

- 목표: 외부 `sjkim686.store`로 접속해도 내부에서는 `ticket.kosa.team2` 기준 라우팅 사용
- 적용 위치: **[EDGE-HAP]** `edge-haproxy`, `edge-haproxy2`
- 수정 파일: `/etc/haproxy/haproxy.cfg`

#### B-1) 선행 확인/인증서 준비 (Terraform 전)

1. 내부 대상 host 존재 확인 (**[BASTION]**)

```bash
kubectl get ingress -A | grep ticket.kosa.team2
```

- 결과가 없으면 rewrite해도 404 가능

2. 현재 Edge 인증서 SAN 확인 (**[EDGE-HAP] 양쪽 모두**)

```bash
sudo openssl x509 -in /etc/haproxy/certs/wildcard.pem -noout -text | grep -A1 "Subject Alternative Name"
```

- `sjkim686.store`가 SAN에 없으면 아래 절차로 교체

3. SAN 확장 인증서 발급/배포 (기존 `*.kosa.team2` 유지 + `sjkim686.store` 추가)

3-1) Edge 인증서 백업 (**[EDGE-HAP] 양쪽 모두**)

```bash
sudo cp /etc/haproxy/certs/wildcard.pem /etc/haproxy/certs/wildcard.pem.bak.$(date +%Y%m%d-%H%M%S)
```

3-2) CSR 생성용 SAN 설정 파일 작성 (**[EDGE-HAP] 1대에서 수행**)

```bash
cat > /tmp/edge-san.cnf <<'EOF'
[ req ]
distinguished_name = dn
req_extensions = req_ext
prompt = no

[ dn ]
CN = *.kosa.team2

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = *.kosa.team2
DNS.2 = kosa.team2
DNS.3 = sjkim686.store
EOF
```

3-3) 새 키/CSR 생성 (**[EDGE-HAP]**)

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /tmp/wildcard-new.key \
  -out /tmp/wildcard-new.csr \
  -config /tmp/edge-san.cnf
```

3-4) 내부 CA로 서명 (**[CA 작업 노드]**)

```bash
openssl x509 -req \
  -in /tmp/wildcard-new.csr \
  -CA <internal-ca.crt> \
  -CAkey <internal-ca.key> \
  -CAcreateserial \
  -out /tmp/wildcard-new.crt \
  -days 3650 -sha256 \
  -extensions req_ext -extfile /tmp/edge-san.cnf
```

> `<internal-ca.crt>`, `<internal-ca.key>`는 팀 내부 CA 저장 위치로 치환.

3-5) HAProxy용 PEM 생성 후 양쪽 Edge에 배포 (**[EDGE-HAP] 양쪽 모두**)

```bash
cat /tmp/wildcard-new.key /tmp/wildcard-new.crt > /tmp/wildcard-new.pem
sudo cp /tmp/wildcard-new.pem /etc/haproxy/certs/wildcard.pem
sudo chmod 600 /etc/haproxy/certs/wildcard.pem
```

3-6) 문법 검증/재기동/검증 (**[EDGE-HAP] 양쪽 모두**)

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sudo openssl x509 -in /etc/haproxy/certs/wildcard.pem -noout -text | grep -A1 "Subject Alternative Name"
```

- 최종 SAN에 `*.kosa.team2`, `kosa.team2`, `sjkim686.store`가 모두 보여야 함

#### B-2) Edge HAProxy 설정 변경

1. 백업 (**[EDGE-HAP] 양쪽 모두**)

```bash
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d-%H%M%S)
```

2. `frontend https-in` 블록을 **아래처럼 수정** (양쪽 Edge 동일 적용)

- 수정 파일: `/etc/haproxy/haproxy.cfg`
- 수정 노드: `edge-haproxy`, `edge-haproxy2`

변경 포인트:

- 기존 ACL 목록에 `ext_root` 1줄 추가
- `http-request set-header Host ticket.kosa.team2 if ext_root` 1줄 추가
- 기존 `use_backend k8s-ingress if ...` 라인에 `ext_root`를 포함

예시 (현재 팀2 설정 기준):

```cfg
frontend https-in
    bind *:443 ssl crt /etc/haproxy/certs/wildcard.pem alpn h2,http/1.1
    mode http

    # X-Forwarded-* 헤더
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Real-IP %[src]

    # 외부 root 도메인 -> 내부 host rewrite
    http-request set-header Host ticket.kosa.team2 if { hdr(host) -i sjkim686.store }

    # Host 기반 라우팅
    acl ext_root hdr(host) -i sjkim686.store
    acl ticket  hdr(host) -i ticket.kosa.team2
    acl grafana hdr(host) -i grafana.kosa.team2
    acl argo    hdr(host) -i argocd.kosa.team2
    acl harbor  hdr(host) -i harbor.kosa.team2
    acl jenkins hdr(host) -i jenkins.kosa.team2

    use_backend k8s-ingress if ext_root or ticket or grafana or argo or harbor or jenkins
    default_backend default-404
```

> `use_backend`에 `ext_root`를 포함하지 않으면 `sjkim686.store` 요청이 `default-404`로 떨어질 수
> 있음.

3. 설정 검증/적용 (**[EDGE-HAP] 양쪽 모두**)

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sudo systemctl status haproxy --no-pager
```

#### B-3) Terraform 실행 전 점검

1. 내부 host 라우팅 확인 (**[EDGE-HAP] 또는 [BASTION]**)

```bash
curl -kI https://172.16.23.50 -H 'Host: ticket.kosa.team2'
```

2. (선택) rewrite 규칙 동작 사전 확인 (**[EDGE-HAP] 또는 [BASTION]**)

```bash
# Edge VIP/주소로 접근 가능한 환경에서 수행
curl -kI https://172.16.22.5 -H 'Host: sjkim686.store'
```

> 이 단계는 Route53/NLB 전이므로 외부 도메인 해석을 기대하지 않음.

#### B-4) tfvars 값 정합성 (Terraform init 전)

방식 B를 쓰면 다음처럼 맞춤:

- `create_route53_zone = true`
- `domain_name = "sjkim686.store"`
- `create_route53_alias_record = true`
- `app_fqdn = "sjkim686.store"`

#### B-5) Terraform apply + DNS 위임 이후 외부 점검

아래는 **Terraform apply 완료 + 가비아 NS 위임 + 전파 후** 실행함.

```bash
nslookup sjkim686.store
curl -kI https://sjkim686.store
```

> 위 선행 준비가 없으면 Route53/NLB가 정상이어도 Host 불일치로 404가 발생할 수 있음.

---

## 2. AWS 계정/권한

필요 권한(최소):

- EC2, VPC, ELBv2, Route53, CloudWatch
- Site-to-Site VPN(VGW/CGW/VPN connection)
- (대안 경로) EIP/ENI/Route table 수정

---

## 3. Terraform/Ansible 적용 가능 범위

- Terraform 권장 대상
  - VPC/Subnet/IGW/Route table/SG
  - EC2(HAProxy/Relay), EIP
  - NLB/Target Group/Listener
  - VGW/CGW/VPN Connection
  - Route53 Hosted Zone/Alias Record
    - 의미: AWS DNS 서비스(Route53) 설정 생성이며, 별도 DNS 서버(BIND 등) 설치 작업이 아님
- Ansible 권장 대상
  - HAProxy 설치/설정/서비스 기동
  - WireGuard 설치/설정/서비스 기동
- 수동 대상
  - 가비아 네임서버 위임
  - pfSense FRR/BGP 설정

참조 문서:

- 현재 AWS 실측값/재구축 기준:
  [aws-site-to-site-vpn-rebuild-guide.md](./aws-site-to-site-vpn-rebuild-guide.md)

스캐폴드 시작:

0. `1.3 외부 도메인 연결 전략`(A/B) 먼저 확정

0-1. VPN 방식/사전값 확정 (**Terraform init/plan 전 필수**)

- 경로 A(Site-to-Site): `create_site_to_site_vpn=true` 여부, `customer_gateway_public_ip`,
  `customer_gateway_bgp_asn`, `onprem_cidr` 확정
- 경로 B(WireGuard Relay): `create_wireguard_relay=true` 여부, `relay_allowed_udp_cidr`,
  `onprem_cidr` 확정

> 여기서 필요한 것은 **설정값 확정**이며, 실제 터널 기동/피어 설정은 보통 `terraform apply`
> 이후(리소스 생성 후) 수행함.

1. `terraform.tfvars` 생성 후 값 입력

- `terraform.tfvars.example`를 복사한 뒤, 값 입력은 아래 가이드를 기준으로 진행
- 참조:
  [aws-nlb-ec2-vpn-onprem-value-discovery-guide.md](./aws-nlb-ec2-vpn-onprem-value-discovery-guide.md)

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 값을 먼저 수정
```

2. Terraform 초기화/Plan 실행

```bash
terraform init
terraform plan -out tfplan
```

3. Terraform Apply 실행 (담당자 1명 원칙)

```bash
terraform apply tfplan
```

- `init`/`plan`만으로는 실제 리소스가 생성/변경되지 않음
- `apply`에서 실제 반영됨
- `-out tfplan`을 쓰면 plan 시점의 변경안을 그대로 apply 가능
- 경로 B(WireGuard Relay)는 Relay EC2/EIP 생성 후 WireGuard 피어 설정 단계로 진행

4. (선택) Ansible 적용

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/haproxy.yml
```

## 4. AWS CLI로 가능한 범위/불가능한 범위

### 4.1 AWS CLI로 가능한 작업

- VPC/Subnet/IGW/Route table 생성 및 연결
- Key pair 생성
- Route 53 Hosted Zone 생성 및 NS 조회
- (후속 단계) NLB/VPN 리소스 생성

### 4.2 AWS CLI로 불가능(또는 AWS 외부) 작업

- 가비아 네임서버 변경
- 온프레 방화벽 포트 오픈
- pfSense FRR/BGP 지원 확인 및 설정

---

## 5. VPC 기본 구성 (AWS CLI, 수동 대안)

> Terraform 스캐폴드(`aws-nlb-ec2-vpn-onprem-automation-draft/terraform`)를 사용할 경우, 이
> 섹션(5)과 6, 8은 대부분 **중복 생성**되므로 보통 생략함.
>
> 현재 AWS 실측 재구축 기준은
> [aws-site-to-site-vpn-rebuild-guide.md](./aws-site-to-site-vpn-rebuild-guide.md)를 우선 참고함.
>
> - Terraform 경로: `terraform init -> plan -> apply`
> - 수동 CLI 경로: 아래 5~8 실행

### 5.1 환경변수 선언

```bash
export AWS_REGION=ap-northeast-2
export VPC_NAME=vpc-hybrid-edge
export VPC_CIDR=10.20.0.0/16
export SUBNET_A_CIDR=10.20.1.0/24
export SUBNET_C_CIDR=10.20.2.0/24
export AZ_A=ap-northeast-2a
export AZ_C=ap-northeast-2c
```

의미:

- 이후 명령에서 반복 입력할 값을 변수로 고정해 오타를 줄임.

### 5.2 VPC 생성

```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block ${VPC_CIDR} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
  --query 'Vpc.VpcId' --output text)

echo ${VPC_ID}
```

의미:

- CIDR `10.20.0.0/16`로 VPC 생성
- Name 태그 부여
- 생성된 VPC ID를 `VPC_ID` 변수에 저장

DNS 기능 활성화:

```bash
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support '{"Value":true}' --region ${AWS_REGION}
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames '{"Value":true}' --region ${AWS_REGION}
```

의미:

- EC2 내부 DNS 해석과 호스트네임 부여 활성화.

### 5.3 Public Subnet 2개 생성

```bash
SUBNET_A_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${SUBNET_A_CIDR} \
  --availability-zone ${AZ_A} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-public-a}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_C_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${SUBNET_C_CIDR} \
  --availability-zone ${AZ_C} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-public-c}]' \
  --query 'Subnet.SubnetId' --output text)

echo ${SUBNET_A_ID}
echo ${SUBNET_C_ID}
```

의미:

- 서로 다른 AZ에 Public Subnet 2개 생성(고가용성 목적).

Public IP 자동할당 활성화:

```bash
aws ec2 modify-subnet-attribute --subnet-id ${SUBNET_A_ID} --map-public-ip-on-launch --region ${AWS_REGION}
aws ec2 modify-subnet-attribute --subnet-id ${SUBNET_C_ID} --map-public-ip-on-launch --region ${AWS_REGION}
```

의미:

- 해당 Subnet에서 생성되는 EC2에 공인 IP 자동 부여.

### 5.4 Internet Gateway 생성/연결

```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=igw-hybrid-edge}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

echo ${IGW_ID}

aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID} --region ${AWS_REGION}
```

의미:

- VPC에 인터넷 출구(IGW)를 연결.

### 5.5 Route Table 생성/연결

```bash
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rtb-public-edge}]' \
  --query 'RouteTable.RouteTableId' --output text)

echo ${RTB_ID}

aws ec2 create-route \
  --route-table-id ${RTB_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${IGW_ID} \
  --region ${AWS_REGION}

aws ec2 associate-route-table --route-table-id ${RTB_ID} --subnet-id ${SUBNET_A_ID} --region ${AWS_REGION}
aws ec2 associate-route-table --route-table-id ${RTB_ID} --subnet-id ${SUBNET_C_ID} --region ${AWS_REGION}
```

의미:

- Public Route Table 생성
- 기본 라우트(0.0.0.0/0)를 IGW로 설정
- 두 Public Subnet에 연결.

---

## 6. 키페어/접속 준비 (AWS CLI)

키페어 생성(신규):

```bash
aws ec2 create-key-pair \
  --key-name kp-haproxy-edge \
  --query 'KeyMaterial' \
  --output text > kp-haproxy-edge.pem

chmod 400 kp-haproxy-edge.pem
```

의미:

- 신규 키페어 생성 + PEM 파일로 저장
- 파일 권한 제한으로 SSH 오류 방지.

---

## 7. CIDR 중복 점검

AWS/온프레 CIDR이 겹치면 라우팅 충돌이 발생하므로 사전 확인.

```bash
python - <<'PY'
import ipaddress
aws = ipaddress.ip_network('10.20.0.0/16')
onprem = ipaddress.ip_network('172.16.0.0/12')
print('overlap=', aws.overlaps(onprem))
PY
```

의미:

- `overlap=False`여야 정상.

---

## 8. Route 53 준비 (AWS CLI)

Hosted Zone 생성:

```bash
aws route53 create-hosted-zone \
  --name sjkim686.store \
  --caller-reference "sjkim686-store-$(date +%s)"
```

Hosted Zone ID/NS 조회:

```bash
HZ_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name sjkim686.store \
  --query "HostedZones[0].Id" --output text)

echo ${HZ_ID}

aws route53 list-resource-record-sets \
  --hosted-zone-id ${HZ_ID} \
  --query "ResourceRecordSets[?Type=='NS' && Name=='sjkim686.store.'].ResourceRecords[].Value" \
  --output text
```

의미:

- 가비아에 입력할 Route 53 NS 4개 값을 조회.

> 가비아 NS 변경은 AWS CLI로 불가(가비아 콘솔에서 수행).

---

## 9. 시작 전 최종 체크

- [ ] Region/VPC/Subnet/CIDR 확정
- [ ] 관리자 공인 IP(/32) 확정
- [ ] 온프레 공인 IP 유무 확인 (경로 A/B 결정)
- [ ] pfSense FRR/BGP 가능 여부 확인
- [ ] 도메인/레코드(`ticket.kosa.team2` 또는 운영 목표 FQDN) 확정
- [ ] AWS Route Table에 `onprem_cidr -> VGW` 경로 존재 확인(경로 A)

## 10. VPN 설정 위치 안내 (경로 A/B)

질문이 많은 항목이라 경로별 위치를 명확히 분리함.

### 10.1 경로 A (온프레 공인 IP 있음): Site-to-Site VPN

- 문서 위치
  - CLI: `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md` →
    `## 4. 경로 A: 온프레 공인 IP 있음 (Site-to-Site VPN)`
  - 콘솔: `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md` →
    `## 4. 경로 A: 온프레 공인 IP 있음 (Site-to-Site VPN)`
- 핵심 리소스
  - VGW, CGW, VPN Connection(ipsec.1), VPC 라우트(VGW 대상)
- 시점
  - init/plan 전: `customer_gateway_public_ip`, `customer_gateway_bgp_asn`, `onprem_cidr` 값 확정
  - apply 후: AWS에서 생성된 VPN 정보를 기준으로 pfSense/IPsec 터널 실제 반영 및 터널 UP 검증
- 참고
  - pfSense 장비 자체는 공인 IP를 "대체"하지 않음
  - 경로 A는 `customer_gateway_public_ip`에 인터넷에서 도달 가능한 공인 IP가 필요함

### 10.2 경로 B (온프레 공인 IP 없음): WireGuard Relay (대안)

- 문서 위치
  - CLI: `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md` →
    `## 5. 경로 B: 온프레 공인 IP 없음 (WireGuard Relay)`
  - 콘솔: `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md` →
    `## 5. 경로 B: 온프레 공인 IP 없음 (WireGuard Relay)`
- 자동화 경로
  - Terraform 변수: `aws-nlb-ec2-vpn-onprem-automation-draft/terraform/terraform.tfvars.example`
    - `create_wireguard_relay = true`
    - `relay_allowed_udp_cidr` 등 WireGuard 관련 값
  - Ansible 플레이북:
    `aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/wireguard_relay.yml`
- 시점
  - init/plan 전: `create_wireguard_relay`, `relay_allowed_udp_cidr`, `onprem_cidr` 확정
  - apply 후: Relay EC2(EIP/키) 생성 이후 WireGuard 피어 설정 및 `wg show` handshake 검증

> 현재 팀2는 "온프레 인터넷 출구 공인 IP(125.131.208.229)"를 CGW endpoint로 사용해 경로
> A(Site-to-Site VPN) 운용 가능함. 경로 B는 공인 endpoint를 확보할 수 없을 때 대안으로 사용.
