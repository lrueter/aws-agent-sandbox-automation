provider "aws" {
  region = var.region

  # Credentials are read from the default AWS credential chain — for this setup,
  # the AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (and optionally AWS_SESSION_TOKEN)
  # environment variables. No profile is referenced.

  default_tags {
    tags = {
      Project   = "forgevm-sandbox"
      ManagedBy = "terraform"
    }
  }
}
