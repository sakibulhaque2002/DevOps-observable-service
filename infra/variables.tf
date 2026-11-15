variable "aws_region" {
  description = "Region for all assessment resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Separate staging and production using separate backend state keys."
  type        = string
  default     = "staging"
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Use staging or production."
  }
}

variable "app_image" {
  description = "Public GHCR image with a SHA tag or digest; publish it before apply."
  type        = string
  validation {
    condition     = can(regex("^ghcr\\.io/[a-z0-9._/-]+(:sha-[a-f0-9]{40}|@sha256:[a-f0-9]{64})$", var.app_image))
    error_message = "Use a full sha-<40-character-git-SHA> tag or sha256 digest from public GHCR."
  }
}

variable "instance_type" {
  type        = string
  description = "Small x86_64 instance; verify your plan's allowed types before applying."
  default     = "t3.micro"
}

variable "allowed_http_cidr" {
  description = "Reviewer/client IPv4 CIDR allowed to reach port 8080. Prefer your public IP/32."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.allowed_http_cidr))
    error_message = "Provide a valid IPv4 CIDR."
  }
}

variable "github_repository" {
  description = "Case-sensitive owner/repository in the GitHub OIDC subject."
  type        = string
  default     = "sakibulhaque2002/DevOps-observable-service"
}

variable "create_github_oidc_provider" {
  description = "Set false if this AWS account already has the GitHub OIDC provider."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch application log retention."
  default     = 7
}

variable "deployment_method" {
  description = "ssm uses GitHub OIDC; ssh supports accounts whose policies block IAM identity providers."
  type        = string
  default     = "ssm"
  validation {
    condition     = contains(["ssm", "ssh"], var.deployment_method)
    error_message = "Use ssm or ssh."
  }
}

variable "ssh_public_key" {
  description = "Dedicated deployment public key; its private key is stored only as a GitHub Actions secret."
  type        = string
  default     = ""
  validation {
    condition     = var.deployment_method != "ssh" || can(regex("^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._-]+)?$", var.ssh_public_key))
    error_message = "SSH mode requires a single Ed25519 public key with an optional simple comment."
  }
}

variable "ssh_allowed_cidr" {
  description = "SSH source range. Dynamic GitHub-hosted runners require broad ingress; the key is forced-command-only."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "Provide a valid IPv4 CIDR."
  }
}
