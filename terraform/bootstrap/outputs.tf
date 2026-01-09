output "nameservers" {
  value       = aws_route53_zone.hosted_zone.name_servers
  description = "List of nameservers for hosted zone"
}
