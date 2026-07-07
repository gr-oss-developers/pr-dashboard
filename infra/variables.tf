variable "region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "eu-west-1"
}

variable "author" {
  type        = string
  description = "Value for the Author tag applied to all resources."
  default     = "Ivan Pavlovic"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (t2.micro/t3.micro are free-tier eligible)."
  default     = "t3.micro"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH access (optional; leave empty for none)."
  default     = ""
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH in. Tighten to YOUR_IP/32."
  default     = "0.0.0.0/0"
}

# --- DNS -------------------------------------------------------------------
# Serves the dashboard on a hostname in the gr-oss.io hosted zone (must already exist in
# this account's Route 53). Set domain_name to the apex ("gr-oss.io") to serve there, or
# clear both to fall back to the raw Elastic IP.
variable "domain_name" {
  type        = string
  description = "FQDN to serve the dashboard on."
  default     = "pr-dashboard.gr-oss.io"
}

variable "route53_zone_name" {
  type        = string
  description = "Existing Route 53 hosted zone that domain_name belongs to."
  default     = "gr-oss.io"
}

# --- App source ------------------------------------------------------------
variable "repo_url" {
  type        = string
  description = "Public git URL the instance clones the app from."
  default     = "https://github.com/gr-oss-developers/pr-dashboard.git"
}

variable "repo_branch" {
  type        = string
  description = "Branch to deploy."
  default     = "main"
}

# --- GitHub OAuth App ------------------------------------------------------
# Register an OAuth App at https://github.com/settings/developers with the callback
# URL shown in the `oauth_callback_url` output, then supply these (via terraform.tfvars,
# which is gitignored — never commit the secret).
variable "github_client_id" {
  type        = string
  description = "GitHub OAuth App client ID."
  sensitive   = true
}

variable "github_client_secret" {
  type        = string
  description = "GitHub OAuth App client secret."
  sensitive   = true
}

variable "oauth_scopes" {
  type        = string
  description = "OAuth scopes requested at sign-in."
  default     = "read:user repo read:org"
}
