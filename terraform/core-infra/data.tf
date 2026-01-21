# Create bucket policy for S3 bucket to allow CloudFront access
data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      actions = [
        "s3:GetObject",
      ]

      resources = [
        "${aws_s3_bucket.app_bucket.arn}/*",
      ]

      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = [aws_cloudfront_distribution.app_distribution.arn]
      }
    }
}

data "aws_iam_policy_document" "external_secrets_trust_policy" {
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
        "system:serviceaccount:default:external-secrets"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.core.outputs.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_caller_identity" "current" {}