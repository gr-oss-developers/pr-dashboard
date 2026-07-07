terraform {
  required_version = ">= 1.5"

  # State + remote runs in HCP Terraform. Org and workspace are supplied at init time
  # via TF_CLOUD_ORGANIZATION and TF_WORKSPACE (same convention as github-terraformer).
  cloud {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Tag every taggable resource, so ownership is clear in the console/billing.
  default_tags {
    tags = {
      Author  = var.author
      Project = "pr-dashboard"
    }
  }
}

# Latest Amazon Linux 2023 AMI for the region (ships Node 18+ and git in its repos).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Prefer the DNS name when a domain is configured; otherwise fall back to the raw IP.
  app_host     = var.domain_name != "" ? var.domain_name : aws_eip.app.public_ip
  app_url      = "http://${local.app_host}/"
  redirect_uri = "http://${local.app_host}/callback"
}

resource "aws_security_group" "app" {
  name_prefix = "pr-dashboard-"
  description = "PR Dashboard — HTTP/HTTPS from anywhere, SSH from admin"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS (reserved for future TLS)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "pr-dashboard" }
}

# A stable public address so the DNS record / OAuth callback survive instance stop/start.
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "pr-dashboard" }
}

# DNS: point <domain_name> at the Elastic IP. Enabled when domain_name is set and the
# hosted zone (route53_zone_name) already exists in this account's Route 53.
data "aws_route53_zone" "app" {
  count        = var.domain_name != "" ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "app" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.app[0].zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url      = var.repo_url
    repo_branch   = var.repo_branch
    client_id     = var.github_client_id
    client_secret = var.github_client_secret
    scopes        = var.oauth_scopes
    redirect_uri  = local.redirect_uri
  })
  # Rebuild (reprovision) when the bootstrap script or its inputs change.
  user_data_replace_on_change = true

  tags = { Name = "pr-dashboard" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
