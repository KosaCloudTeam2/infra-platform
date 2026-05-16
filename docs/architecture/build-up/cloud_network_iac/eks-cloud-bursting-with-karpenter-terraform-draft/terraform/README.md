# Terraform 초안 (EKS Cloud Bursting with Karpenter)

> Status: Unverified

시작:

```bash
cd docs/architecture/build-up/cloud_network_iac/eks-cloud-bursting-with-karpenter-terraform-draft/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

주의:

- 현재는 Scheduler+Lambda 중심 골격만 포함
- Karpenter IRSA/Helm/NodePool 자동화는 TODO
