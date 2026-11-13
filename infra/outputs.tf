output "instance_id" {
  value = aws_instance.app.id
}
output "application_url" {
  value = "http://${aws_instance.app.public_ip}:8080"
}
output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}
