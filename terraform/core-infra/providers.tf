terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "3.8.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "random" {}

