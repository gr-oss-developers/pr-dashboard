output "app_url" {
  description = "Where the dashboard is served."
  value       = local.app_url
}

output "oauth_callback_url" {
  description = "Set this as the OAuth App's Authorization callback URL."
  value       = "${local.app_url}callback"
}

output "public_ip" {
  description = "Elastic IP of the instance."
  value       = aws_eip.app.public_ip
}

output "dns_record_to_create" {
  description = "Add this A record at the DNS provider (Namecheap) so the hostname resolves."
  value       = var.domain_name != "" ? "A  ${var.domain_name}  ->  ${aws_eip.app.public_ip}" : "n/a (using raw IP)"
}

output "ssh" {
  description = "SSH command (if a key_name was provided)."
  value       = var.key_name != "" ? "ssh ec2-user@${aws_eip.app.public_ip}" : "no key_name set"
}
