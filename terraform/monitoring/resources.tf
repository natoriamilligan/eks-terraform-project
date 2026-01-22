# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "monitoring/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

resource "helm_release" "monitoring" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"

  namespace         = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      grafana = {
        enabled = true

        adminUser     = "admin"
        adminPassword = "changeme"

        service = {
          type = "ClusterIP"
        }
      }

      prometheus = {
        prometheusSpec = {
          retention = "7d"
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "app-service-monitor"
      namespace = "monitoring"
    }

    spec = {
      selector = {
        matchLabels = {
          app = "app-lb-service"
        }
      }

      namespaceSelector = {
        matchNames = ["default"]
      }

      endpoints = [
        {
          port = "http"
          path = "/metrics"
          interval = "30s"
        }
      ]
    }
  }
}