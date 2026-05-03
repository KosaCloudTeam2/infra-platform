variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, formatted as owner/repo"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "app_private_subnet_cidrs" {
  description = "Private application subnet CIDRs"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "data_private_subnet_cidrs" {
  description = "Private data subnet CIDRs for ProxySQL and PXC nodes"
  type        = list(string)
  default     = ["10.20.21.0/24", "10.20.22.0/24", "10.20.23.0/24"]
}

variable "container_port" {
  description = "Application container port"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB health check path"
  type        = string
  default     = "/health"
}

variable "task_cpu" {
  description = "Fargate task CPU"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "ECS desired task count"
  type        = number
  default     = 2
}

variable "ecs_cpu_alarm_threshold" {
  description = "ECS average CPU utilization alarm threshold"
  type        = number
  default     = 80
}

variable "ecs_memory_alarm_threshold" {
  description = "ECS average memory utilization alarm threshold"
  type        = number
  default     = 80
}

variable "image_tag" {
  description = "Initial image tag"
  type        = string
  default     = "latest"
}

variable "app_environment" {
  description = "Plain environment variables for the ECS app container"
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "ECS container secret mappings. Key is environment variable name, value is Secrets Manager ARN."
  type        = map(string)
  default     = {}
}

variable "db_instance_type" {
  description = "EC2 instance type for PXC nodes"
  type        = string
  default     = "t3.small"
}

variable "proxysql_instance_type" {
  description = "EC2 instance type for ProxySQL"
  type        = string
  default     = "t3.micro"
}

variable "proxysql_count" {
  description = "Number of ProxySQL instances. Use 2 with enable_proxysql_internal_nlb for HA."
  type        = number
  default     = 1
}

variable "enable_proxysql_internal_nlb" {
  description = "Create an internal NLB in front of ProxySQL instances"
  type        = bool
  default     = false
}

variable "db_node_count" {
  description = "Number of Percona XtraDB Cluster nodes"
  type        = number
  default     = 3
}

variable "db_volume_size" {
  description = "Root EBS volume size for DB nodes"
  type        = number
  default     = 40
}
