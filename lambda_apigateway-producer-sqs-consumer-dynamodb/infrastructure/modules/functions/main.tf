variable "environment" { type = string }
variable "floci_endpoint" { type = string }
variable "queue_url" { type = string }
variable "queue_arn" { type = string }
variable "dynamodb_table_name" { type = string }
variable "dynamodb_table_arn" { type = string }

# Execution Role with Scoped Permissions
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-exec-policy-${var.environment}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [var.queue_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
        Resource = [var.dynamodb_table_arn]
      }
    ]
  })
}

# Producer Lambda
data "archive_file" "producer_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/orders/producer"
  output_path = "${path.module}/builds/producer.zip"
}

resource "aws_lambda_function" "producer" {
  filename         = data.archive_file.producer_zip.output_path
  function_name    = "OrderProducer-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  source_code_hash = data.archive_file.producer_zip.output_base64sha256

  environment {
    variables = {
      QUEUE_URL        = var.queue_url
      AWS_ENDPOINT_URL = var.floci_endpoint
    }
  }
}

# Consumer Lambda
data "archive_file" "consumer_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../src/orders/consumer"
  output_path = "${path.module}/builds/consumer.zip"
}

resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_zip.output_path
  function_name    = "OrderConsumer-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME       = var.dynamodb_table_name
      AWS_ENDPOINT_URL = var.floci_endpoint
    }
  }
}

# Event Pipeline Source Mapping
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.queue_arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 5
}

output "producer_arn" { value = aws_lambda_function.producer.arn }
output "producer_invoke_arn" { value = aws_lambda_function.producer.invoke_arn }
output "producer_function_name" { value = aws_lambda_function.producer.function_name }
