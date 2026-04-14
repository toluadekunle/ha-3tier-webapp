variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "certificate_arn" {
  type    = string
  default = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for internal ALB"
  type        = list(string)
}

variable "int_alb_sg_id" {
  description = "Security group ID for internal ALB"
  type        = string
}
