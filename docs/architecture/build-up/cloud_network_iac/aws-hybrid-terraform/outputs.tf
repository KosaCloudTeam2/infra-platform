output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public Subnet ID 목록"
  value       = { for k, v in aws_subnet.public : k => v.id }
}

output "private_subnet_ids" {
  description = "Private Subnet ID 목록"
  value       = { for k, v in aws_subnet.private : k => v.id }
}

output "private_route_table_ids" {
  description = "Private Route Table ID 목록"
  value       = { for k, v in aws_route_table.private : k => v.id }
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID 목록"
  value       = { for k, v in aws_nat_gateway.this : k => v.id }
}

output "haproxy_instance_ids" {
  description = "Private HAProxy EC2 Instance ID 목록"
  value       = { for k, v in aws_instance.haproxy : k => v.id }
}

output "haproxy_private_ips" {
  description = "Private HAProxy EC2 Private IP 목록"
  value       = { for k, v in aws_instance.haproxy : k => v.private_ip }
}

output "selected_ubuntu_ami_id" {
  description = "자동 선택된 Ubuntu 22.04 AMI ID"
  value       = data.aws_ami.ubuntu_2204.id
}

output "nlb_dns_name" {
  description = "NLB DNS 이름"
  value       = aws_lb.nlb.dns_name
}

output "nlb_zone_id" {
  description = "NLB Route53 Hosted Zone ID"
  value       = aws_lb.nlb.zone_id
}

output "route53_name_servers" {
  description = "가비아 NS 위임에 입력할 Route53 네임서버 목록"
  value       = var.create_route53_zone ? aws_route53_zone.this[0].name_servers : []
}

output "app_fqdn" {
  description = "생성된 Alias 레코드 FQDN"
  value       = var.create_route53_zone && var.create_route53_alias_record ? local.app_fqdn : null
}

output "vpn_gateway_id" {
  description = "VGW ID"
  value       = var.create_vpn ? aws_vpn_gateway.this[0].id : null
}

output "customer_gateway_id" {
  description = "CGW ID"
  value       = var.create_vpn ? aws_customer_gateway.this[0].id : null
}

output "vpn_connection_id" {
  description = "Site-to-Site VPN Connection ID"
  value       = var.create_vpn ? aws_vpn_connection.this[0].id : null
}

output "vpn_tunnel_outside_ips" {
  description = "pfSense Remote Gateway에 입력할 AWS 터널 Outside IP"
  value = var.create_vpn ? [
    aws_vpn_connection.this[0].tunnel1_address,
    aws_vpn_connection.this[0].tunnel2_address
  ] : []
}

output "vpn_customer_gateway_configuration" {
  description = "pfSense 설정 참고용 AWS VPN XML 구성. PSK 포함 가능성이 있으므로 파일 저장/공유 주의"
  value       = var.create_vpn ? aws_vpn_connection.this[0].customer_gateway_configuration : null
  sensitive   = true
}
