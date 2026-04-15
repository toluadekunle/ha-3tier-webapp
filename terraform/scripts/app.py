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
