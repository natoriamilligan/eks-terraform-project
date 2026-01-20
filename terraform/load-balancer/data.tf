# Reference core-infra Terraform state
data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket = "nmilligan-tf-states"
    key    = "core-infra/terraform.tfstate"
    region = var.region
  }
}

# Reference core-infra Terraform state
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = "nmilligan-tf-states"
    key    = "bootstrap/terraform.tfstate"
    region = var.region
  }
}

data "aws_iam_policy_document" "lb_controller_trust_policy" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.core.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.core.outputs.oidc_provider}:sub"
      values   = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.core.outputs.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_eks_cluster" "eks" {
  name = data.terraform_remote_state.core.outputs.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = data.aws_eks_cluster.eks.name
}
