data "aws_caller_identity" "me" {}
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
data "aws_availability_zones" "az" { state = "available" }

locals {
  account  = data.aws_caller_identity.me.account_id
  boundary = "arn:aws:iam::${local.account}:policy/portfolio-ci-boundary"
  bucket   = "${var.name_prefix}-data-${local.account}"
  app_files = {
    for f in setunion(toset(["Dockerfile", "docker-compose.yml", "deploy.sh"]), fileset("${path.module}/../app", "*.py"), fileset("${path.module}/../app", "dags/*.py"), fileset("${path.module}/../app", "hop/**")) :
    f => "${path.module}/../app/${f}"
  }
}

# ---------------- network (own VPC, public subnet, no NAT) ----------------
resource "aws_vpc" "this" {
  cidr_block           = "10.42.0.0/24"
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.42.0.0/26"
  availability_zone       = data.aws_availability_zones.az.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name_prefix}-public-rt" }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "airflow" {
  name        = "${var.name_prefix}-airflow"
  description = "Airflow UI only from owner CIDR; no SSH (use SSM)"
  vpc_id      = aws_vpc.this.id
  ingress {
    description = "Airflow UI from owner IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name_prefix}-airflow" }
}

# ---------------- S3: pipeline data + app bundle ----------------
resource "aws_s3_bucket" "data" {
  bucket        = local.bucket
  force_destroy = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "sample_input" {
  bucket = aws_s3_bucket.data.id
  key    = "input/orders.csv"
  source = "${path.module}/../app/data/orders.csv"
  etag   = filemd5("${path.module}/../app/data/orders.csv")
}
resource "aws_s3_object" "app" {
  for_each = local.app_files
  bucket   = aws_s3_bucket.data.id
  key      = "app/${each.key}"
  source   = each.value
  etag     = filemd5(each.value)
}

# ---------------- IAM for the instance ----------------
resource "aws_iam_role" "ec2" {
  name                 = "${var.name_prefix}-ec2"
  permissions_boundary = local.boundary
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "ec2" {
  name = "pipeline"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"], Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"] },
      { Effect = "Allow", Action = ["ssm:GetParameter", "ssm:PutParameter", "ssm:AddTagsToResource"], Resource = "arn:aws:ssm:ap-southeast-2:${local.account}:parameter/${var.name_prefix}/*" },
    ]
  })
}
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2"
  role = aws_iam_role.ec2.name
}

# ---------------- the Airflow host ----------------
resource "aws_instance" "airflow" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.airflow.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # containers need IMDS for the instance-role credentials
  }
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    bucket = aws_s3_bucket.data.id
    prefix = var.name_prefix
  })
  depends_on = [aws_s3_object.app, aws_s3_object.sample_input, aws_route_table_association.public]
  tags       = { Name = "${var.name_prefix}-airflow" }
}
resource "aws_eip" "airflow" {
  instance = aws_instance.airflow.id
  domain   = "vpc"
  tags     = { Name = "${var.name_prefix}-airflow" }
}

output "airflow_url" { value = "http://${aws_eip.airflow.public_ip}:8080" }
output "instance_id" { value = aws_instance.airflow.id }
output "data_bucket" { value = aws_s3_bucket.data.id }
output "admin_password_param" { value = "/${var.name_prefix}/airflow-admin-password" }
