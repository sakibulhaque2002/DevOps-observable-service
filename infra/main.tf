locals {
  name = "devops-task-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "default" {
  default = true
}
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/devops-task/${var.environment}/app"
  retention_in_days = var.log_retention_days
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-"
  description = "Application HTTP only; administration uses outbound SSM"
  vpc_id      = data.aws_vpc.default.id
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "Assessment app from the configured client CIDR"
  cidr_ipv4         = var.allowed_http_cidr
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to SSM, CloudWatch, registries and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_iam_role" "instance" {
  name = "${local.name}-instance"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "instance" {
  name = "ssm-and-app-logs"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      }
    ]
  })
}
resource "aws_iam_instance_profile" "app" {
  name = local.name
  role = aws_iam_role.instance.name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.app.name
  credit_specification {
    cpu_credits = "standard"
  }
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region        = var.aws_region
    log_group     = aws_cloudwatch_log_group.app.name
    environment   = var.environment
    image         = var.app_image
    deploy_script = filebase64("${path.module}/../scripts/deploy-container.sh")
  })
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  tags       = { Name = local.name }
  depends_on = [aws_iam_role_policy.instance]
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_deploy" {
  name = "${local.name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/main"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "deploy-one-instance-via-ssm"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Action = "ssm:SendCommand"
        Resource = [
          aws_instance.app.arn,
          "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-RunShellScript"
        ]
      },
      { Effect = "Allow", Action = "ssm:GetCommandInvocation", Resource = "*" }
    ]
  })
}
