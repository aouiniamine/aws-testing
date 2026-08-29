variable "environment" { type = string }

# --- 1. S3 Storage ---
resource "aws_s3_bucket" "source" {
  bucket = "image-source-bucket-${var.environment}"
}

resource "aws_s3_bucket" "dest" {
  bucket = "image-resized-bucket-${var.environment}"
}

resource "aws_s3_bucket_public_access_block" "source_block" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "dest_block" {
  bucket                  = aws_s3_bucket.dest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "source_bucket_name" { value = aws_s3_bucket.source.id }
output "source_bucket_arn" { value = aws_s3_bucket.source.arn }
output "dest_bucket_name" { value = aws_s3_bucket.dest.id }
output "dest_bucket_arn" { value = aws_s3_bucket.dest.arn }
