# Reference core-infra Terraform state
data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket = "nmilligan-tf-states"
    key    = "core-infra/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

