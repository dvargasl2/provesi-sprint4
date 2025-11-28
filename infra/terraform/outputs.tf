output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.guard_host.id
}

output "public_dns" {
  description = "DNS público"
  value       = aws_instance.guard_host.public_dns
}
