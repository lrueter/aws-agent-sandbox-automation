variable "region" {
  description = "AWS region to deploy into. Nested virtualization is documented as available in all commercial regions; verify capacity for the chosen family before relying on it."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. MUST be a family that supports nested virtualization."
  type        = string
  default     = "m7i-flex.large"

  validation {
    condition     = can(regex("^(c8i|m8i|r8i|c8id|r8id|m8id|c8i-flex|r8i-flex|m8i-flex|x8i|c7i|r7i|m7i|c7i-flex|m7i-flex|i7i)\\.", var.instance_type))
    error_message = "instance_type must be a nested-virtualization-capable family: c8i, m8i, r8i, c8id, r8id, m8id, c8i-flex, r8i-flex, m8i-flex, x8i, c7i, r7i, m7i, c7i-flex, m7i-flex, i7i (e.g. m7i-flex.large)."
  }
}

variable "root_volume_size" {
  description = "Size of the root gp3 EBS volume in GiB (host OS + Docker images + the XFS loopback used for ForgeVM snapshots)."
  type        = number
  default     = 40
}

variable "forgevm_version" {
  description = "ForgeVM version to install. Empty string installs the latest release."
  type        = string
  default     = ""
}

variable "forgevm_xfs_size_gb" {
  description = "Size (GiB) of the XFS reflink loopback volume mounted at /var/lib/forgevm for fast (~28-35ms) snapshot restore."
  type        = number
  default     = 8
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach SSH (22) and the ForgeVM API (7423). Leave empty to auto-detect this machine's public IP as a /32."
  type        = string
  default     = ""
}

variable "public_key_path" {
  description = "Path to an SSH public key installed for the ec2-user account. Generate one with `ssh-keygen` if you don't have it."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "key_name" {
  description = "Name for the AWS key pair created from public_key_path."
  type        = string
  default     = "forgevm-sandbox"
}

variable "nested_virtualization_method" {
  description = <<-EOT
    How to enable nested virtualization:
      - "provider": use the aws_instance cpu_options block (cleanest; needs a recent AWS provider that exposes nested_virtualization).
      - "cli": enable it post-launch via `aws ec2 modify-instance-cpu-options` (works with any provider version; requires the AWS CLI (>= 2.33.21) on the machine running Terraform).
  EOT
  type        = string
  default     = "provider"

  validation {
    condition     = contains(["provider", "cli"], var.nested_virtualization_method)
    error_message = "nested_virtualization_method must be either \"provider\" or \"cli\"."
  }
}
