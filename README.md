# HA 3-Tier Web App on AWS EC2

> **Stack:** Terraform · AWS VPC · ALB · EC2 ASG · RDS MySQL · Secrets Manager · CloudWatch
> **Author:** Swanand Awatade | Binary Hat Pvt. Ltd.
> **Timeline:** Aug 2022 – Dec 2022

---

## 📐 Architecture Overview

A fully **Highly Available**, **Auto-Scaling**, **3-tier** web application on AWS across **2 Availability Zones**.

```
Internet → Route 53 → External ALB → Web Tier (Nginx, ASG)
                                          ↓
                                    Internal ALB
                                          ↓
                                   App Tier (Flask, ASG)
                                          ↓
                                  RDS MySQL (Multi-AZ)
```

See `docs/architecture.md` for the full ASCII diagram.

---

## 📁 Project Structure

```
ha-3tier-webapp/
├── terraform/
│   ├── main.tf                    # Root module — wires everything together
│   ├── variables.tf               # All input variables
│   ├── outputs.tf                 # Key outputs (ALB DNS, RDS endpoint, etc.)
│   ├── terraform.tfvars.example   # Fill this in → rename to terraform.tfvars
│   └── modules/
│       ├── vpc/                   # VPC, subnets, IGW, NAT GW, route tables, flow logs
│       ├── security/              # All 4 security groups (ALB, Web, App, RDS)
│       ├── alb/                   # External ALB + Internal ALB + target groups
│       ├── ec2-asg/               # Launch Template + ASG + scaling policies + CloudWatch alarms
│       └── rds/                   # RDS MySQL Multi-AZ + parameter group + subnet group
├── scripts/
│   ├── web_userdata.sh            # Web EC2 bootstrap: Nginx + CloudWatch agent
│   └── app_userdata.sh            # App EC2 bootstrap: Flask API + DB schema init
├── ansible/
│   └── validate-deployment.yml   # Smoke tests run post-deploy
├── .github/workflows/
│   └── deploy-infra.yml          # GitHub Actions: plan → apply → validate
├── docs/
│   └── architecture.md           # Full architecture diagram
└── README.md
```

---

## 🚀 Quickstart

### Prerequisites
```bash
# Install tools
brew install terraform awscli ansible   # macOS
# or
sudo apt install terraform awscli ansible  # Ubuntu

# Verify
terraform version   # >= 1.5.0
aws --version
ansible --version

# Configure AWS credentials
aws configure
# Enter: Access Key, Secret Key, Region (ap-south-1), output format (json)
```

### 1 — Clone & Configure
```bash
git clone https://github.com/swanand18/ha-3tier-webapp.git
cd ha-3tier-webapp/terraform

cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # Set key_name to your EC2 Key Pair name
```

### 2 — Create EC2 Key Pair (if you don't have one)
```bash
aws ec2 create-key-pair \
    --key-name ha-webapp-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/ha-webapp-key.pem
chmod 400 ~/.ssh/ha-webapp-key.pem
```

### 3 — Deploy Infrastructure
```bash
cd terraform

# Initialize (downloads providers & modules)
terraform init

# Preview what will be created
terraform plan

# Deploy (takes ~10–15 minutes for RDS Multi-AZ)
terraform apply
```

### 4 — Get the ALB URL
```bash
terraform output app_url
# → http://ha-webapp-prod-ext-alb-XXXXXX.ap-south-1.elb.amazonaws.com
```

### 5 — Validate Deployment
```bash
# Run Ansible smoke tests
ALB_DNS=$(terraform output -raw alb_dns_name)
ansible-playbook -i localhost, ansible/validate-deployment.yml \
    -e "alb_dns=$ALB_DNS"
```

### 6 — Test the API
```bash
ALB="http://$(terraform output -raw alb_dns_name)"

# Health check
curl $ALB/health

# App health (checks DB connectivity)
curl $ALB/api/health

# List items
curl $ALB/api/items

# Create an item
curl -X POST $ALB/api/items \
    -H "Content-Type: application/json" \
    -d '{"name":"test-item","description":"my first item"}'
```

---

## 🔧 Terraform Modules

