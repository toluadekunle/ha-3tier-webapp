# ============================================================
#  main.tf — HA 3-Tier Web App on AWS
#  Author  : Swanand Awatade | Binary Hat Pvt. Ltd.
#  Stack   : VPC → ALB → EC2 ASG (Web + App) → RDS MySQL
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 (uncomment & configure for production)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ha-3tier/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "swanand-awatade"
    }
  }
}

# ── Data Sources ──────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Module: VPC ───────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = data.aws_availability_zones.available.names
  public_subnets      = var.public_subnet_cidrs
  private_app_subnets = var.private_app_subnet_cidrs
  private_db_subnets  = var.private_db_subnet_cidrs
}

# ── Module: Security Groups ───────────────────────────────
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# ── Module: Application Load Balancer ────────────────────
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_app_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  int_alb_sg_id     = module.security.int_alb_sg_id
  certificate_arn   = try(aws_acm_certificate.main.arn, var.certificate_arn)
}

# ── Module: Web Tier ASG ──────────────────────────────────
module "web_tier" {
  source = "./modules/ec2-asg"

  project_name       = var.project_name
  environment        = var.environment
  tier               = "web"
  ami_id             = data.aws_ami.amazon_linux_2023.id
  instance_type      = var.web_instance_type
  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_ids = [module.security.web_sg_id]
  target_group_arn   = module.alb.web_target_group_arn
  secret_arn         = aws_secretsmanager_secret.db_password.arn
  enable_secrets_access = false
  min_size           = var.web_min_size
  max_size           = var.web_max_size
  desired_capacity   = var.web_desired_capacity
  app_port           = 80
  user_data = base64encode(templatefile("${path.module}/scripts/web_userdata.sh", {
    app_tier_endpoint = module.alb.internal_alb_dns
    APP_TIER_ENDPOINT = module.alb.internal_alb_dns
    environment       = var.environment
    ENVIRONMENT       = var.environment
  }))
  key_name = var.key_name
}

# ── Module: App Tier ASG ──────────────────────────────────
module "app_tier" {
  source = "./modules/ec2-asg"

  project_name       = var.project_name
  environment        = var.environment
  tier               = "app"
  ami_id             = data.aws_ami.amazon_linux_2023.id
  instance_type      = var.app_instance_type
  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_ids = [module.security.app_sg_id]
  target_group_arn   = module.alb.app_target_group_arn
  min_size           = var.app_min_size
  secret_arn         = aws_secretsmanager_secret.db_password.arn
  max_size           = var.app_max_size
  desired_capacity   = var.app_desired_capacity
  app_port           = 5000
  user_data = base64encode(templatefile("${path.module}/scripts/app_userdata.sh", {
    db_endpoint  = module.rds.db_endpoint
    db_name      = var.db_name
    db_user      = var.db_username
    db_secret_id = aws_secretsmanager_secret.db_password.id
    DB_SECRET_ID = aws_secretsmanager_secret.db_password.id
    environment  = var.environment
    aws_region   = var.aws_region
    AWS_REGION   = var.aws_region
  }))
  key_name = var.key_name
}

# ── Module: RDS (Database Tier) ───────────────────────────
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [module.security.rds_sg_id]
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = random_password.db_password.result
  instance_class     = var.db_instance_class
  engine_version     = var.db_engine_version
  skip_final_snapshot = true
  deletion_protection = false
  multi_az           = var.db_multi_az
}

# ── Secrets Manager (DB password) ────────────────────────
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-${var.environment}-db-password"
  description             = "RDS MySQL password for ${var.project_name}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = split(":", module.rds.db_endpoint)[0]
    dbname   = var.db_name
    port     = 3306
  })
}

# ── Route 53 DNS (optional) ───────────────────────────────
resource "aws_route53_record" "app" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# ── WAFv2 Web ACL ────────────────────────────────────────
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-${var.environment}-waf"
  description = "WAF for external ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-ip-reputation"
    }
  }

  rule {
    name     = "RateLimit"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = module.alb.external_alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ── ACM Certificate for HTTPS ────────────────────────────
resource "aws_acm_certificate" "main" {
  domain_name       = "app.cybserve.co.uk"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cert"
  }
}

# ── SSM Session Manager Logging ──────────────────────────
resource "aws_ssm_document" "session_logging" {
  name            = "${var.project_name}-${var.environment}-session-prefs"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager logging preferences"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = "/aws/ssm/${var.project_name}-${var.environment}-sessions"
      cloudWatchEncryptionEnabled = false
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = false
      runAsEnabled                = false
      shellProfile = {
        linux = ""
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-session-prefs"
  }
}

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.project_name}-${var.environment}-sessions"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-logs"
  }
}

# ── VPC Interface Endpoints (Private Management Plane) ───
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "Allow HTTPS from VPC to VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-vpce-sg" }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${var.project_name}-${var.environment}-vpce-ssm" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${var.project_name}-${var.environment}-vpce-ssmmessages" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${var.project_name}-${var.environment}-vpce-ec2messages" }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${var.project_name}-${var.environment}-vpce-secrets" }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = { Name = "${var.project_name}-${var.environment}-vpce-logs" }
}
