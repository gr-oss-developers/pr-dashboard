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
# The app is served on this hostname and it's used for the OAuth callback. DNS is managed
# externally (Namecheap): after apply, create an A record pointing this name at the
# Elastic IP (see the dns_record_to_create output). Clear it to use the raw IP instead.
variable "domain_name" {
  type        = string
  description = "FQDN the dashboard is served on (A record created manually at the DNS provider)."
  default     = "pr-dashboard.gr-oss.io"
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

variable "app_version" {
  type        = string
  description = "Fingerprint of the app files (index.html/server.js). Set by the deploy workflow; a change replaces the instance so it re-clones the latest code."
  default     = ""
}
