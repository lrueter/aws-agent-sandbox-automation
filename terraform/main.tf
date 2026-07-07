# ---------------------------------------------------------------------------
# Public IP auto-detection (only when allowed_cidr is left empty)
# ---------------------------------------------------------------------------
data "http" "myip" {
  count = var.allowed_cidr == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  detected_cidr = var.allowed_cidr != "" ? var.allowed_cidr : "${chomp(data.http.myip[0].response_body)}/32"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    forgevm_version = var.forgevm_version
    xfs_size_gb     = var.forgevm_xfs_size_gb
  })
}

# ---------------------------------------------------------------------------
# Latest Amazon Linux 2023 x86_64 AMI (via the SSM public parameter)
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# Default VPC + a subnet to place the instance in
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# SSH key pair (created from your local public key)
# ---------------------------------------------------------------------------
resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))
}

# ---------------------------------------------------------------------------
# Security group: SSH + ForgeVM API, both scoped to allowed_cidr
# ---------------------------------------------------------------------------
resource "aws_security_group" "forgevm" {
  name_prefix = "forgevm-sandbox-"
  description = "ForgeVM sandbox: SSH + ForgeVM API, scoped to a single CIDR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.detected_cidr]
  }

  ingress {
    description = "ForgeVM API"
    from_port   = 7423
    to_port     = 7423
    protocol    = "tcp"
    cidr_blocks = [local.detected_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "forgevm-sandbox" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------
resource "aws_instance" "forgevm" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.forgevm.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  # Native provider path for nested virtualization (recent AWS provider required).
  # When method = "cli", this block is omitted and null_resource.enable_nested_virt
  # enables it after launch instead.
  dynamic "cpu_options" {
    for_each = var.nested_virtualization_method == "provider" ? [1] : []
    content {
      nested_virtualization = "enabled"
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # enforce IMDSv2
  }

  tags = { Name = "forgevm-sandbox" }
}

# ---------------------------------------------------------------------------
# Elastic IP — a stable address that survives the stop/start cycle used by the
# CLI nested-virt path (and keeps outputs correct in all cases).
# ---------------------------------------------------------------------------
resource "aws_eip" "forgevm" {
  domain   = "vpc"
  instance = aws_instance.forgevm.id
  tags     = { Name = "forgevm-sandbox" }
}

# ---------------------------------------------------------------------------
# CLI fallback: enable nested virtualization on the (stopped) instance, then
# start it again. Only used when nested_virtualization_method = "cli".
# Requires the AWS CLI (>= 2.33.21) on the machine running Terraform.
# ---------------------------------------------------------------------------
resource "null_resource" "enable_nested_virt" {
  count = var.nested_virtualization_method == "cli" ? 1 : 0

  # Ensure the EIP is associated before we stop/start, so the address is stable.
  depends_on = [aws_eip.forgevm]

  triggers = {
    instance_id = aws_instance.forgevm.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      IID="${aws_instance.forgevm.id}"
      REGION="${var.region}"
      echo "[nested-virt/cli] Stopping $IID ..."
      aws ec2 stop-instances       --region "$REGION" --instance-ids "$IID" >/dev/null
      aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$IID"
      echo "[nested-virt/cli] Enabling nested virtualization ..."
      aws ec2 modify-instance-cpu-options --region "$REGION" \
        --instance-id "$IID" --nested-virtualization enabled >/dev/null
      echo "[nested-virt/cli] Starting $IID ..."
      aws ec2 start-instances       --region "$REGION" --instance-ids "$IID" >/dev/null
      aws ec2 wait instance-running --region "$REGION" --instance-ids "$IID"
      echo "[nested-virt/cli] Done. /dev/kvm will be present after this boot; the forgevm service will pick it up."
    EOT
  }
}
