terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # `nested_virtualization` inside cpu_options is a recent addition.
      # If `terraform plan` reports "Unsupported argument nested_virtualization",
      # run `terraform init -upgrade`, or set nested_virtualization_method = "cli".
      version = ">= 6.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}
