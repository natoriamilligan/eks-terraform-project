locals {
  root_domain  = "banksie.app"
  subdomain    = "www.banksie.app"
  s3_origin_id = "s3origin"
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

# Create RDS security group
resource "aws_security_group" "db_sg" {
  name        = "rds-sg"
  vpc_id      = aws_vpc.main.id
}

# Create database subnet group to attach to VPC
resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# Create database instance
resource "aws_db_instance" "app_db" {
  allocated_storage      = 20
  db_name                = "mydb"
  identifier             = "mydb"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  username               = "postgres"
  password               = "password"

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name

  skip_final_snapshot    = true
}

# Create private repository in ECR
resource "aws_ecr_repository" "app_repo" {
  name                 = "app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
