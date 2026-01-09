# Direct state file to S3 bucket and connect DynamoDB table
terraform {
  backend "s3" {
    bucket         = "nmilligan-tf-states"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-bootstrap"
    encrypt        = true
  }
}

# Create locals
locals {
  root_domain = "banksie.app"
  subdomain  = "www.banksie.app
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

# Create hosted zone
resource "aws_route53_zone" "hosted_zone" {
  name = "banksie.app"
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
