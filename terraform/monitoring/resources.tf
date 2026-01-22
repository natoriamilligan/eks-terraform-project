# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "monitoring/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}