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
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${aws_ecr_repository.app_repo.name}:latest"

          env {
            name  = "DB_USERNAME"
            value = aws_db_instance.app_db.username
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
            value = aws_db_instance.app_db.address
          }

          env {
            name  = "DB_PORT"
            value = 5432
          }

          env {
            name  = "DB_NAME"
            value = aws_db_instance.app_db.db_name
          }

          ports {
            container_port = 5000
          }
        }
      }
    }
  }
}