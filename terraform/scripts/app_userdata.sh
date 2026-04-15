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

# ── 1. System update & packages ──────────────────────────
echo "[1/6] Installing system packages..."
dnf update -y
dnf install -y python3 python3-pip python3-devel mariadb105 gcc jq amazon-cloudwatch-agent

# ── 2. Create app user & directory ───────────────────────
echo "[2/6] Setting up app directory..."
useradd -r -s /bin/false appuser 2>/dev/null || true
mkdir -p "$APP_DIR"
chown appuser:appuser "$APP_DIR"
mkdir -p /var/log/app
chown appuser:appuser /var/log/app

# ── 3. Install Python dependencies ───────────────────────
echo "[3/6] Installing Python packages..."
pip3 install flask gunicorn pymysql boto3 cryptography --quiet

# ── 4. Write the Flask application ───────────────────────
echo "[4/6] Writing Flask application..."
cat > "$APP_DIR/app.py" <<'PYAPP'
import os, json, logging
import boto3
import pymysql
from flask import Flask, jsonify, request
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler("/var/log/app/app.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ── DB Connection via Secrets Manager ─────────────────────
def get_db_secret():
    secret_id = os.environ["DB_SECRET_ID"]
    region    = os.environ.get("AWS_REGION", "ap-south-1")
    client    = boto3.client("secretsmanager", region_name=region)
    secret    = client.get_secret_value(SecretId=secret_id)
    return json.loads(secret["SecretString"])

def get_db_connection():
    creds = get_db_secret()
    return pymysql.connect(
        host     = creds["host"],
        user     = creds["username"],
        password = creds["password"],
        database = creds["dbname"],
        port     = int(creds.get("port", 3306)),
        connect_timeout = 5,
        cursorclass = pymysql.cursors.DictCursor
    )

# ── Routes ─────────────────────────────────────────────────
@app.route("/api/health")
def health():
    db_status = "unknown"
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
        logger.error("DB health check failed: %s", e)

    return jsonify({
        "status":      "healthy" if db_status == "connected" else "degraded",
        "tier":        "app",
        "environment": os.environ.get("ENVIRONMENT", "unknown"),
        "database":    db_status,
        "timestamp":   datetime.utcnow().isoformat()
    }), 200

@app.route("/api/live")
def live():
    return jsonify({"status": "alive", "tier": "app"}), 200

@app.route("/api/ready")
def ready():
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return jsonify({"status": "ready", "database": "connected"}), 200
    except Exception as e:
        logger.error("Readiness check failed: %s", e)
        return jsonify({"status": "not_ready", "database": str(e)}), 503

@app.route("/api/info")
def info():
    return jsonify({
        "app":         "ha-3tier-webapp",
        "tier":        "app",
        "environment": os.environ.get("ENVIRONMENT", "unknown"),
        "version":     os.environ.get("APP_VERSION", "1.0.0"),
        "db_host":     os.environ.get("DB_ENDPOINT", ""),
        "timestamp":   datetime.utcnow().isoformat()
    })

@app.route("/api/items", methods=["GET"])
def get_items():
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM items ORDER BY created_at DESC LIMIT 50")
            items = cur.fetchall()
        conn.close()
        return jsonify({"items": items, "count": len(items)})
    except Exception as e:
        logger.error("GET /api/items failed: %s", e)
        return jsonify({"error": "Database error", "detail": str(e)}), 500

@app.route("/api/items", methods=["POST"])
def create_item():
    data = request.get_json()
    if not data or "name" not in data:
        return jsonify({"error": "name field required"}), 400
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO items (name, description) VALUES (%s, %s)",
                (data["name"], data.get("description", ""))
            )
            conn.commit()
            item_id = cur.lastrowid
        conn.close()
        logger.info("Created item id=%s name=%s", item_id, data["name"])
        return jsonify({"id": item_id, "name": data["name"], "status": "created"}), 201
    except Exception as e:
        logger.error("POST /api/items failed: %s", e)
        return jsonify({"error": "Database error", "detail": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYAPP

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
