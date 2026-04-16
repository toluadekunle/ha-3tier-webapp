#!/bin/bash
# ============================================================
#  web_userdata.sh — Web Tier EC2 Bootstrap Script
#  Runs on first boot via Launch Template user_data
#  Installs Nginx as reverse proxy → App Tier (internal ALB)
# ============================================================
set -eo pipefail

APP_TIER_ENDPOINT="${app_tier_endpoint}"
ENVIRONMENT="${environment}"
LOG_FILE="/var/log/userdata.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "======================================================"
echo "  Web Tier Bootstrap — $(date)"
echo "  Environment : $ENVIRONMENT"
echo "  App Endpoint: $APP_TIER_ENDPOINT"
echo "======================================================"

# ── 1. Packages pre-installed via Packer AMI ─────────────
echo "[1/5] Packages already baked into AMI, skipping install..."

# ── 2. Configure Nginx ────────────────────────────────────
echo "[2/5] Configuring Nginx..."
cat > /etc/nginx/nginx.conf <<'NGINX'
user nginx;
worker_processes auto;
error_log  /var/log/nginx/error.log warn;
pid        /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';
    access_log /var/log/nginx/access.log main;
    sendfile        on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    include /etc/nginx/conf.d/*.conf;
}
NGINX


cat > /etc/nginx/conf.d/app.conf <<NGINXAPP
server {
    listen 80;
    resolver 169.254.169.253 valid=30s ipv6=off;
    set \$app_backend "http://${APP_TIER_ENDPOINT}:80";
    server_name _;

    # Health check endpoint (returns 200 directly from Nginx)
    location /health {
        access_log off;
        return 200 '{"status":"healthy","tier":"web","env":"${ENVIRONMENT}"}';
        add_header Content-Type application/json;
    }

    # Static files served directly
    location /static/ {
        root /var/www/html;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }

    # Proxy all other traffic to App Tier
    location / {
        proxy_pass         \$app_backend;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
        proxy_next_upstream   error timeout http_502 http_503;
    }
}
NGINXAPP

# ── 3. Create static landing page ────────────────────────
echo "[3/5] Creating static assets..."
mkdir -p /var/www/html/static
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html><html><head><title>HA 3-Tier Web App</title></head>
<body><h1>Web Tier — $ENVIRONMENT</h1></body></html>
HTML

# ── 4. Start and enable Nginx ─────────────────────────────
echo "[4/5] Starting Nginx..."
nginx -t
systemctl enable nginx
systemctl restart nginx

# ── 5. CloudWatch agent config ────────────────────────────
echo "[5/5] Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/ha-webapp/${ENVIRONMENT}/web/nginx-access",
            "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/ha-webapp/${ENVIRONMENT}/web/nginx-error",
            "log_stream_name": "{instance_id}" }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "cpu":  { "measurement": ["cpu_usage_idle","cpu_usage_user"], "metrics_collection_interval": 60 },
      "mem":  { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["/"], "metrics_collection_interval": 60 }
    }
  }
}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "======================================================"
echo "  ✅ Web Tier Bootstrap COMPLETE — $(date)"
echo "======================================================"
