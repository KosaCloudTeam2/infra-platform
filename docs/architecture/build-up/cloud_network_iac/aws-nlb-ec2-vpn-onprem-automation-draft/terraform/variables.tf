variable "aws_region" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "hybrid-edge"
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_a_cidr" {
  type = string
}

variable "public_subnet_c_cidr" {
  type = string
}

variable "az_a" {
  type = string
}

variable "az_c" {
  type = string
}

variable "admin_cidr" {
  type        = string
  description = "SSH 허용 관리 IP/CIDR (예: x.x.x.x/32)"
}

variable "haproxy_ami_id" {
  type        = string
  description = "AL2023 AMI ID를 리전별로 직접 지정"
}

variable "haproxy_instance_type" {
  type    = string
  default = "t3.small"
}

variable "key_name" {
  type = string
}

variable "onprem_edge_backends" {
  type        = list(string)
  description = "On-Prem HAProxyEdge backend 목록 (예: [\"172.16.20.10:443\", \"172.16.20.11:443\"])"
}

variable "create_wireguard_relay" {
  type    = bool
  default = false
}

variable "relay_ami_id" {
  type    = string
  default = ""
}

variable "relay_instance_type" {
  type    = string
  default = "t3.small"
}

variable "relay_allowed_udp_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "create_site_to_site_vpn" {
  type    = bool
  default = false
}

variable "customer_gateway_public_ip" {
  type    = string
  default = ""
}

variable "customer_gateway_bgp_asn" {
  type    = number
  default = 65000
}

variable "onprem_cidr" {
  type    = string
  default = ""
}

variable "vpn_static_routes_only" {
  type    = bool
  default = false
}

variable "create_route53_zone" {
  type    = bool
  default = false
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "create_route53_alias_record" {
  type    = bool
  default = false
}

variable "app_fqdn" {
  type    = string
  default = ""
}
