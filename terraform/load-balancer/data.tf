# Reference eks module created in another state
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "nmilligan-tf-states"
    key    = "load-balancer/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_iam_policy_document" "lb_controller_trust_policy" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider}:sub"
      values   = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
}
