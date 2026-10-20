terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket       = "pf-hop-airflow-tfstate-346208529954"
    key          = "hop-airflow/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = ["346208529954"]
  default_tags {
    tags = {
      project      = "portfolio"
      repo         = "hop-airflow-testbed-IaC-aws"
      "managed-by" = "terraform"
    }
  }
}
