# AWS 리소스 정리(Release/Remove) 체크리스트

> Status: Unverified

`docs/architecture/build-up/cloud_network_iac/` 경로 문서에서 사용한 AWS 자원을 **누락 없이
정리**하기 위한 절차임.

---

## 1. 적용 범위

대상 문서:

- `eks-cloud-bursting-without-karpenter.md`
- `eks-cloud-bursting-with-karpenter.md`
- `aws-nlb-ec2-vpn-onprem-prerequisites.md`
- `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`
- `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md`

대상 자원(요약):

- 네트워크: VPC, Subnet, IGW, Route Table, Security Group
- 로드밸런싱: NLB, Target Group, Listener
- 컴퓨트: EC2(HAProxy), EC2(WireGuard Relay), EIP
- VPN: VGW, CGW, Site-to-Site VPN Connection
- DNS: Route 53 Hosted Zone/Record
- EKS: Cluster, NodeGroup, OIDC, Karpenter(NodePool/EC2NodeClass/helm), Lambda, EventBridge
  Scheduler, IAM Role/Policy

---

## 2. 정리 방식 선택 (중요)

### 2.1 Terraform으로 만든 경우 (권장)

- 원칙: **Terraform state 기준으로 `terraform destroy`** 수행
- 경로:
  `docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform/`

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform
terraform init
terraform plan -destroy
terraform destroy
```

권장 보완:

- `terraform state list`로 실제 관리 리소스 확인
- 수동 생성 리소스가 섞였으면 `terraform import` 후 destroy 또는 수동 삭제 병행
- Route53 레코드/Hosted Zone, EKS(eksctl 생성), Lambda/Scheduler가 Terraform 바깥이면 아래 3장 수동
  절차 수행

### 2.2 Terraform이 아닌 CLI/콘솔/eksctl 중심으로 만든 경우

- 원칙: **의존성 역순 수동 삭제**
- 아래 3장 절차를 순서대로 수행

---

## 3. 수동 삭제 절차 (CLI/콘솔/eksctl 구성용)

## 3.1 공통 환경변수

```bash
export AWS_REGION=ap-northeast-2
export CLUSTER_NAME=ticket-burst-eks
export NODEGROUP_NAME=base-ng
export NLB_NAME=nlb-haproxy-edge
export DOMAIN_NAME=sjkim686.store
export APP_FQDN=api.sjkim686.store
export VPC_ID=vpc-xxxxxxxx
```

## 3.2 DNS/트래픽 정리

### 3.2.1 Route 53 레코드 삭제

```bash
HZ_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name ${DOMAIN_NAME} \
  --query "HostedZones[0].Id" --output text)

cat > r53-delete-api.json <<EOF
{
  "Comment": "delete api alias",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "${APP_FQDN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "REPLACE_NLB_ZONE_ID",
          "DNSName": "REPLACE_NLB_DNS",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id ${HZ_ID} \
  --change-batch file://r53-delete-api.json
```

> Alias DELETE는 기존 레코드 값과 동일해야 함.

### 3.2.2 Hosted Zone 삭제(완전 삭제 기준)

```bash
aws route53 delete-hosted-zone --id ${HZ_ID}
```

> SOA/NS 외 레코드가 없어야 삭제 가능.

## 3.3 EKS 관련 자원 정리

```bash
aws scheduler delete-schedule --name ticket-scale-out-before-event || true
aws scheduler delete-schedule --name ticket-scale-in-after-event || true

aws lambda delete-function --function-name scale-eks-nodegroup || true

kubectl delete nodepool ticket-burst --ignore-not-found
kubectl delete ec2nodeclass ticket-nodeclass --ignore-not-found
helm uninstall karpenter -n kube-system || true

eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}

aws iam delete-role-policy --role-name LambdaEKSScaleRole --policy-name LambdaEKSScalePolicy || true
aws iam delete-role --role-name LambdaEKSScaleRole || true
```

## 3.4 NLB/EC2/VPN 자원 정리

```bash
NLB_ARN=$(aws elbv2 describe-load-balancers --names ${NLB_NAME} --region ${AWS_REGION} --query 'LoadBalancers[0].LoadBalancerArn' --output text)
TG_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn ${NLB_ARN} --region ${AWS_REGION} --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 delete-load-balancer --load-balancer-arn ${NLB_ARN} --region ${AWS_REGION}
aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --region ${AWS_REGION}

aws ec2 terminate-instances --instance-ids <HAPROXY_EC2_ID_A> <HAPROXY_EC2_ID_C> --region ${AWS_REGION}
```

Relay 경로(B) 사용 시:

```bash
aws ec2 terminate-instances --instance-ids <RELAY_EC2_ID> --region ${AWS_REGION}
aws ec2 release-address --allocation-id <EIP_ALLOC_ID> --region ${AWS_REGION}
```

경로 A(Site-to-Site VPN) 사용 시:

```bash
aws ec2 delete-vpn-connection --vpn-connection-id <VPN_ID> --region ${AWS_REGION}
aws ec2 delete-customer-gateway --customer-gateway-id <CGW_ID> --region ${AWS_REGION}
aws ec2 detach-vpn-gateway --vpn-gateway-id <VGW_ID> --vpc-id ${VPC_ID} --region ${AWS_REGION}
aws ec2 delete-vpn-gateway --vpn-gateway-id <VGW_ID> --region ${AWS_REGION}
```

## 3.5 VPC 자원 정리

```bash
# 비메인 Route Table association 정리 후 Route Table 삭제
aws ec2 describe-route-tables --filters Name=vpc-id,Values=${VPC_ID} --region ${AWS_REGION}

aws ec2 detach-internet-gateway --internet-gateway-id <IGW_ID> --vpc-id ${VPC_ID} --region ${AWS_REGION}
aws ec2 delete-internet-gateway --internet-gateway-id <IGW_ID> --region ${AWS_REGION}

aws ec2 delete-subnet --subnet-id <SUBNET_A_ID> --region ${AWS_REGION}
aws ec2 delete-subnet --subnet-id <SUBNET_C_ID> --region ${AWS_REGION}

aws ec2 delete-security-group --group-id <SG_HAPROXY_ID> --region ${AWS_REGION}
aws ec2 delete-security-group --group-id <SG_NLB_ID> --region ${AWS_REGION}

aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${AWS_REGION}
```

---

## 4. 삭제 후 잔존 자원 점검 (공통)

## 4.1 네트워크/컴퓨트 잔존

```bash
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} --region ${AWS_REGION}
aws ec2 describe-addresses --region ${AWS_REGION}
aws elbv2 describe-load-balancers --region ${AWS_REGION}
aws ec2 describe-vpn-connections --region ${AWS_REGION}
```

## 4.2 EKS/Lambda/Scheduler 잔존

```bash
aws eks list-clusters --region ${AWS_REGION}
aws lambda list-functions --region ${AWS_REGION}
aws scheduler list-schedules --region ${AWS_REGION}
```

## 4.3 비용 확인

- Billing > Bills / Cost Explorer에서 다음날까지 잔여 과금 확인
- 특히 EIP, NAT GW, NLB, ENI, EBS Snapshot 잔존 여부 재확인

---

## 5. 실패가 잦은 포인트

- Terraform 관리 리소스를 콘솔에서 먼저 지워 state 불일치 발생
- Terraform 외부(수동) 리소스를 destroy만 믿고 누락
- Route53 Hosted Zone 삭제 전 레코드 미정리
- Subnet 삭제 전 ENI 잔존
- VPN 삭제 후 VGW/CGW 미삭제로 잔존 과금
