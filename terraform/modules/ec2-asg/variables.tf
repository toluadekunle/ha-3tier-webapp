variable "project_name" { type = string }
variable "environment" { type = string }
variable "tier" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "target_group_arn" { type = string }
variable "min_size" { type = number }
variable "max_size" { type = number }
variable "desired_capacity" { type = number }
variable "app_port" { type = number }
variable "user_data" { type = string }
variable "key_name" { type = string }

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret for IAM policy scoping"
  type        = string
  default     = "*"
}

variable "enable_secrets_access" {
  description = "Whether to create Secrets Manager read policy"
  type        = bool
  default     = true
}
