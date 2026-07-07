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

variable "subnet_id" {
  description = "Subnet to launch into. Leave empty to use the default VPC's first subnet. REQUIRED if your account has no default VPC. Pick a public subnet (one whose route table has an internet gateway) so the Elastic IP is reachable."
  type        = string
  default     = ""
}

variable "generate_ssh_key" {
  description = "If true, Terraform generates an SSH keypair and writes the private key to generated_key_path (mode 0600) instead of reading public_key_path. Handy when you don't already have a key."
  type        = bool
  default     = false
}

variable "generated_key_path" {
  description = "Where to write the generated private key when generate_ssh_key = true."
  type        = string
  default     = "./forgevm-ssh-key.pem"
}

variable "public_key_path" {
  description = "Path to an existing SSH public key installed for ec2-user. Used only when generate_ssh_key = false. Generate one with `ssh-keygen -t ed25519` if you don't have it."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "key_name" {
  description = "Name for the AWS key pair created from public_key_path."
  type        = string
  default     = "forgevm-sandbox"
}

variable "use_elastic_ip" {
  description = "Allocate an Elastic IP for a stable address. Default false so an idle auto-terminate leaves nothing billable behind (the auto-assigned public IP is used and released on terminate). Set true if you use nested_virtualization_method = \"cli\", whose stop/start would otherwise change the auto-assigned IP."
  type        = bool
  default     = false
}

variable "auto_terminate_idle" {
  description = "Idle cost guard: an in-instance systemd timer TERMINATES the box after idle_minutes of inactivity (no running ForgeVM sandboxes, no SSH sessions, low CPU load) via an OS shutdown. Needs no CloudWatch/IAM. Terminating also deletes the root EBS. Set false to let the box persist untended (and shutdown just stops it)."
  type        = bool
  default     = true
}

variable "idle_minutes" {
  description = "Minutes of sustained inactivity before the in-instance idle guard terminates the box (checked every 5 minutes, with a ~15m grace period after boot)."
  type        = number
  default     = 45
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
