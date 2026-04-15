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

@app.route("/")
def index():
    db_status = "unknown"
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) as count FROM items")
            count = cur.fetchone()["count"]
        conn.close()
        db_status = "connected"
    except Exception as e:
        db_status = str(e)
        count = 0

    return f"""<!DOCTYPE html>
<html>
<head>
    <title>HA 3-Tier Web App</title>
    <style>
        body {{ font-family: -apple-system, sans-serif; max-width: 700px; margin: 60px auto; padding: 0 20px; background: #0f172a; color: #e2e8f0; }}
        h1 {{ color: #38bdf8; margin-bottom: 4px; }}
        .subtitle {{ color: #94a3b8; margin-bottom: 40px; }}
        .card {{ background: #1e293b; border-radius: 8px; padding: 20px; margin: 16px 0; }}
        .card h3 {{ margin-top: 0; color: #38bdf8; }}
        .status {{ display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 13px; font-weight: 600; }}
        .healthy {{ background: #064e3b; color: #6ee7b7; }}
        .row {{ display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #334155; }}
        .label {{ color: #94a3b8; }}
        a {{ color: #38bdf8; }}
        .footer {{ margin-top: 40px; color: #475569; font-size: 13px; text-align: center; }}
    </style>
</head>
<body>
    <h1>HA 3-Tier Web App</h1>
    <p class="subtitle">Built by Tolu Adekunle</p>

    <div class="card">
        <h3>Infrastructure</h3>
        <div class="row"><span class="label">Architecture</span><span>3-Tier HA (Web / App / DB)</span></div>
        <div class="row"><span class="label">Region</span><span>eu-west-2 (London)</span></div>
        <div class="row"><span class="label">TLS</span><span>ACM + TLS 1.3</span></div>
        <div class="row"><span class="label">WAF</span><span>4 managed rule groups</span></div>
        <div class="row"><span class="label">Deployment</span><span>Packer AMI + Terraform + GitHub Actions</span></div>
    </div>

    <div class="card">
        <h3>Live Status</h3>
        <div class="row"><span class="label">Database</span><span class="status healthy">{db_status}</span></div>
        <div class="row"><span class="label">Items in DB</span><span>{count}</span></div>
        <div class="row"><span class="label">Environment</span><span>{os.environ.get('ENVIRONMENT', 'unknown')}</span></div>
    </div>

    <div class="card">
        <h3>API Endpoints</h3>
        <div class="row"><span class="label">Health</span><a href="/api/health">/api/health</a></div>
        <div class="row"><span class="label">Readiness</span><a href="/api/ready">/api/ready</a></div>
        <div class="row"><span class="label">Liveness</span><a href="/api/live">/api/live</a></div>
        <div class="row"><span class="label">Items</span><a href="/api/items">/api/items</a></div>
    </div>

    <p class="footer">Immutable AMI deployment &middot; Packer &middot; Terraform &middot; HCP Terraform Remote Execution</p>
</body>
</html>""", 200, {"Content-Type": "text/html"}

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


@app.route("/api/stats")
def stats():
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) as total FROM items")
            total = cur.fetchone()["total"]
            cur.execute("SELECT DATE(created_at) as date, COUNT(*) as count FROM items GROUP BY DATE(created_at) ORDER BY date DESC LIMIT 7")
            daily = cur.fetchall()
        conn.close()
        return jsonify({"total_items": total, "daily_breakdown": daily, "tier": "app"})
    except Exception as e:
        logger.error("GET /api/stats failed: %s", e)
        return jsonify({"error": "Database error", "detail": str(e)}), 500

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
