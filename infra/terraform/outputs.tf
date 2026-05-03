output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.ecs_task.arn
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
