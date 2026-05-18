output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

output "haproxy_instance_ids" {
  value = [aws_instance.haproxy_a.id, aws_instance.haproxy_c.id]
}

output "haproxy_public_ips" {
  value = [aws_instance.haproxy_a.public_ip, aws_instance.haproxy_c.public_ip]
}

output "haproxy_private_ips" {
  value = [aws_instance.haproxy_a.private_ip, aws_instance.haproxy_c.private_ip]
}

output "selected_al2023_ami_id" {
  value = data.aws_ami.al2023.id
}

output "nlb_dns_name" {
  value = aws_lb.nlb.dns_name
}

output "nlb_zone_id" {
  value = aws_lb.nlb.zone_id
}

output "relay_eip" {
  value = var.create_wireguard_relay ? aws_eip.relay[0].public_ip : null
}

output "vpn_connection_id" {
  value = var.create_site_to_site_vpn ? aws_vpn_connection.this[0].id : null
}

output "route53_name_servers" {
  value = var.create_route53_zone ? aws_route53_zone.this[0].name_servers : []
}
