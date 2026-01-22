# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "k8s/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

# Service account for external secrets
resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.external_secrets_role
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = "kube-system"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "1.2.1"

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_secrets.metadata[0].name
  }

  depends_on = [
    kubernetes_service_account.external_secrets
  ]
}

# Connect Kubernetes to AWS
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"

    metadata = {
      name = "aws-secrets"
    }

    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "us-east-1"

          auth = {
            jwt = {
              serviceAccountRef = {
                name      = kubernetes_service_account.external_secrets.metadata[0].name
                namespace = "kube-system"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.external_secrets
  ]
}

resource "kubernetes_manifest" "db_password_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"

    metadata = {
      name      = "db-password"
      namespace = "default"
    }

    spec = {
      refreshInterval = "1h"

      secretStoreRef = {
        name = "aws-secrets"
        kind = "ClusterSecretStore"
      }

      target = {
        name           = "db-password"
        creationPolicy = "Owner"
      }

      data = [
        {
          secretKey = "DB_PASSWORD"
          remoteRef = {
            key      = data.terraform_remote_state.core.outputs.secret_name
            property = "password"
          }
        }
      ]
    }
  }
}

resource "kubernetes_deployment" "app_deployment" {
  metadata {
    name      = "app-deployment"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "app-pod"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-pod"
        }
      }

      spec {
        container {
          name  = "app-container"
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${data.terraform_remote_state.core.outputs.repo_name}:latest"

          env {
            name  = "DB_USERNAME"
            value = data.terraform_remote_state.core.outputs.db_username
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "app-db-secret"
                key  = "DB_PASSWORD"
              }
            }
          }

          env {
            name  = "DB_HOST"
            value = data.terraform_remote_state.core.outputs.db_host
          }

          env {
            name  = "DB_PORT"
            value = 5432
          }

          env {
            name  = "DB_NAME"
            value = data.terraform_remote_state.core.outputs.db_name
          }

          ports {
            container_port = 5000
          }
        }
      }
    }
  }
}

# ExternalDNS service account
resource "kubernetes_service_account" "external_DNS" {
  metadata {
    name      = "external-DNS"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.external_DNS_role
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

  depends_on = [
    kubernetes_service_account.external_DNS
  ]
}

# LB Controller service account
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.lb_controller_role
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

  depends_on = [
    kubernetes_service_account.lb_controller
  ]
}

# Kubernetes service for load balancer
resource "kubernetes_service" "app_lb_service" {
  metadata {
    name = "app-lb-service"
    namespace = "default"
    labels = {
      app = "app-lb-service" 
    }
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
      "alb.ingress.kubernetes.io/certificate-arn" = data.terraform_remote_state.core.outputs.api_cert_arn
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "external-dns.alpha.kubernetes.io/hostname" = api.banksie.app
    }
  }

  spec {
    rule {
      host = "api.banksie.app"

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
}

# Pod service account
resource "kubernetes_service_account" "pods" {
  metadata {
    name      = "pods"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/security-groups" = data.terraform_remote_state.core.outputs.pod_sg_id
    }
  }
}