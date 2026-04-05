# ============================================================
#  modules/alb/main.tf — External ALB (Web) + Internal ALB (App)
# ============================================================

# ── External ALB (Internet-facing → Web Tier) ─────────────
resource "aws_lb" "external" {
  name               = "${var.project_name}-${var.environment}-ext-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false  # set true in production
  enable_cross_zone_load_balancing = true
  idle_timeout                     = 60

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "ext-alb"
    enabled = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-ext-alb", Type = "external" }
}

# ── ALB Access Logs S3 Bucket ─────────────────────────────
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-${var.environment}-alb-logs-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-alb-logs" }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/ext-alb/AWSLogs/*"
    }]
  })
}

data "aws_elb_service_account" "main" {}

# ── Web Target Group ──────────────────────────────────────
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = { Name = "${var.project_name}-web-tg" }
}

# ── External ALB Listener: HTTP → redirect to HTTPS ───────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.web.arn
        }
      }
    }
  }
}

# ── External ALB Listener: HTTPS (when cert provided) ─────
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.external.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ── Internal ALB (Web Tier → App Tier) ────────────────────
resource "aws_lb" "internal" {
  name               = "${var.project_name}-${var.environment}-int-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
  tags               = { Name = "${var.project_name}-${var.environment}-int-alb", Type = "internal" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-app-tg" }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
