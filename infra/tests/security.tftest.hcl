# These are offline mocked plans, not evidence of an actual AWS apply.
mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-0123456789abcdef0"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

run "staging_security_defaults" {
  command = plan
  variables {
    environment       = "staging"
    app_image         = "ghcr.io/example/app:sha-0123456789012345678901234567890123456789"
    allowed_http_cidr = "203.0.113.1/32"
  }
  assert {
    condition     = aws_instance.app.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition     = aws_instance.app.root_block_device[0].encrypted
    error_message = "The root disk must be encrypted."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.http.from_port == 8080 && aws_vpc_security_group_ingress_rule.http.cidr_ipv4 == "203.0.113.1/32"
    error_message = "HTTP must be limited to the supplied CIDR and app port."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 7
    error_message = "Logs must have explicit retention."
  }
}
