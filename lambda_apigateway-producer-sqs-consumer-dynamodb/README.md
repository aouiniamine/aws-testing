# API Gateway → Producer → SQS → Consumer → DynamoDB

An asynchronous, decoupled event-processing pipeline for orders, deployed as **Infrastructure-as-Code with Terraform** and run against a local [floci](https://floci.io) (LocalStack-compatible) instance on `localhost:4566`. It is a clean-architecture reference: each responsibility lives in its own Terraform module and each step in the flow is only coupled to the message contract, not to its neighbours.

> Visual reference: [preview.html](./preview.html) — open it in a browser (or `open preview.html`).

---

## Architecture Overview

```
 Client ──POST /orders──▶  API Gateway v2        OrderProducer Lambda (Node 22)
                          orders-api-local  ─────▶  index.handler
                          (HTTP, $default,         + parses JSON body
                           AWS_PROXY,              + SendMessage ───────────┐
                           payload 2.0)            + returns HTTP 202        │
                                                                             ▼
                                                    ┌─────────────────────────────────────┐
                                                    │  SQS Queue  orders-order-main-local  │
                                                    │  visibility_timeout = 30s            │
                                                    │  redrive → orders-order-dlq-local    │
                                                    └─────────────────────────────────────┘
                                                    (maxReceiveCount = 3 → DLQ on failure)
                                                                             │
                                Event Source Mapping (batch_size = 5)  ◀────┘
                                                                             ▼
                                                   OrderConsumer Lambda (Node 22)
                                                   + iterates event.Records
                                                   + PutItem ──────────────▶  DynamoDB
                                                                             orders-local
                                                                             status = "PROCESSED"
```

### Data Flow

1. **Ingress** — the client sends `POST /orders` to the API Gateway HTTP v2 endpoint.
2. **Produce (async)** — API Gateway invokes `OrderProducer` via an `AWS_PROXY` integration. The producer parses the JSON body (generating an `orderId` if none is provided), constructs a message (`orderId`, `item`, `amount`, `timestamp`), and sends it to the SQS queue. It immediately returns **HTTP 202 Accepted** with the `orderId` — a fire-and-forget pattern that keeps the request path fast and decoupled.
3. **Decouple** — SQS `orders-order-main-local` buffers messages. A dead-letter queue (`orders-order-dlq-local`) captures messages that fail after **3 receives**, providing resilience against poison-pill messages.
4. **Consume** — the consumer Lambda is triggered by an SQS event source mapping (batch size 5). It iterates `event.Records`, parses each body, and `PutItem`s into the DynamoDB `orders-local` table, stamping `status: "PROCESSED"` and a `processedAt` timestamp.

### Why this design

- **Async**: the caller gets an immediate `202`; the heavy lifting happens in the background.
- **Decoupled**: API Gateway, producer, queue, consumer, and database are all independent — a failure in the consumer cannot block the producer, and vice-versa.
- **Buffered & resilient**: SQS absorbs traffic bursts, and the DLQ isolates messages the consumer cannot process.

---

## Repository Layout

```
lambda_apigateway-producer-sqs-consumer-dynamodb/
├── README.md                       # This document
├── preview.html                    # Visual architecture diagram (open in browser)
├── src/
│   └── orders/
│       ├── producer/index.js       # Lambda: API Gateway → SQS producer (202 response)
│       └── consumer/index.js       # Lambda: SQS → DynamoDB consumer (PutItem)
└── infrastructure/                 # Terraform module (note: historical misspelling)
    ├── main.tf                     # Root module, wires the 4 sub-modules together
    ├── providers.tf                # AWS (→ floci) + archive providers, endpoints
    ├── test.tfvars                 # Local test variable values
    └── modules/
        ├── api/main.tf             # API Gateway v2 (HTTP), POST /orders route
        ├── events/main.tf          # SQS main queue + DLQ with redrive policy
        ├── functions/main.tf       # Both Lambdas, IAM role, event source mapping
        └── db/main.tf              # DynamoDB table
```
---

## Module Breakdown

All resources are defined via Terraform modules under `infrastructure/modules/`. `main.tf` is the orchestrator that threads inputs/outputs between them.

| Module | File | Key resources | Purpose |
| ------ | ---- | ------------- | ------- |
| `storage` | `modules/db/main.tf` | `aws_dynamodb_table.test_db` → `orders-local` | Order persistence. `PAY_PER_REQUEST`, hash key `orderId` (S) |
| `events` | `modules/events/main.tf` | `aws_sqs_queue.order_main`, `aws_sqs_queue.order_dlq` | Message buffering + DLQ. Main has 30s visibility and `maxReceiveCount = 3` redrive to DLQ |
| `compute` | `modules/functions/main.tf` | `aws_iam_role.lambda_exec`, `× 2 aws_lambda_function` (producer, consumer), `aws_lambda_event_source_mapping.sqs_trigger` | The two Lambdas, their scoped IAM role, and the SQS→consumer trigger (`batch_size = 5`) |
| `api` | `modules/api/main.tf` | `aws_apigatewayv2_api.http`, `aws_apigatewayv2_route.post_orders`, `aws_apigatewayv2_integration.producer`, `aws_apigatewayv2_stage.default`, `aws_lambda_permission.apigw_invoke` | HTTP v2 ingress, `POST /orders` → producer, auto-deploy `$default` stage |

### Resource IDs (as deployed for `environment = "local"`)

| Resource type | Name |
| ------------- | ---- |
| DynamoDB table | `orders-local` |
| SQS main queue | `orders-order-main-local` |
| SQS DLQ | `orders-order-dlq-local` |
| IAM role | `lambda-exec-role-local` |
| IAM policy | `lambda-exec-policy-local` |
| Producer Lambda | `OrderProducer-local` |
| Consumer Lambda | `OrderConsumer-local` |
| API Gateway v2 API | `orders-api-local` |

---

## The Lambdas (`src/orders`)

Both functions use the AWS SDK v3 and rely on **environment variables** set by Terraform to stay agnostic of their wiring.

### Producer — `producer/index.js`

- Reads `QUEUE_URL` and the Region from the environment.
- Parses `event.body`; uses `body.orderId` or mints `ord_<uuid>`.
- Builds a message payload (`orderId`, `item`, `amount`, `timestamp`).
- Calls SQS `SendMessageCommand` against the configured queue.
- Returns **`202 Accepted`** (`{ message, orderId }`) on success, `500` on error.

### Consumer — `consumer/index.js`

- Reads `TABLE_NAME` from the environment.
- For each `record` in `event.Records`, parses `record.body`.
- Calls DynamoDB `PutCommand` (via the document client) storing `orderId`, `item`, `amount`, `status: "PROCESSED"`, `processedAt`.

### IAM permissions (least privilege)

A single shared role scoped to exactly what each task needs:

```
sqs:      SendMessage, ReceiveMessage, DeleteMessage, GetQueueAttributes  → main queue ARN
dynamodb: PutItem, GetItem                                               → table ARN
```

---

## Prerequisites

- [Docker](https://www.docker.com/) + Docker Compose
- [Terraform](https://developer.hashicorp.com/terraform) `>= 1.5.0`
- Node.js (to inspect/run the Lambda source; the deployed runtime is `nodejs22.x`)
- `aws` CLI (optional, to verify deployed resources against floci)

---

## Local Runtime Setup

This project targets a local [floci](https://floci.io) instance. The stack is started and provisioned from the workspace root.

### 1. Start the local AWS stack

```bash
docker compose up -d
```

- **floci** — LocalStack-compatible core, exposed on **`localhost:4566`**
- **floci-ui** — Web UI, exposed on **`localhost:4500`** (`open http://localhost:4500`)

### 2. Apply the stack

From the `infrastructure/` directory:

```bash
terraform init
terraform plan -var-file=test.tfvars -out=tfplan
terraform apply tfplan
```

`test.tfvars` configures the sandbox:

```hcl
aws_region     = "us-east-1"
floci_endpoint = "http://localhost:4566"
environment    = "local"
table_name     = "orders"
queue_name     = "orders"
```

### 3. Endpoint wiring

`providers.tf` points the AWS provider at the local endpoint using dummy sandbox credentials and validation skips, with explicit endpoint overrides for each service this stack uses:

```hcl
provider "aws" {
  region                      = var.aws_region
  access_key                  = "floci"
  secret_key                  = "floci"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigatewayv2 = var.floci_endpoint
    dynamodb     = var.floci_endpoint
    iam          = var.floci_endpoint
    lambda       = var.floci_endpoint
    sqs          = var.floci_endpoint
  }
}
```

---

## Exercise the Pipeline

Once applied, grab the API URL from Terraform output:

```bash
terraform output api_url     # -> e.g. http://localhost:4566/<api-id>.execute-api/.../orders
```

Send an order (the producer returns `202 Accepted` and the consumer eventually writes to DynamoDB):

```bash
curl -X POST "$(terraform output -raw api_url)" \
  -H "Content-Type: application/json" \
  -d '{"item": "Laptop", "amount": 2}'
# {"message":"Order accepted for processing","orderId":"ord_<uuid>"}
```

Verify the message landed in DynamoDB (via floci/WSL-like endpoint):

```bash
aws --endpoint-url http://localhost:4566 dynamodb scan \
  --table-name orders-local \
  --region us-east-1
```

or browse the floci UI (`http://localhost:4500`) to watch the API, queues, Lambdas, and the table.

---

## Verify the Deployment

```bash
# SQS queues
aws --endpoint-url http://localhost:4566 sqs list-queues --region us-east-1

# DynamoDB table
aws --endpoint-url http://localhost:4566 dynamodb list-tables --region us-east-1

# Lambda functions
aws --endpoint-url http://localhost:4566 lambda list-functions --region us-east-1
```

---

## Teardown

```bash
terraform destroy -var-file=test.tfvars -auto-approve
```

---

## Caveats / Notes

- **Local/sandbox**: all credentials are dummy values and every AWS API call is served by floci, not real AWS.
- **Hard-coded Lambda endpoint**: `src/orders/*/index.js` currently sets the SDK endpoint to `http://host.docker.internal:4566` (the Docker-host address). Terraform also injects `AWS_ENDPOINT_URL=http://localhost:4566`, but the source hard-codes over it. If the Lambdas (running inside a container) cannot reach that host address, switch the endpoint to the matching reachable value — see the commented-out lines in each file.
- **No bundler**: the Lambdas are zipped directly from `src/orders/*` via Terraform’s `archive_file` — there is no `package.json`/`node_modules` step. The SDK modules are resolved/available in the floci runtime environment.
- **Single queue/table**: designed as a local reference, not a production-grade multi-AZ deployment.
