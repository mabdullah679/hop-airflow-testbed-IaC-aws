# Bootstrap: Terraform state bucket + GitHub OIDC deploy role. Applied LOCALLY once (state kept
# locally in this directory, git-ignored) because CI cannot create its own role or state bucket.
terraform {
  required_version = ">= 1.10"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}

variable "name_prefix" { default = "pf-hop-airflow" }
variable "github_repo" { default = "mabdullah679/hop-airflow-testbed-IaC-aws" }
variable "github_branch" { default = "prod-hardening" }

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      project      = "portfolio"
      repo         = "hop-airflow-testbed-IaC-aws"
      "managed-by" = "terraform"
    }
  }
}

data "aws_caller_identity" "me" {}
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
locals {
  account  = data.aws_caller_identity.me.account_id
  boundary = "arn:aws:iam::${local.account}:policy/portfolio-ci-boundary"
}

resource "aws_s3_bucket" "state" {
  bucket        = "${var.name_prefix}-tfstate-${local.account}"
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name_prefix}-gha-deploy"
  permissions_boundary = local.boundary
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Ec2Vpc", Effect = "Allow", Action = ["ec2:*"], Resource = "*" },
      { Sid = "SsmRunAndRead", Effect = "Allow", Action = ["ssm:*"], Resource = "*" },
      { Sid = "S3Own", Effect = "Allow", Action = "s3:*", Resource = [
      "arn:aws:s3:::${var.name_prefix}-*", "arn:aws:s3:::${var.name_prefix}-*/*"] },
      { Sid = "S3List", Effect = "Allow", Action = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"], Resource = "*" },
      { Sid = "IamOwnRoles", Effect = "Allow", Action = "iam:*", Resource = [
        "arn:aws:iam::${local.account}:role/${var.name_prefix}-*",
      "arn:aws:iam::${local.account}:instance-profile/${var.name_prefix}-*"] },
      { Sid = "IamReadShared", Effect = "Allow", Action = ["iam:GetOpenIDConnectProvider", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListOpenIDConnectProviders"], Resource = "*" },
      { Sid = "Ident", Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" },
    ]
  })
}

output "state_bucket" { value = aws_s3_bucket.state.id }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
