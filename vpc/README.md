# VPC Implementation — floci (LocalStack)

This module provisions a complete AWS VPC using Terraform and deploys it against a local
[floci](https://floci.io) (LocalStack-compatible) instance running on `localhost:4566`.
The resulting topology mirrors a typical production-style three-tier networking layout,
but collapsed into two public and two private subnets across two availability zones.

> Visual reference: [preview.html](./preview.html)

---

## Architecture Overview

```
                    ┌─────────────────────────────── Internet ───────────────────────────────┐
                    │                                                                        │
              (egress in)                                                              (egress in)
                    └───────────────┐                                                        │
                                    ▼                                                        ▼
                          ┌─────────────────────┐                                 ┌─────────────────────┐
                          │  Internet Gateway    │                                 │  NAT Gateway         │
                          │  aws_internet_gateway│                                 │  aws_nat_gateway     │
                          └──────────┬──────────┘                                 └──────────┬──────────┘
                                     │ 0.0.0.0/0 -> IGW                              ▲       │ 0.0.0.0/0 -> NAT
                                     │                                            EIP       │
                    ┌────────────────┷────────────────┐                        (elastic IP)  │
                    │        PUBLIC ROUTE TABLE        │                                    │
                    │   (aws_route_table.public)      │                                    │
                    └───────────┬────────────┬────────┘                           ┌──────────┴────────────┐
                                │            │                                   │   PRIVATE ROUTE TABLE   │
                    ┌───────────▼──┐      ┌───▼──────────┐                      │ (aws_route_table.private)│
                    │ public_zone1 │      │ public_zone2 │                      └───────────┬────────┬─────┘
                    │ 10.10.1.0/24 │      │ 10.10.2.0/24 │                                  │        │
                    │   us-east-1a │      │   us-east-1b │                      ┌───────────▼──┐   ┌──▼────────────┐
                    └──────────────┘      └──────────────┘                      │ private_zone1 │   │ private_zone2 │
                                                                                │ 10.10.11.0/24│   │ 10.10.12.0/24 │
                                                                                │   us-east-1a │   │   us-east-1b  │
                                                                                └──────────────┘   └───────────────┘
                                                          PUBLIC ─────────────────────────────── PRIVATE
```

---

## Resource Breakdown

All resources are defined in ordered, self-documenting `.tf` files within `vpc/`.

| File                    | Resource(s)                                                        | Purpose                                                       |
| ----------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------- |
| `0-providers.tf`        | `aws` + `archive` providers, `environment`/`aws_region`/`floci_endpoint` vars | Terraform/provider setup, variable declarations, local backend |
| `1-vpc.tf`              | `aws_vpc.main` (CIDR `10.10.0.0/16`)                               | The VPC itself, DNS hostnames + support enabled               |
| `2-igw.tf`              | `aws_internet_gateway.main`                                        | Internet gateway for all public egress/ingress                |
| `3-public-subnets.tf`   | `aws_subnet.public_zone1` (`10.10.1.0/24`), `public_zone2` (`10.10.2.0/24`) | Two public subnets, one per AZ, auto-assign public IPs        |
| `4-public-routes.tf`    | `aws_route_table.public` + 2 associations                          | Default route `0.0.0.0/0 → IGW`, tied to both public subnets  |
| `5-nat.tf`              | `aws_eip.nat`, `aws_nat_gateway.nat`                               | Elastic IP + NAT gateway (sits in `public_zone1`)             |
| `6-private-subnets.tf`  | `aws_subnet.private_zone1` (`10.10.11.0/24`), `private_zone2` (`10.10.12.0/24`) | Two private subnets, one per AZ, no public IPs                |
| `7-private-routes.tf`   | `aws_route_table.private` + 2 associations                         | Default route `0.0.0.0/0 → NAT`, tied to both private subnets |

### CIDR Layout

| Scope         | CIDR Block  | Subnets                                  |
| ------------- | ----------- | ---------------------------------------- |
| VPC           | `10.10.0.0/16` |                                          |
| Public AZ a   | `10.10.1.0/24` | `public_zone1`                           |
| Public AZ b   | `10.10.2.0/24` | `public_zone2`                           |
| Private AZ a  | `10.10.11.0/24`| `private_zone1`                          |
| Private AZ b  | `10.10.12.0/24`| `private_zone2`                          |

---

## Networking Behavior

- **Public subnets** (`10.10.1.0/24`, `10.10.2.0/24`)
  - `map_public_ip_on_launch = true` → instances get public IPs.
  - Routed via the **public route table** whose `0.0.0.0/0` route points to the **Internet Gateway**.
  - Typical use: NAT gateways, load balancers, bastion hosts.

- **Private subnets** (`10.10.11.0/24`, `10.10.12.0/24`)
  - No public IPs; not directly reachable from the internet.
  - Routed via the **private route table** whose `0.0.0.0/0` route points to the **NAT Gateway**.
  - This gives private resources outbound internet access while keeping them isolated from inbound traffic.
  - Typical use: application/DB servers, workers, internal services.

- **NAT Gateway** lives inside `public_zone1`, backed by an **Elastic IP**, so private resources can reach the internet while remaining unreachable from it.

All four subnets span two availability zones (`us-east-1a` / `us-east-1b`) for AZ-level redundancy.

---

## Local Runtime Setup

This project is designed to run against an owned LocalStack fork distributed as the
`floci/floci` Docker image. The UI is served separately via `floci/floci-ui`.

### 1. Start the local AWS stack

```bash
docker compose up -d
```

- `floci` — LocalStack-compatible core, exposed on **`localhost:4566`**
- `floci-ui` — Web UI, exposed on **`localhost:4500`**
  - `FLOCI_ENDPOINT=http://floci:4566` (internal Docker hostname)

### 2. Configure / validate the Terraform provider

`0-providers.tf` already points the AWS provider at the local endpoint using
hardcoded sandbox credentials and validation skips:

```hcl
provider "aws" {
  region                      = var.aws_region
  access_key                  = "floci"
  secret_key                  = "floci"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}
```

> Note: the `aws` provider targeting `localhost:4566` in this file does **not**
> currently set `endpoints`/`endpoint` — if a run fails to reach LocalStack,
> add an AWS endpoints override (see "Endpoint wiring" below).

### 3. Apply the stack

```bash
terraform init
terraform plan -var-file=test.tfvars -out=tfplan
terraform apply tfplan
```

`test.tfvars` provides:

```hcl
aws_region     = "us-east-1"
floci_endpoint = "http://localhost:4566"
environment    = "local"
```

### Endpoint wiring

The `floci_endpoint` variable is declared in `0-providers.tf` but the active provider
block does not consume it. To strictly target LocalStack through Terraform, add an
endpoint override, e.g.:

```hcl
provider "aws" {
  # ...existing settings...
  access_key = "test"
  secret_key = "test"
  endpoints {
    ec2 = var.floci_endpoint
  }
}
```

---

## Verify the Deployment

After applying, confirm resources appeared in floci:

```bash
# VPC / subnets / gateways via AWS CLI pointed at LocalStack
aws --endpoint-url http://localhost:4566 ec2 describe-vpcs --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-subnets --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-internet-gateways --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-nat-gateways --region us-east-1
aws --endpoint-url http://localhost:4566 ec2 describe-route-tables --region us-east-1

# Or browse the web UI
open http://localhost:4500
```

---

## Teardown

```bash
terraform destroy -var-file=test.tfvars -auto-approve
```

---

## Caveats / Notes

- This is a **local/sandbox** configuration: credentials are dummy values and all AWS
  API calls are served by floci, not real AWS.
- A single NAT gateway + single EIP is provisioned. For production multi-AZ resilience
  you would typically add one NAT per AZ (one in each public subnet).
- The `archive` provider is declared but unused by the current VPC resources; it exists
  for downstream modules in the broader floci workspace (e.g. Lambda packaging).
- No security groups are declared yet; they can be added per-subnet or per-service.
