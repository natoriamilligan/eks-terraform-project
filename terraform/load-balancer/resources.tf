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

locals {
  api_domain = api.banksie.app
}

# Create TLS certificate for api domain
resource "aws_acm_certificate" "api_cert" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create CNAME records in hosted zone for api
resource "aws_route53_record" "api_validation_record" {
  for_each = {
    for domain in aws_acm_certificate.api_cert.domain_validation_options : domain.domain_name => {
      name    = domain.resource_record_name
      record  = domain.resource_record_value
      type    = domain.resource_record_type
      zone_id = aws_route53_zone.hosted_zone.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 300
  type            = each.value.type
  zone_id         = each.value.zone_id
}

# Validate the api certificate using CNAME records
resource "aws_acm_certificate_validation" "api_cert_validation" {
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.api_validation_record : record.fqdn]
}

# IAM role for ExternalDNS
resource "aws_iam_role" "external_DNS_role" {
  name               = "external-DNS-role"
  assume_role_policy = data.aws_iam_policy_document.external_DNS_trust_policy.json
}

# IAM policy for ExternalDNS 
resource "aws_iam_policy" "external_DNS" {
  name = "ExternalDNSPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = [data.terraform_remote_state.bootstrap.outputs.hosted_zone] 
      }
    ]
  })
}

# Attach policy to ExternalDNS role
resource "aws_iam_role_policy_attachment" "external_DNS" {
  role       = aws_iam_role.external_DNS.name
  policy_arn = aws_iam_policy.external_DNS.arn
}

# ExternalDNS service account
resource "kubernetes_service_account" "external_DNS" {
  metadata {
    name      = "external-DNS"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_DNS_role.arn
    }
  }
}

# Create ExternalDNS via Helm
resource "helm_release" "external_DNS" {
  name       = "external-DNS"
  namespace  = "default"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  version    = "9.0.3" 

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.zoneType"
    value = "public"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_DNS.metadata[0].name
  }

  set {
    name  = "txtOwnerId"
    value = "external-DNS"
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
    value = data.terraform_remote_state.core.outputs.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.core.outputs.vpc_id
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

# Kubernetes service
resource "kubernetes_service" "app_lb_service" {
  metadata {
    name = "app-lb-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "app-pod"
    }

    port {
      port        = 80
      target_port = 5000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Kubernetes ingress for ALB 
resource "kubernetes_ingress" "app_lb_ingress" {
  metadata {
    name      = "app-lb-ingress"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.api_cert.arn
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "external-dns.alpha.kubernetes.io/hostname" = api.banksie.app
    }
  }

  spec {
    rule {
      host = "api.example.com"

      http {
        path {
          path     = "/"
          path_type= "Prefix"

          backend {
            service {
              name = kubernetes_service.app_lb_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [aws_acm_certificate.app_cert]
}

# IAM role for pods
resource "aws_iam_role" "pod_role" {
  name               = "pod-role"
  assume_role_policy = data.aws_iam_policy_document.pod_trust_policy.json
}

# IAM policy for pods
resource "aws_iam_policy" "pods" {
  name = "EKSPodPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [data.terraform_remote_state.core.outputs.db_secret.arn] 
      }
    ]
  })
}

# Attach policy to pod role
resource "aws_iam_role_policy_attachment" "pods" {
  role       = aws_iam_role.pod_role.name
  policy_arn = aws_iam_policy.pods.arn
}

# Pod service account
resource "kubernetes_service_account" "pods" {
  metadata {
    name      = "pods"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn"        = aws_iam_role.pod_role.arn
      "eks.amazonaws.com/security-groups" = data.terraform_remote_state.core.outputs.pod_sg
    }
  }
}