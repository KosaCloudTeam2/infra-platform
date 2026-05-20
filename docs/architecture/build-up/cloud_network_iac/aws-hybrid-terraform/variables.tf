variable "aws_region" {
  type        = string
  description = "AWS 리전"
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  type        = string
  description = "생성 리소스 이름 접두사"
  default     = "kosa-hybrid"
}

variable "vpc_cidr" {
  type        = string
  description = "AWS VPC CIDR"
  default     = "10.20.0.0/16"
}

variable "public_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  description = "Public Subnet 정의"
  default = {
    a = {
      cidr = "10.20.1.0/24"
      az   = "ap-northeast-2a"
    }
    c = {
      cidr = "10.20.2.0/24"
      az   = "ap-northeast-2c"
    }
  }
}

variable "private_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
  description = "Private Subnet 정의"
  default = {
    a = {
      cidr = "10.20.10.0/24"
      az   = "ap-northeast-2a"
    }
    c = {
      cidr = "10.20.20.0/24"
      az   = "ap-northeast-2c"
    }
  }
}

variable "onprem_cidrs" {
  type        = list(string)
  description = "AWS에서 온프레미스로 라우팅할 CIDR 목록"
  default     = ["172.16.0.0/12"]
}

variable "customer_gateway_public_ip" {
  type        = string
  description = "온프레 인터넷 출구 공인 IP 또는 상위 NAT 공인 IP. pfSense WAN 사설 IP가 아님"
}

variable "customer_gateway_bgp_asn" {
  type        = number
  description = "Customer Gateway BGP ASN. Static VPN에서도 AWS 리소스 생성 시 필요"
  default     = 65000
}

variable "create_vpn" {
  type        = bool
  description = "VGW/CGW/Site-to-Site VPN 생성 여부"
  default     = true
}

variable "create_route53_zone" {
  type        = bool
  description = "Route53 Public Hosted Zone 생성 여부"
  default     = true
}

variable "create_route53_alias_record" {
  type        = bool
  description = "NLB를 가리키는 Route53 Alias A 레코드 생성 여부"
  default     = true
}

variable "domain_name" {
  type        = string
  description = "가비아에서 구매한 실제 도메인. 예: example.com. 고정 프로젝트 도메인을 기본값으로 두지 않음"
  default     = ""
}

variable "app_fqdn" {
  type        = string
  description = "NLB Alias 레코드 FQDN. 비우면 domain_name apex에 생성"
  default     = ""
}

variable "nlb_ingress_cidrs" {
  type        = list(string)
  description = "Public NLB 80/443 접근 허용 CIDR"
  default     = ["0.0.0.0/0"]
}

variable "ec2_ami_id" {
  type        = string
  description = "HAProxy EC2 AMI ID. 비우면 최신 Ubuntu 22.04 LTS amd64 AMI 자동 조회"
  default     = ""
}

variable "ec2_instance_type" {
  type        = string
  description = "HAProxy EC2 인스턴스 타입"
  default     = "t3.micro"
}

variable "ec2_key_name" {
  type        = string
  description = "선택: EC2 Key Pair 이름. SSM 기준이면 비워둠"
  default     = ""
}

variable "create_s3_gateway_endpoint" {
  type        = bool
  description = "Private Subnet에서 S3 접근용 Gateway Endpoint 생성 여부"
  default     = true
}
