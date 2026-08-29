variable "source_bucket_arn" { type = string }
variable "source_bucket_name" { type = string }
variable "dest_bucket_arn" { type = string }
variable "dest_bucket_name" { type = string }
variable "dynamodb_table_arn" { type = string }
variable "dynamodb_table_name" { type = string }
variable "environment" { type = string }
variable "floci_endpoint" { type = string }

resource "aws_iam_role" "lambda_role" {
  name = "image_resizer_lambda_role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "image_resizer_policy-${var.environment}"
  description = "Allows reading source images, writing resized images, and updating DynamoDB metadata"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.source_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.dest_bucket_arn}/*"
      },
      {
        Effect   = ["dynamodb:PutItem"]
        Action   = ["dynamodb:PutItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src"
  output_path = "${path.module}/build/src.zip"
}

# resource "aws_lambda_function" "resizer" {
#   filename         = data.archive_file.lambda_zip.output_path
#   function_name    = "image-resizer-service-${var.environment}"
#   role             = aws_iam_role.lambda_role.arn
#   handler          = "resize_image.lambda_handler"
#   runtime          = "python3.10"
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   layers           = ["arn:aws:lambda:us-east-1:000000000000:layer:python-pillow-layer:12"] # published layer via AWS CLI
#   architectures    = ["x86_64"]
#   timeout          = 30
#   memory_size      = 512

#   environment {
#     variables = {
#       DEST_BUCKET    = var.dest_bucket_arn
#       DYNAMODB_TABLE = var.dynamodb_table_arn
#     }
#   }
# }

resource "aws_lambda_function" "resizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "image-resizer-service-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  architectures    = ["x86_64"]
  timeout          = 30
  memory_size      = 512

  environment {
    variables = {
      DEST_BUCKET      = var.dest_bucket_name    # Pass Bucket Name (e.g., aws_s3_bucket.dest.id)
      DYNAMODB_TABLE   = var.dynamodb_table_name # Pass Table Name (e.g., aws_dynamodb_table.metadata.name)
      AWS_ENDPOINT_URL = var.floci_endpoint      # Floci emulator fallback (http://localhost:4566)
    }
  }
}
# --- 5. Event Trigger ---
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.source_bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = var.source_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.resizer.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
