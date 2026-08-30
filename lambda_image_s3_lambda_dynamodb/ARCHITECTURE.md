# Architecture — Lambda image resizer with S3 + DynamoDB

Serverless image-resizing pipeline with an event-driven flow. An S3 upload
triggers a Lambda that generates three resized variants, stores them in a second
S3 bucket, and records metadata in DynamoDB.

> Visual preview: open `preview.html` in a browser, or run
> `python3 -m http.server 8000` from this directory and visit
> <http://localhost:8000/preview.html>.

## High-level flow

```
        ┌─────────────┐  ObjectCreated:*   ┌────────────┐
        │  S3 source  │ ─────────────────▶ │  Lambda    │
        │   bucket    │    (event hook)    │  resizer   │ ◀── IAM role grants access
        └─────────────┘                    └─────┬──────┘
                                                 │
                          ┌──────────────────────┼───────────────────────┐
                          ▼                      ▼                       ▼
                 ┌──────────────┐      ┌──────────────┐        ┌─────────────┐
                 │ S3 dest      │      │ S3 dest      │        │ DynamoDB    │
                 │ images/thumb │      │ images/large │        │ metadata    │
                 └──────────────┘      └──────────────┘        └─────────────┘
```

## Components

| Component | Resource | Detail |
|---|---|---|
| Event source | `aws_s3_bucket.source` | `image-source-bucket-<env>`; uploads here trigger the pipeline |
| Trigger | `aws_s3_bucket_notification` | Fires on `s3:ObjectCreated:*`, invokes the Lambda |
| Compute | `aws_lambda_function.resizer` | `image-resizer-service-<env>`, Node.js `nodejs20.x`, x86_64, 512 MB, 30s timeout |
| Storage (resized) | `aws_s3_bucket.dest` | `image-resized-bucket-<env>`; receives `images/thumb|medium|large/...` |
| Metadata | `aws_dynamodb_table` | `image_metadata-<env>`, `PAY_PER_REQUEST`, hash key `ImageId` |
| Permissions | `aws_iam_role` + `aws_iam_policy` | Read source S3, write dest S3, `dynamodb:PutItem`, CloudWatch logs |
| Emulator | Floci `floci/floci:1.7.0` | Local AWS emulator at `http://localhost:4566` (via docker-compose) |

## Data flow detail

1. An image is uploaded to the **source S3 bucket**
   (`s3:ObjectCreated:*` notification).
2. **Lambda** (`src/index.js`) receives the S3 event and, per record:
   - Downloads the original object via `GetObjectCommand`.
   - Resizes it with **sharp** to three variants — `thumb` (150×150),
     `medium` (500×500), `large` (1024×1024) — using `fit: 'inside'`
     (aspect-ratio preserving, no upscaling).
   - Uploads each variant to the **destination bucket** as
     `images/<size>/<filename><ext>` via `PutObjectCommand`.
   - Records variant metadata `{s3_key, s3_url, floci_s3_url, width, height,
     file_size_bytes}` and writes a single item (`ImageId` = source key,
     `SourceBucket`, `ProcessedAt`, `Variants`) to **DynamoDB**.

Variant size map (`src/index.js`):

```js
const SIZES = {
    thumb:  { width: 150,  height: 150  },
    medium: { width: 500,  height: 500  },
    large:  { width: 1024, height: 1024 },
};
```

DynamoDB item shape:

```
ImageId        : String  (partition key, the source S3 key)
SourceBucket   : String
ProcessedAt    : Number  (unix seconds)
Variants       : Map
  thumb/medium/large -> { s3_key, s3_url, floci_s3_url, width, height, file_size_bytes }
```

> Note: `src/index.js` is the **active** runtime handler (`handler = "index.handler"`).
> `src/resize_image.py` is a retained Python/Pillow equivalent (currently disabled in
> Terraform — see the commented-out `aws_lambda_function` block in
> `infrastructure/modules/functions/main.tf`).

## Repository layout

```
├── src/
│   ├── index.js          # Node.js Lambda handler (sharp-based resizer)
│   ├── resize_image.py   # Python/Pillow equivalent (archive/alternative)
│   └── package.json      # @aws-sdk/*, sharp (npm install --os=linux --cpu=x64)
├── infrastructure/
│   ├── main.tf           # Orchestrates the three modules
│   ├── providers.tf      # AWS provider pointed at the Floci emulator
│   ├── test.tfvars       # aws_region / floci_endpoint / environment
│   ├── modules/
│   │   ├── s3/           # source + dest buckets (public access blocked)
│   │   ├── db/           # DynamoDB metadata table
│   │   └── functions/    # IAM, Lambda, S3 event notification + permissions
├── ARCHITECTURE.md       # this document
└── preview.html          # standalone visual diagram
```

## Terraform modules

### `modules/s3`
Creates `image-source-bucket-<env>` and `image-resized-bucket-<env>`, both with
public ACL/policy access fully blocked. Exposes names and ARNs.

### `modules/db`
Creates a `PAY_PER_REQUEST` DynamoDB table with `ImageId` (String) as the hash
key.

### `modules/functions`
- `aws_iam_role` (assume `lambda.amazonaws.com`) + policy granting `s3:GetObject`
  on the source bucket, `s3:PutObject` on the destination bucket,
  `dynamodb:PutItem` on the metadata table, and CloudWatch log access.
- `archive_file` zips `../src` at plan time.
- `aws_lambda_function` with env vars:
  `DEST_BUCKET`, `DYNAMODB_TABLE`, `AWS_ENDPOINT_URL` (Floci fallback).
- `aws_lambda_permission` + `aws_s3_bucket_notification` wire the S3→Lambda hook.

## Local emulation (Floci)

The whole stack runs against **Floci** (`localhost:4566`) instead of AWS.
Providers point all AWS endpoints at the emulator via `providers.tf`:

```hcl
provider "aws" {
  access_key                  = "floci"
  secret_key                  = "floci"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    dynamodb = var.floci_endpoint   # http://localhost:4566
    lambda   = var.floci_endpoint
    iam      = var.floci_endpoint
    ...
  }
}
```

`docker-compose.yaml` (repo root) runs `floci` (:4566) plus the `floci-ui`
dashboard (:4500). S3 access uses `forcePathStyle: true` and the SDK resolves
`http://host.docker.internal:4566` from inside the Lambda emulator.

## Setup / deploy

```bash
# 1. Start the Floci emulator stack
docker compose up -d

# 2. Deploy infrastructure (local emulator target)
cd infrastructure
terraform init
terraform plan -var-file=test.tfvars
terraform apply -var-file=test.tfvars

# 3. Smoke test: upload an image to the source bucket, then query DynamoDB
aws --endpoint-url http://localhost:4566 s3 cp ./demo.jpg s3://image-source-bucket-local/
aws --endpoint-url http://localhost:4566 dynamodb scan \
    --table-name image_metadata-local
```