# 🌐 Highly Available 3-Tier Web Application on AWS

> **Production-style AWS infrastructure project implementing a highly available, auto-scaling 3-tier web application across multiple Availability Zones using Terraform, Ansible, GitHub Actions, and AWS managed services.**

---

## 👨‍💻 Author

**Swanand Awatade**
Cloud / DevOps / Infrastructure Engineer

---

## 🧰 Tech Stack

* **Infrastructure as Code:** Terraform
* **Cloud Platform:** AWS
* **Networking:** VPC, Public/Private Subnets, NAT Gateway, Route Tables
* **Load Balancing:** External ALB, Internal ALB
* **Compute:** EC2 Auto Scaling Groups
* **Database:** Amazon RDS MySQL (Multi-AZ)
* **Security:** Security Groups, IAM, Secrets Manager, IMDSv2
* **Observability:** CloudWatch, VPC Flow Logs
* **Automation:** Ansible
* **CI/CD:** GitHub Actions
* **Web Tier:** Nginx
* **App Tier:** Flask + Gunicorn

---

## 📐 Architecture

![HA 3-Tier Architecture](docs/images/architecture.png)

### 🔍 High-Level Flow

1. **Users** access the application via the internet
2. Traffic enters through the **External Application Load Balancer**
3. Requests are routed to the **Web Tier (Nginx)** running in an **Auto Scaling Group**
4. The Web Tier forwards traffic to the **Internal ALB**
5. Requests are passed to the **Application Tier (Flask + Gunicorn)** running in a separate **Auto Scaling Group**
6. The App Tier securely connects to **Amazon RDS MySQL (Multi-AZ)** in private DB subnets
7. Infrastructure is provisioned using **Terraform** and validated using **Ansible**
8. Deployment and validation are automated using **GitHub Actions**

---

## 🏗 Architecture Summary

This project implements a **Highly Available 3-Tier Architecture** across **2 Availability Zones** with proper **network segmentation**, **security isolation**, **load balancing**, and **auto scaling**.

### Core Design Principles

* **High Availability**
* **Fault Tolerance**
* **Network Isolation**
* **Least Privilege Security**
* **Infrastructure as Code**
* **Production-style Deployment Pattern**

---

## 📁 Project Structure

```bash
ha-3tier-webapp/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/
│       ├── security/
│       ├── alb/
│       ├── ec2-asg/
│       └── rds/
├── scripts/
│   ├── web_userdata.sh
│   └── app_userdata.sh
├── ansible/
│   └── validate-deployment.yml
├── .github/workflows/
│   └── deploy-infra.yml
├── docs/
│   ├── architecture.md
│   └── images/
│       └── architecture.png
└── README.md
```

---

## 🚀 Features

* ✅ Highly Available 3-Tier Architecture
* ✅ Public + Private subnet segregation
* ✅ External and Internal Application Load Balancers
* ✅ Web Tier and App Tier in separate Auto Scaling Groups
* ✅ RDS MySQL Multi-AZ deployment
* ✅ Secrets Manager for secure DB password handling
* ✅ CloudWatch logs, alarms, and VPC Flow Logs
* ✅ Terraform-based infrastructure provisioning
* ✅ Ansible-based deployment validation
* ✅ GitHub Actions for infra CI/CD

---

## 🌍 Architecture Components

### 1️⃣ Networking Layer

* Custom **VPC**
* **2 Public Subnets**
* **2 Private App Subnets**
* **2 Private DB Subnets**
* **Internet Gateway**
* **NAT Gateways**
* **Route Tables**
* **VPC Flow Logs**

### 2️⃣ Web Tier

* Nginx reverse proxy
* Deployed in private compute subnets
* Connected behind an **External ALB**
* Auto Scaling enabled across AZs

### 3️⃣ Application Tier

* Flask application served using Gunicorn
* Connected behind an **Internal ALB**
* Runs in private subnets only
* Auto Scaling enabled

### 4️⃣ Database Tier

* Amazon RDS MySQL
* Multi-AZ enabled
* Deployed in private DB subnets
* No public access

---

## ⚙️ Prerequisites

Install the following tools:

* Terraform `>= 1.5`
* AWS CLI
* Ansible
* Git

### Verify Installation

```bash
terraform version
aws --version
ansible --version
git --version
```

---

## ☁️ AWS Configuration

Configure your AWS credentials:

```bash
aws configure
```

Enter:

* AWS Access Key ID
* AWS Secret Access Key
* Region: `ap-south-1`
* Output format: `json`

---

## 🚀 Deployment Guide

### 1. Clone the Repository

```bash
git clone https://github.com/swanand18/ha-3tier-webapp.git
cd ha-3tier-webapp
```

---

### 2. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Update values in:

