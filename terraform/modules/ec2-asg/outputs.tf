output "asg_name"            { value = aws_autoscaling_group.main.name }
output "launch_template_id"  { value = aws_launch_template.main.id }
output "iam_role_arn"        { value = aws_iam_role.ec2.arn }
