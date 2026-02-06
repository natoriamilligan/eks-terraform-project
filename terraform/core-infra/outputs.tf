output "vpc_id" {
  value = aws_vpc.main.id
}

output "external_secrets_role" {
  value = aws_iam_role.external_secrets_role.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}

output "jwt_secret_name" {
  value = aws_secretsmanager_secret.jwt.name
}

output "repo_name" {
  value = aws_ecr_repository.app_repo.name
}

output "db_username" {
  value = aws_db_instance.app_db.username
}

output "db_host" {
  value     = aws_db_instance.app_db.address
  sensitive = true
}

output "db_name" {
  value = aws_db_instance.app_db.db_name
}

output "external_DNS_role" {
  value = aws_iam_role.external_DNS_role.arn
}

output "lb_controller_role" {
  value =  aws_iam_role.lb_controller_role.arn 
}

output "api_cert_arn" {
  value = aws_acm_certificate.api_cert.arn
}

output "pod_sg_id" {
  value = aws_security_group.pod_sg.id
}