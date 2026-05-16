variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "cluster_name" {
  type = string
}

variable "nodegroup_name" {
  type = string
}

variable "scale_lambda_zip_path" {
  type = string
}

variable "scale_out_schedule" {
  type        = string
  description = "EventBridge Scheduler cron/rate"
}

variable "scale_in_schedule" {
  type        = string
  description = "EventBridge Scheduler cron/rate"
}
