#!/bin/bash
# ============================================================
#  app_userdata.sh — App Tier EC2 Bootstrap Script
#  Installs Python Flask API + connects to RDS via Secrets Manager
# ============================================================
set -euo pipefail

DB_ENDPOINT="${db_endpoint}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_SECRET_ID="${db_secret_id}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"
APP_DIR="/opt/app"
LOG_FILE="/var/log/userdata.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "======================================================"
echo "  App Tier Bootstrap — $(date)"
echo "  Environment : $ENVIRONMENT"
echo "  DB Endpoint : $DB_ENDPOINT"
echo "======================================================"

# ── 1. Packages pre-installed via Packer AMI ──────────────
echo "[1/6] Packages already baked into AMI, skipping install..."

# ── 2. App user and directories pre-created via Packer AMI
echo "[2/6] App user and directories already exist, skipping..."

# ── 3. Python packages pre-installed via Packer AMI ──────
echo "[3/6] Python packages already baked into AMI, skipping..."

# ── 4. Flask app pre-baked into AMI via Packer ───────────
echo "[4/6] App code already baked into AMI, skipping..."

# ── 5. Initialize DB schema ───────────────────────────────
echo "[5/6] Initializing database schema..."
cat > /tmp/init_db.py <<PYINIT
import boto3, pymysql, json, os, time

secret_id = os.environ.get("DB_SECRET_ID", "${DB_SECRET_ID}")
region    = os.environ.get("AWS_REGION",   "${AWS_REGION}")

for attempt in range(10):
    try:
        client = boto3.client("secretsmanager", region_name=region)
        secret = json.loads(client.get_secret_value(SecretId=secret_id)["SecretString"])
        conn   = pymysql.connect(
            host=secret["host"], user=secret["username"],
            password=secret["password"], database=secret["dbname"],
            connect_timeout=10
        )
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    name        VARCHAR(255) NOT NULL,
                    description TEXT,
                    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            """)
            cur.execute("""
                INSERT IGNORE INTO items (id, name, description)
                VALUES (1, 'Sample Item', 'Seeded by bootstrap script');
            """)
            conn.commit()
        conn.close()
        print("DB schema initialized successfully")
        break
    except Exception as e:
        print(f"Attempt {attempt+1}/10 failed: {e}")
        time.sleep(15)
PYINIT

export DB_SECRET_ID="$DB_SECRET_ID"
export AWS_REGION="$AWS_REGION"
python3 /tmp/init_db.py || echo "DB init skipped (may already exist)"

# ── 6. Create systemd service & start ─────────────────────
echo "[6/6] Creating systemd service..."
cat > /etc/systemd/system/app.service <<SVCUNIT
[Unit]
Description=HA 3-Tier App — Flask API
After=network.target

[Service]
User=appuser
WorkingDirectory=$APP_DIR
Environment="ENVIRONMENT=$ENVIRONMENT"
Environment="DB_ENDPOINT=$DB_ENDPOINT"
Environment="DB_SECRET_ID=$DB_SECRET_ID"
Environment="AWS_REGION=$AWS_REGION"
Environment="APP_VERSION=1.0.0"
ExecStart=/usr/local/bin/gunicorn \
    --bind 0.0.0.0:5000 \
    --workers 4 \
    --timeout 60 \
    --access-logfile /var/log/app/access.log \
    --error-logfile  /var/log/app/error.log \
    app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCUNIT

systemctl daemon-reload
systemctl enable app
systemctl start app

# CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/app/app.log",
            "log_group_name": "/ha-webapp/$ENVIRONMENT/app/application",
            "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/app/access.log",
            "log_group_name": "/ha-webapp/$ENVIRONMENT/app/access",
            "log_stream_name": "{instance_id}" }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "cpu":  { "measurement": ["cpu_usage_idle","cpu_usage_user"], "metrics_collection_interval": 60 },
      "mem":  { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 }
    }
  }
}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "======================================================"
echo "  ✅ App Tier Bootstrap COMPLETE — $(date)"
echo "======================================================"