### `modules/vpc`
Creates the full network foundation:
- VPC with DNS enabled
- 2 public subnets (ALB, NAT GW)
- 2 private app subnets (EC2)
- 2 private DB subnets (RDS)
- Internet Gateway
- 2 NAT Gateways (one per AZ — true HA)
- Route tables for each tier
- VPC Flow Logs → CloudWatch

### `modules/security`
4 tightly scoped security groups following least-privilege:
- **ALB SG** — allows internet → 80/443
- **Web SG** — allows ALB SG → 80 only
- **App SG** — allows Web SG → 5000 only
- **RDS SG** — allows App SG → 3306 only

### `modules/alb`
- **External ALB** — internet-facing, public subnets
- **Internal ALB** — web-to-app, private subnets
- HTTP → HTTPS redirect when ACM cert is provided
- Access logs → S3

### `modules/ec2-asg`
Reusable module used for both Web and App tiers:
- Launch Template with IMDSv2 enforced
- Encrypted EBS volumes (gp3)
- Auto Scaling Group spanning 2 AZs
- CPU-based scale-up (>70%) and scale-down (<20%) policies
- Instance refresh with rolling updates (50% min healthy)
- IAM role: SSM, CloudWatch, Secrets Manager access

### `modules/rds`
- MySQL 8.0 Multi-AZ (Primary + Standby)
- Encrypted at rest (gp3 storage)
- Automated backups (7-day retention)
- Slow query logging → CloudWatch
- Password managed by Secrets Manager

---

## 🔐 Security Highlights

| Feature | Implementation |
|---------|----------------|
| DB Password | AWS Secrets Manager (never in code) |
| EC2 metadata | IMDSv2 enforced on all instances |
| EBS volumes | AES-256 encryption enabled |
| Network | RDS in private subnet, no public access |
| IAM | Least-privilege roles per tier |
| SSH | Key-based only, no password auth |
| ALB | HTTPS with TLS 1.3 policy |
| VPC | Flow logs enabled |

---

## 📊 Auto Scaling

| Tier | Min | Max | Scale Up | Scale Down |
|------|-----|-----|----------|------------|
| Web  | 2   | 6   | CPU > 70% | CPU < 20% |
| App  | 2   | 6   | CPU > 70% | CPU < 20% |

---

## 💰 Estimated Monthly Cost (ap-south-1)

| Resource | Type | ~Cost/month |
|----------|------|-------------|
| Web EC2 x2 | t3.micro | ~$15 |
| App EC2 x2 | t3.small | ~$30 |
| RDS MySQL Multi-AZ | db.t3.micro | ~$30 |
| NAT Gateway x2 | — | ~$65 |
| ALB x2 | — | ~$32 |
| **Total** | | **~$172/mo** |

*Use `t3.micro` for all instances in dev/staging to reduce costs.*

---

## 🗑️ Destroy Infrastructure

```bash
cd terraform
terraform destroy
# Confirm with: yes
```

---

## 🛠 Technologies Used

| Tool | Purpose |
|------|---------|
| Terraform 1.7 | Infrastructure as Code |
| AWS VPC | Network isolation |
| AWS ALB | Load balancing (external + internal) |
| AWS EC2 ASG | Auto-scaling compute |
| AWS RDS | Managed MySQL Multi-AZ |
| AWS Secrets Manager | Secure credential storage |
| AWS CloudWatch | Metrics, logs, alarms |
| AWS Route 53 | DNS (optional) |
| Nginx | Web tier reverse proxy |
| Flask + Gunicorn | App tier API |
| Ansible | Deployment validation |
| GitHub Actions | CI/CD for infrastructure |

---

## 📈 Objectives Achieved

- ✅ VPC with 3-tier subnet isolation (public / private-app / private-db)
- ✅ EC2 instances in private subnets — no direct internet exposure
- ✅ ALB distributes traffic across multiple AZs
- ✅ Auto Scaling responds to CPU load automatically
- ✅ RDS Multi-AZ — automatic failover in under 60 seconds
- ✅ DB credentials never hardcoded — Secrets Manager only
- ✅ IMDSv2 enforced on all EC2 instances
- ✅ VPC Flow Logs + CloudWatch for full observability
- ✅ One-command deploy via `terraform apply`
