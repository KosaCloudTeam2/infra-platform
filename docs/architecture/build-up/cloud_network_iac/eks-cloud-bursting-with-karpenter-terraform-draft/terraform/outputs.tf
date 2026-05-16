output "lambda_function_name" {
  value = aws_lambda_function.scale_nodegroup.function_name
}

output "schedule_names" {
  value = [
    aws_scheduler_schedule.scale_out.name,
    aws_scheduler_schedule.scale_in.name,
  ]
}
