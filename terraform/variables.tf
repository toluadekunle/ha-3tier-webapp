# ============================================================
#  variables.tf — Input variables for HA 3-Tier Web App
# ============================================================

# ── General ───────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ha-webapp"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be prod, staging, or dev."
  }
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

# ── Networking ────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB, NAT Gateway)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs for private app subnets (Web + App EC2)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDRs for private DB subnets (RDS)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ── Web Tier ──────────────────────────────────────────────
variable "web_instance_type" {
  description = "EC2 instance type for web tier"
  type        = string
  default     = "t3.micro"
}

variable "web_min_size" {
  description = "Minimum instances in web ASG"
  type        = number
  default     = 2
}

variable "web_max_size" {
  description = "Maximum instances in web ASG"
  type        = number
  default     = 6
}

variable "web_desired_capacity" {
  description = "Desired instances in web ASG"
  type        = number
  default     = 2
}

# ── App Tier ──────────────────────────────────────────────
variable "app_instance_type" {
  description = "EC2 instance type for app tier"
  type        = string
  default     = "t3.small"
}

variable "app_min_size" {
  description = "Minimum instances in app ASG"
  type        = number
  default     = 2
}

variable "app_max_size" {
  description = "Maximum instances in app ASG"
  type        = number
  default     = 6
}

variable "app_desired_capacity" {
  description = "Desired instances in app ASG"
  type        = number
  default     = 2
}

# ── Database Tier ─────────────────────────────────────────
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "dbadmin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

# ── ALB / DNS ─────────────────────────────────────────────
variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (leave empty to use HTTP only)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Route 53 domain name (leave empty to skip DNS record)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "web_ami_id" {
  description = "Packer-built web tier AMI ID"
  type        = string
}

variable "app_ami_id" {
  description = "Packer-built app tier AMI ID"
  type        = string
}
