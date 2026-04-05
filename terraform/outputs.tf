# ============================================================
#  outputs.tf — Key outputs after terraform apply
# ============================================================

output "alb_dns_name" {
  description = "Public ALB DNS name — open this in browser"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias)"
  value       = module.alb.alb_zone_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs"
  value       = module.vpc.private_db_subnet_ids
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "web_asg_name" {
  description = "Web tier Auto Scaling Group name"
  value       = module.web_tier.asg_name
}

output "app_asg_name" {
  description = "App tier Auto Scaling Group name"
  value       = module.app_tier.asg_name
}

output "app_url" {
  description = "Application URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${module.alb.alb_dns_name}"
}