```bash
terraform.tfvars
```

For example:

* AWS region
* Key pair name
* instance sizes
* DB settings
* domain / certificate values (if used)

---

### 3. Initialize Terraform

```bash
terraform init
```

---

### 4. Preview Changes

```bash
terraform plan
```

---

### 5. Deploy Infrastructure

```bash
terraform apply
```

> ⏱ Expected deployment time: **10–20 minutes**
> (RDS Multi-AZ and NAT Gateways usually take the longest)

---

## 🔍 Validate Deployment

### Get ALB URL

```bash
terraform output app_url
```

or

```bash
terraform output -raw alb_dns_name
```

---

### Run Validation Playbook

```bash
ansible-playbook -i localhost, ansible/validate-deployment.yml \
  -e "alb_dns=$(terraform output -raw alb_dns_name)"
```

---

## 🌐 Test the Application

```bash
ALB="http://$(terraform output -raw alb_dns_name)"

curl $ALB/health
curl $ALB/api/health
curl $ALB/api/items
```

### Create a Sample Item

```bash
curl -X POST $ALB/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"sample-item","description":"hello from HA webapp"}'
```

---

## 🔧 Terraform Modules

### `modules/vpc`

Responsible for:

* VPC creation
* Public / Private subnet design
* Internet Gateway
* NAT Gateways
* Route Tables
* Flow Logs

---

### `modules/security`

Responsible for:

* ALB Security Group
* Web Tier Security Group
* App Tier Security Group
* RDS Security Group

Implements **least privilege** access.

---

### `modules/alb`

Responsible for:

* External ALB
* Internal ALB
* Target Groups
* Listener Rules
* HTTP/HTTPS handling

---

### `modules/ec2-asg`

Responsible for:

* Launch Templates
* Auto Scaling Groups
* Scaling Policies
* CloudWatch Alarms
* Rolling Instance Refresh

---

### `modules/rds`

Responsible for:

* RDS MySQL deployment
* Multi-AZ setup
* DB subnet group
* Parameter group
* Backup retention
* CloudWatch integration

---

## 🔐 Security Highlights

| Control           | Implementation             |
| ----------------- | -------------------------- |
| DB Credentials    | AWS Secrets Manager        |
| EC2 Metadata      | IMDSv2 enforced            |
| Storage           | Encrypted EBS volumes      |
| Database Exposure | Private only               |
| Access Control    | Least privilege IAM        |
| SSH               | Key-based authentication   |
| Logs              | VPC Flow Logs + CloudWatch |
| TLS               | Ready for HTTPS via ALB    |

---

## 📊 Auto Scaling Configuration

| Tier     | Min | Max | Scale Up  | Scale Down |
| -------- | --- | --- | --------- | ---------- |
| Web Tier | 2   | 6   | CPU > 70% | CPU < 20%  |
| App Tier | 2   | 6   | CPU > 70% | CPU < 20%  |

---

## 📈 Monitoring & Observability

This project includes operational visibility using:

* **CloudWatch Logs**
* **CloudWatch Alarms**
* **VPC Flow Logs**
* **ALB health checks**
* **Auto Scaling health policies**

This improves:

* reliability
* troubleshooting
* deployment confidence
* operational readiness

---

## 💰 Estimated AWS Cost (ap-south-1)

| Resource            | Approx Monthly Cost |
| ------------------- | ------------------- |
| EC2 Web Tier        | ~$15                |
| EC2 App Tier        | ~$30                |
| RDS Multi-AZ        | ~$30                |
| NAT Gateway x2      | ~$65                |
| ALB x2              | ~$32                |
| **Estimated Total** | **~$172/month**     |

> 💡 For testing/dev, you can reduce cost using smaller instances and fewer HA components.

---

## 🗑️ Destroy Infrastructure

To avoid AWS charges:

```bash
cd terraform
terraform destroy
```

---

## 🎯 Key Outcomes

* ✅ Built a **production-style AWS 3-tier architecture**
* ✅ Implemented **multi-AZ high availability**
* ✅ Designed **secure private subnet architecture**
* ✅ Used **Terraform for repeatable IaC deployment**
* ✅ Automated validation with **Ansible**
* ✅ Enabled **scalability and observability**
* ✅ Used **managed AWS services** following good cloud design principles

---

## 🔮 Future Improvements

* Add **WAF** for edge protection
* Add **CloudFront** for CDN and caching
* Add **ACM + HTTPS enforcement**
* Add **EKS / ECS migration path**
* Add **RDS Proxy** for better DB connection handling
* Add **Prometheus + Grafana** monitoring
* Add **Blue/Green deployment** support

---

## ⭐ Support

If you found this project useful, consider giving it a **star** on GitHub.

---
