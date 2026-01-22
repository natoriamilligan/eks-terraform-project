terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.core.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.core.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}