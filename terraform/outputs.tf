output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.forgevm.id
}

output "public_ip" {
  description = "Public IP of the ForgeVM host (Elastic IP if use_elastic_ip, else the auto-assigned public IP)."
  value       = local.host_ip
}

output "region" {
  description = "AWS region the instance runs in."
  value       = var.region
}

output "allowed_cidr" {
  description = "CIDR granted access to SSH and the ForgeVM API."
  value       = local.detected_cidr
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI used."
  value       = nonsensitive(data.aws_ssm_parameter.al2023.value)
}

output "ssh_command" {
  description = "SSH into the instance."
  value = var.generate_ssh_key ? (
    "ssh -i ${var.generated_key_path} ec2-user@${local.host_ip}"
  ) : "ssh ec2-user@${local.host_ip}"
}

output "forgevm_url" {
  description = "Base URL of the ForgeVM API."
  value       = "http://${local.host_ip}:7423"
}

output "test_command" {
  description = "Quick health check once bootstrap has finished (give it a few minutes)."
  value       = "curl http://${local.host_ip}:7423/api/v1/sandboxes"
}

output "bootstrap_log_hint" {
  description = "Where to watch first-boot progress."
  value = var.generate_ssh_key ? (
    "ssh -i ${var.generated_key_path} ec2-user@${local.host_ip} 'sudo tail -f /var/log/forgevm-bootstrap.log'"
  ) : "ssh ec2-user@${local.host_ip} 'sudo tail -f /var/log/forgevm-bootstrap.log'"
}

output "idle_auto_terminate" {
  description = "In-instance idle auto-terminate status."
  value = var.auto_terminate_idle ? (
    "enabled — self-terminates after ~${var.idle_minutes}m idle (no sandboxes, no SSH, low load)"
  ) : "disabled"
}
