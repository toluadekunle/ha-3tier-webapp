# Highly Available 3-Tier Web Application on AWS

AWS infrastructure implementing a highly available, auto-scaling 3-tier web application across multiple Availability Zones. Built with Terraform, managed via HCP Terraform Remote execution, validated with Ansible, and deployed through GitHub Actions CI/CD.

**Live:** https://app.cybserve.co.uk

> Originally forked from [swanand18/ha-3tier-webapp](https://github.com/swanand18/ha-3tier-webapp). Substantially rearchitected with 13 production hardening changes, 14 error fixes, HTTPS/TLS 1.3, WAFv2, VPC interface endpoints, readiness health checks, conditional IAM, SSM session logging, target tracking scaling, Nginx DNS re-resolution, and CI/CD via GitHub Actions.

---

## Author

**Tolu Adekunle**

---

## Architecture

```
Internet
    |
[WAFv2] -- CommonRuleSet, KnownBadInputs, IpReputationList, RateLimit 2000/5min
    |
[External ALB] -- HTTPS 443 (ACM, TLS 1.3) | HTTP 80 -> 301 redirect
    |                 SG: ext-alb-sg (80/443 from 0.0.0.0/0)
    |
[Web Tier] -- 2x t3.micro, Nginx reverse proxy, private app subnets
    |            SG: web-sg (80 from ext-alb-sg only)
    |            No SSH | No Secrets Manager access | SSM only
    |            Nginx resolver 169.254.169.253 valid=30s
    |
[Internal ALB] -- Private app subnets, own SG
    |                SG: int-alb-sg (80 from web-sg only)
    |
[App Tier] -- 2x t3.small, Flask/Gunicorn port 5000, private app subnets
    |           SG: app-sg (5000 from int-alb-sg only)
    |           Health: /api/ready -> 503 when DB unreachable
    |           Health: /api/live -> 200 if process alive
    |
[RDS MySQL 8.0] -- Multi-AZ, encrypted, gp3, private DB subnets
                    SG: rds-sg (3306 from app-sg only)
                    No outbound route | No public access
```

---

## Infrastructure Summary

| Component | Configuration |
|-----------|--------------|
| Region | eu-west-2 (London) |
| Domain | app.cybserve.co.uk (ACM certificate, DNS validated via GoDaddy) |
| TLS | TLS 1.3 (ELBSecurityPolicy-TLS13-1-2-2021-06), HTTP to HTTPS redirect |
| WAF | WAFv2: CommonRuleSet, KnownBadInputs, IpReputationList, RateLimit |
| VPC | 10.0.0.0/16, 6 subnets across 2 AZs |
| Public subnets | 10.0.1.0/24 (2a), 10.0.2.0/24 (2b) -- External ALB and NAT Gateways only |
| Private app subnets | 10.0.11.0/24 (2a), 10.0.12.0/24 (2b) -- Web ASG, App ASG, Internal ALB, VPC endpoints |
| Private DB subnets | 10.0.21.0/24 (2a), 10.0.22.0/24 (2b) -- RDS only, no outbound route |
| Compute | Web: 2x t3.micro (Nginx), App: 2x t3.small (Flask/Gunicorn) |
| Database | RDS MySQL 8.0, db.t3.micro, Multi-AZ, encrypted, gp3, 7-day backup |
| Scaling | TargetTrackingScaling at 60% CPU, AWS-managed alarms |
| State | HCP Terraform Remote execution |
| CI/CD | GitHub Actions: plan on PR, apply on merge to main |
| Total resources | 75 Terraform-managed |

---

## Security

| Control | Implementation |
|---------|---------------|
| TLS | ACM certificate, TLS 1.3 at ALB, HTTP redirected to HTTPS |
| WAF | 4 AWS managed rule groups on external ALB |
| SSH | Removed from all security groups. SSM Session Manager only |
| SSM logging | Session commands logged to CloudWatch Logs, 7-day retention |
| Secrets | Scoped IAM to exact secret ARN. Web tier has no secrets policy (conditional boolean) |
| Security groups | 6 SGs with SG-to-SG references. Each tier only accepts traffic from the tier above |
| IAM | Per-tier instance profiles. Conditional secrets access. Zero Resource:* policies |
| IMDSv2 | Required on all instances (http_tokens = required) |
| VPC endpoints | 5 interface endpoints (SSM, SSMMessages, EC2Messages, Secrets Manager, CloudWatch Logs) |
| Endpoint SG | vpce-sg: HTTPS 443 from VPC CIDR only |
| VPC Flow Logs | All traffic logged to CloudWatch. IAM scoped to exact log group ARN |
| RDS | Private subnets only, no public access, encrypted storage, no outbound route |
| EBS | Encrypted gp3 on all instances |

---

## VPC Interface Endpoints

Management plane traffic stays inside the VPC via PrivateLink:

| Endpoint | Service | Purpose |
|----------|---------|---------|
| vpce-ssm | com.amazonaws.eu-west-2.ssm | Session Manager control |
| vpce-ssmmessages | com.amazonaws.eu-west-2.ssmmessages | Session Manager data channel |
| vpce-ec2messages | com.amazonaws.eu-west-2.ec2messages | SSM agent communication |
| vpce-secrets | com.amazonaws.eu-west-2.secretsmanager | Database credential retrieval |
| vpce-logs | com.amazonaws.eu-west-2.logs | CloudWatch log delivery |

All endpoints have private DNS enabled and share a dedicated security group allowing HTTPS from the VPC CIDR.

---

## Health Checks

| Endpoint | Behaviour | Used by |
|----------|-----------|---------|
| /health | Returns 200 from Nginx directly (web tier alive) | External ALB web target group |
| /api/ready | Returns 200 when DB connected, 503 when DB unreachable | Internal ALB app target group |
| /api/live | Returns 200 if Flask process is alive | Liveness check |
| /api/health | Returns full status with DB connectivity, environment, timestamp | Diagnostic |

---

## CI/CD

GitHub Actions workflows triggered by repository events:

| Workflow | Trigger | Steps |
|----------|---------|-------|
| Terraform Plan | Pull request to main (terraform/** paths) | Checkout, Setup Terraform, fmt check, init, validate, plan, PR comment |
| Terraform Apply | Push to main (terraform/** paths) | Checkout, Setup Terraform, init, apply |

Authentication via HCP Terraform API token stored as GitHub Actions secret. AWS credentials remain in the HCP Terraform workspace, never in GitHub.

---

## Terraform Modules

| Module | Resources |
|--------|-----------|
| vpc | VPC, 6 subnets, IGW, 2 NAT Gateways, route tables, flow logs |
| security | 6 SGs: ext-alb, int-alb, web, app, rds, vpce |
| alb | External ALB (HTTPS + redirect), Internal ALB, target groups, S3 logs |
| ec2-asg | Launch template, ASG, TargetTracking scaling, IAM (reused for web and app) |
| rds | RDS MySQL Multi-AZ, parameter group, subnet group |
| Root | WAF, ACM, Secrets Manager, SSM logging, VPC endpoints |

---

## Deployment

### Prerequisites

- Terraform >= 1.5
- AWS CLI configured with profile
- HCP Terraform account with workspace configured
- GoDaddy DNS (or equivalent) for domain validation

### Deploy

```bash
export AWS_PROFILE=ha3
cd terraform
terraform init
terraform apply
```

### Test

```bash
curl -I http://app.cybserve.co.uk
curl -sk https://app.cybserve.co.uk/api/health
curl -sk https://app.cybserve.co.uk/api/ready
curl -sk https://app.cybserve.co.uk/api/live
```

### Destroy

```bash
cd terraform
terraform destroy -auto-approve
```

---

## Build History

14 errors were diagnosed and fixed across OS, application, network, security, and database layers:

**Pre-deploy errors:** Wrong shell environment, root credentials in config, script path mismatch in remote execution, Ansible gather_facts conflict, HCL semicolon syntax errors, template variable case mismatch, remote execution path failure, workspace variable miscategorisation.

**Post-deploy errors:** curl-minimal package conflict on AL2023, mysql package renamed to mariadb105 on AL2023, app security group blocked ALB health check packets, RDS endpoint included port in hostname string, Ansible smoke test targeted non-existent root route.

**Post-hardening error:** 504 Nginx DNS caching after internal ALB subnet move. Nginx cached stale IPs at startup, resolved with resolver directive and variable proxy_pass.

---

## Production Hardening (13 changes)

1. Internal ALB moved from public to private subnets
2. SSH removed from all security groups, SSM Session Manager only
3. Secrets Manager IAM policy scoped to exact secret ARN
4. Separate security group for internal ALB (int-alb-sg)
5. VPC flow logs IAM policy scoped to exact log group ARN
6. HTTPS with ACM certificate, TLS 1.3 policy, HTTP-to-HTTPS redirect
7. WAFv2 with 4 managed rule groups attached to external ALB
8. Readiness/liveness health check split (/api/ready returns 503 when DB unreachable)
9. Web tier Secrets Manager access disabled via conditional boolean
10. App security group tightened to Internal ALB SG only (Web SG removed)
11. TargetTrackingScaling at 60% CPU replacing SimpleScaling with manual alarms
12. Nginx resolver directive (169.254.169.253 valid=30s) with variable proxy_pass
13. SSM session logging to CloudWatch Logs with 7-day retention

Plus: 5 VPC interface endpoints and CI/CD via GitHub Actions.

---

## Estimated Cost (eu-west-2)

| Resource | Approximate monthly cost |
|----------|------------------------|
| EC2 Web Tier (2x t3.micro) | ~$17 |
| EC2 App Tier (2x t3.small) | ~$34 |
| RDS Multi-AZ (db.t3.micro) | ~$29 |
| NAT Gateway x2 | ~$65 |
| ALB x2 | ~$32 |
| VPC Endpoints x5 | ~$52 |
| Total | ~$229/month |

---

## License

No licence file in the original repository. This fork is maintained independently. Attribution to the original repository is preserved above.
