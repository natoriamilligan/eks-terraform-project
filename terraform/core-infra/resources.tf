# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "core-infra/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

locals {
  root_domain  = "banksie.app"
  subdomain    = "www.banksie.app"
  s3_origin_id = "s3origin"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create public subnets
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
}

# Create public route table and connect internet gateway
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
  }
}

# Connect public subnet to route table for internet access
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.route_table.id
}

# Create elastic IP for NAT Gateway
resource "aws_eip" "ngw" {}

# Create NAT Gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw.id
  subnet_id     = aws_subnet.public_a.id

  depends_on    = [aws_internet_gateway.igw]
}

# Create private route table and connect NAT gateway
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_nat_gateway.ngw.id
  }
}

# Create private subnets
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Attach private subnets to private route tables
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create S3 bucket
resource "aws_s3_bucket" "app_bucket" {
  bucket = local.root_domain
}

# Attach bucket policy to S3 bucket for CloudFront access
resource "aws_s3_bucket_policy" "app_bucket_policy" {
  bucket = aws_s3_bucket.app_bucket.bucket
  policy = data.aws_iam_policy_document.origin_bucket_policy.json

  depends_on = [aws_cloudfront_distribution.app_distribution]
}

# Create TLS certificate for root and subdomain
resource "aws_acm_certificate" "domain_cert" {
  domain_name       = local.root_domain
  subject_alternative_names = [local.subdomain]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create CNAME records in hosted zone for domain/subdomain
resource "aws_route53_record" "validation_records" {
  for_each = {
    for domain in aws_acm_certificate.domain_cert.domain_validation_options : domain.domain_name => {
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

# Validate the domain/subdomain certificate using CNAME records
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.domain_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation_records : record.fqdn]
}

# Create OAC for S3 bucket and CloudFront distribution
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Create policy to prevent forwarding to S3
resource "aws_cloudfront_origin_request_policy" "ORP_policy" {
  name    = "ORP-policy"
  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "none"
  }
  query_strings_config {
    query_string_behavior = "none"
  }
}

# Create policy to limit caching to S3
resource "aws_cloudfront_cache_policy" "s3_cache_policy" {
  name        = "s3-cache-policy"
  default_ttl = 3600
  max_ttl     = 86400
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# Create Cloudfront distribution
resource "aws_cloudfront_distribution" "app_distribution" {
  origin {
    domain_name              = aws_s3_bucket.app_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  aliases = [local.root_domain, local.subdomain]

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = local.s3_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.s3_cache_policy.id 
    origin_request_policy_id = aws_cloudfront_origin_request_policy.ORP_policy.id
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }  

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.domain_cert.arn
    ssl_support_method  = "sni-only"
  }
}

# Create A records pointing to the CloudFront distribution
resource "aws_route53_record" "cloudfront" {
  for_each = aws_cloudfront_distribution.app_distribution.aliases
  zone_id  = aws_route53_zone.hosted_zone.zone_id
  name     = each.value
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.app_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.app_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Create pod security group for RDS instance
resource "aws_security_group" "pod_sg" {
  name        = "pod-sg"
  vpc_id      = aws_vpc.main.id
}

# Create RDS security group
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  vpc_id      = aws_vpc.main.id
}

# Allow database traffic from pods
resource "aws_security_group_rule" "allow_pods" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.pod_sg.id
  security_group_id        = aws_security_group.db_sg.id
}

# Create database subnet group to attach to VPC
resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# Generate random password 
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# Store random password in Secrets Manager 
resource "aws_secretsmanager_secret" "db_password" {
  name = "db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    password = random_password.db_password.result
  })

  depends_on    = [aws_secretsmanager_secret.db_password, random_password.db_password]
}


# Create database instance
resource "aws_db_instance" "app_db" {
  allocated_storage           = 20
  db_name                     = "appdb"
  identifier                  = "appdb"
  engine                      = "postgres"
  instance_class              = "db.t3.micro"
  username                    = "postgres"
  password                    = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string["password"])

  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  db_subnet_group_name        = aws_db_subnet_group.db_subnet_group.name

  skip_final_snapshot         = true

  depends_on = [aws_secretsmanager_secret_version.db_password]
}

# Create private repository in ECR
resource "aws_ecr_repository" "app_repo" {
  name                 = "app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM role for external secrets
resource "aws_iam_role" "external_secrets_role" {
  name               = "external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust_policy.json
}

# IAM policy for external secrets
resource "aws_iam_policy" "external_secrets" {
  name = "ExternalSecretsPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [aws_db_instance.app_db.master_user_secret[0].secret_arn] 
      }
    ]
  })
}

# Attach policy to external secrets role
resource "aws_iam_role_policy_attachment" "pods" {
  role       = aws_iam_role.external_secrets_role.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# Service account for external secrets
resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets_role.arn
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


# Pod service account
resource "kubernetes_service_account" "pods" {
  metadata {
    name      = "pods"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/security-groups" = aws_security_group.pod_sg.id
    }
  }
}

