terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.core.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.core.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}