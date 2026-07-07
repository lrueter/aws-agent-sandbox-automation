output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.forgevm.id
}

output "public_ip" {
  description = "Stable public IP (Elastic IP) of the ForgeVM host."
  value       = aws_eip.forgevm.public_ip
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
  value       = data.aws_ssm_parameter.al2023.value
}

output "ssh_command" {
  description = "SSH into the instance."
  value       = "ssh ec2-user@${aws_eip.forgevm.public_ip}"
}

output "forgevm_url" {
  description = "Base URL of the ForgeVM API."
  value       = "http://${aws_eip.forgevm.public_ip}:7423"
}

output "test_command" {
  description = "Quick health check once bootstrap has finished (give it a few minutes)."
  value       = "curl http://${aws_eip.forgevm.public_ip}:7423/api/v1/sandboxes"
}

output "bootstrap_log_hint" {
  description = "Where to watch first-boot progress."
  value       = "ssh ec2-user@${aws_eip.forgevm.public_ip} 'sudo tail -f /var/log/forgevm-bootstrap.log'"
}
