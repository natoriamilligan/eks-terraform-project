# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "load-balancer/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

# Create Load Balancer Controller IAM role
resource "aws_iam_role" "lb_controller_role" {
  name               = "lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust_policy.json
}

# Create policy for LB Controller
resource "aws_iam_policy" "lb_controller" {
  name   = "LBControllerIAMPolicy"
  policy = file("${path.module}/lb-iam-policy.json")
}

# Attach LB Controller policy to IAM role
resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.lb_controller_role.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# LB Controller service account
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lb_controller_role.arn
    }
  }
}

# Install LB Controller from Helm LB chart
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "2.17.1"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.eks.outputs.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.eks.outputs.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lb_controller.name
  }
}
