locals {
  root_domain = "banksie.app"
  subdomain   = "www.banksie.app"
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
