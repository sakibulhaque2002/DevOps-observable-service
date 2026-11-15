output "instance_id" {
  value = aws_instance.app.id
}
output "application_url" {
  value = "http://${aws_instance.app.public_ip}:8080"
}
output "github_deploy_role_arn" {
  value = try(aws_iam_role.github_deploy[0].arn, null)
}

output "deployment_method" {
  value = var.deployment_method
}

output "ssh_host" {
  value = var.deployment_method == "ssh" ? aws_instance.app.public_ip : null
}
output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}
