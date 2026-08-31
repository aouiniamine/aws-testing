# VPC + EC2 Architecture

Terraform module that provisions a multi-AZ AWS VPC with public/private subnet tiers and EC2 instances, targeting the **floci** local AWS emulator (`localhost:4566`).

## Overview

```
Internet
   │
   ├──► Internet Gateway ──► Public Route Table ──┬──► Public Subnet AZ-a (10.100.0.0/24)
   │                                               │       └── public-ec2
   │                                               └──► Public Subnet AZ-b (10.100.1.0/24)
   │                                                       └── public-ec2
   │
   └──► NAT Gateway (AZ-a) ──► Private Route Table AZ-a ──► Private Subnet AZ-a (10.100.10.0/24)
                                │                                   └── private-ec2
                                │
                                └──► NAT Gateway (AZ-b) ──► Private Route Table AZ-b ──► Private Subnet AZ-b (10.100.11.0/24)
                                                                              └── private-ec2
```

## Components

### VPC

| Property | Value |
|----------|-------|
| CIDR | `10.100.0.0/16` |
| DNS Hostnames | Enabled |
| DNS Support | Enabled |
| Tag | `${environment}-ec2-vpc` |

### Subnets

| Type | AZ | CIDR | Public IP |
|------|----|------|-----------|
| Public | us-east-1a | `10.100.0.0/24` | Yes |
| Public | us-east-1b | `10.100.1.0/24` | Yes |
| Private | us-east-1a | `10.100.10.0/24` | No |
| Private | us-east-1b | `10.100.11.0/24` | No |

### Gateways & NAT

- **Internet Gateway** -- single IGW attached to VPC; public route table routes `0.0.0.0/0` through it
- **NAT Gateways** -- one per AZ, placed in the corresponding public subnet; each private route table routes `0.0.0.0/0` through its AZ-local NAT
- **Elastic IPs** -- one EIP per NAT gateway, each assigned to the NAT in its public subnet

### Route Tables

| Table | Association | Default Route |
|-------|-------------|---------------|
| Public (shared) | Both public subnets | `0.0.0.0/0` -> IGW |
| Private AZ-a | Private subnet AZ-a | `0.0.0.0/0` -> NAT AZ-a |
| Private AZ-b | Private subnet AZ-b | `0.0.0.0/0` -> NAT AZ-b |

### Security Groups

| Name | Inbound | Outbound | Used By |
|------|---------|----------|---------|
| `allow_all` | All traffic from `0.0.0.0/0` | All traffic | Public EC2 instances |
| `allow_local` | All traffic from `10.100.0.0/16` (VPC only) | All traffic | Private EC2 instances |

### EC2 Instances

| Type | Count | AMI | Size | Subnet | SG |
|------|-------|-----|------|--------|----|
| Public | 2 (1 per AZ) | `ami-0f02b24005e4aec36` | t2.micro | Public | `allow_all` |
| Private | 2 (1 per AZ) | `ami-0f02b24005e4aec36` | t2.micro | Private | `allow_local` |

- Root volume: 8 GB `gp3`, delete on termination
- No SSH key pair configured (commented out)
- No user data or IAM roles

## File Structure

```
0-providers.tf        # AWS provider, required_providers, input variables
1-locals.tf           # AZs, CIDR blocks as local values
2-vpc.tf              # VPC resource
3-igw.tf              # Internet Gateway
4-public-subnet.tf    # 2 public subnets (count = 2 AZs)
5-public-routes.tf    # Public route table + associations
6-nat.tf              # Elastic IP + 2 NAT gateways
7-private-subnet.tf   # 2 private subnets (count = 2 AZs)
8-private-routes.tf   # 2 private route tables + associations
9-ec2.tf              # Security groups + EC2 instances
test.tfvars           # Variable values for local deployment
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| IaC | Terraform >= 1.5.0 |
| Provider | hashicorp/aws ~> 5.0 (locked to 5.100.0) |
| Local Emulator | floci (`floci/floci:1.7.0`) on port 4566 |
| Management UI | floci-ui (`floci/floci-ui:latest`) on port 4500 |
| Runtime | Docker Compose |

## Setup & Deployment

### Prerequisites

- Docker & Docker Compose
- Terraform >= 1.5.0

### 1. Start floci

```bash
docker compose up -d
```

Services:
- **floci** -- `http://localhost:4566` (LocalStack-compatible AWS emulator)
- **floci-ui** -- `http://localhost:4500` (web management UI)

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan -var-file=test.tfvars -out=tfplan
terraform apply tfplan
```

### 3. Verify

```bash
aws --endpoint-url http://localhost:4566 ec2 describe-vpcs --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-subnets --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-instances --region us-east-1
```

### 4. Teardown

```bash
terraform destroy -var-file=test.tfvars -auto-approve
```

## Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `environment` | string | Environment name for resource tagging | `local` |
| `aws_region` | string | AWS region | `us-east-1` |
| `floci_endpoint` | string | floci endpoint URL | `http://localhost:4566` |

## Known Issues

1. **Bug in public-ec2 output** (`9-ec2.tf:86`) -- the `public-ec2` output references `aws_instance.private-ec2[*].id` instead of `aws_instance.public-ec2[*].id`, so both outputs return the same instance IDs.

2. **Unused `floci_endpoint` variable** -- declared but the AWS provider block does not configure `endpoints {}` to use it. The provider relies on default LocalStack endpoint resolution.

4. **No SSH access** -- key pair is commented out; instances cannot be SSH'd into for testing.

5. **Permissive security groups** -- `allow_all` permits all inbound from `0.0.0.0/0`. Acceptable for local sandbox only; not production-safe.
