output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}

output "db_port" {
  value = aws_db_instance.main.port
}

output "db_arn" {
  value = aws_db_instance.main.arn
}
