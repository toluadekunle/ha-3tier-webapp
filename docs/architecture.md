# HA 3-Tier Web App — Architecture

## Infrastructure Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│  AWS Cloud  (ap-south-1)                                                │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  VPC  10.0.0.0/16                                                │  │
│  │                                                                  │  │
│  │   AZ-1a                          AZ-1b                          │  │
│  │  ┌─────────────────────┐    ┌─────────────────────┐             │  │
│  │  │  PUBLIC SUBNET      │    │  PUBLIC SUBNET      │             │  │
│  │  │  10.0.1.0/24        │    │  10.0.2.0/24        │  ◄─ IGW    │  │
│  │  │                     │    │                     │             │  │
│  │  │  [NAT GW]  ┌──────────────────┐  [NAT GW]     │             │  │
│  │  └────────────│                  │───────────────┘             │  │
│  │               │  External ALB    │                              │  │
│  │               │  (internet-facing│                              │  │
│  │               └────────┬─────────┘                              │  │
│  │                        │ HTTP/HTTPS                              │  │
│  │  ┌─────────────────────┼─────────────────────┐                  │  │
│  │  │  PRIVATE APP SUBNET │    PRIVATE APP SUBNET│                  │  │
│  │  │  10.0.11.0/24       │    10.0.12.0/24      │                  │  │
│  │  │                     │                      │                  │  │
│  │  │  ┌──────────────┐   │   ┌──────────────┐  │                  │  │
│  │  │  │ Web EC2 (ASG)│   │   │ Web EC2 (ASG)│  │  ← Web Tier     │  │
│  │  │  │ Nginx        │   │   │ Nginx        │  │    min: 2        │  │
│  │  │  └──────┬───────┘   │   └──────┬───────┘  │    max: 6        │  │
│  │  │         │           │          │           │                  │  │
│  │  │    Internal ALB ────┼──────────┘           │                  │  │
│  │  │         │           │                      │                  │  │
│  │  │  ┌──────▼───────┐   │   ┌──────────────┐  │                  │  │
│  │  │  │ App EC2 (ASG)│   │   │ App EC2 (ASG)│  │  ← App Tier     │  │
│  │  │  │ Flask API    │   │   │ Flask API    │  │    min: 2        │  │
│  │  │  └──────┬───────┘   │   └──────┬───────┘  │    max: 6        │  │
│  │  └─────────┼───────────┼──────────┼───────────┘                  │  │
│  │            │           │          │                               │  │
│  │  ┌─────────┼───────────┼──────────┼───────────┐                  │  │
│  │  │  PRIVATE DB SUBNET  │    PRIVATE DB SUBNET  │                  │  │
│  │  │  10.0.21.0/24       │    10.0.22.0/24       │                  │  │
│  │  │                     │                       │                  │  │
│  │  │  ┌──────────────────▼───────────────────┐  │  ← DB Tier      │  │
│  │  │  │  RDS MySQL 8.0  (Multi-AZ)           │  │                  │  │
│  │  │  │  Primary (AZ-1a) ↔ Standby (AZ-1b)  │  │                  │  │
│  │  │  └──────────────────────────────────────┘  │                  │  │
│  │  └────────────────────────────────────────────┘                  │  │
│  │                                                                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  Supporting Services                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  Route 53    │  │  CloudWatch  │  │  Secrets Mgr │  │  S3 Logs  │  │
│  │  (DNS)       │  │  (Metrics)   │  │  (DB Creds)  │  │  (ALB)    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └───────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

```
User Request
    │
    ▼
Route 53 (DNS)  →  HTTPS/HTTP
    │
    ▼
External ALB  (public subnets, AZ-1a + AZ-1b)
    │  round-robin across healthy targets
    ▼
Web Tier EC2 (Nginx)  ←── Auto Scaling Group (min 2, max 6)
    │  reverse proxy
    ▼
Internal ALB  (private subnets)
    │
    ▼
App Tier EC2 (Flask API)  ←── Auto Scaling Group (min 2, max 6)
    │  pymysql + Secrets Manager
    ▼
RDS MySQL 8.0  (Multi-AZ: Primary + Standby)
```

## Subnet Layout

| Subnet | CIDR | Purpose |
|--------|------|---------|
| public-1a | 10.0.1.0/24 | ALB, NAT GW |
| public-1b | 10.0.2.0/24 | ALB, NAT GW |
| app-1a | 10.0.11.0/24 | Web + App EC2 |
| app-1b | 10.0.12.0/24 | Web + App EC2 |
| db-1a | 10.0.21.0/24 | RDS Primary |
| db-1b | 10.0.22.0/24 | RDS Standby |

## Security Group Rules

| SG | Inbound From | Port |
|----|--------------|------|
| ALB SG | Internet (0.0.0.0/0) | 80, 443 |
| Web SG | ALB SG only | 80 |
| App SG | Web SG only | 5000 |
| RDS SG | App SG only | 3306 |
