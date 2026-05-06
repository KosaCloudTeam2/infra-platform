output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.app.dns_name
}

output "app_autoscaling_group_name" {
  description = "AWS burst app Auto Scaling Group name"
  value       = aws_autoscaling_group.app.name
}

output "app_launch_template_id" {
  description = "AWS burst app Launch Template ID"
  value       = aws_launch_template.app.id
}

output "app_security_group_id" {
  description = "AWS burst app security group ID"
  value       = aws_security_group.app.id
}

output "target_group_arn" {
  description = "ALB target group ARN"
  value       = aws_lb_target_group.app.arn
}

output "proxysql_private_ips" {
  description = "Private IP addresses of ProxySQL instances"
  value       = aws_instance.proxysql[*].private_ip
}

output "proxysql_internal_nlb_dns_name" {
  description = "Internal NLB DNS name for ProxySQL when enabled"
  value       = try(aws_lb.proxysql_internal[0].dns_name, null)
}

output "pxc_private_ips" {
  description = "Private IP addresses of PXC nodes"
  value       = aws_instance.pxc[*].private_ip
}
