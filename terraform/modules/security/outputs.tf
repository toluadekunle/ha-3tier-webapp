output "alb_sg_id" { value = aws_security_group.alb.id }
output "web_sg_id" { value = aws_security_group.web.id }
output "app_sg_id" { value = aws_security_group.app.id }
output "rds_sg_id" { value = aws_security_group.rds.id }
