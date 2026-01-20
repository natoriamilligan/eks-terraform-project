output "vpc_id" {
  value = aws_vpc.main.id
}

output "pod_sg" {
  value = aws_security_group.pod_sg.id
}