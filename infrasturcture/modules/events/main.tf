variable "queue_name" { type = string }
variable "environment" { type = string }

resource "aws_sqs_queue" "order_dlq" {
  name = "${var.queue_name}-order-dlq-${var.environment}"
}

resource "aws_sqs_queue" "order_main" {
  name                       = "${var.queue_name}-order-main-${var.environment}"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

output "queue_id" { value = aws_sqs_queue.order_main.id }
output "queue_arn" { value = aws_sqs_queue.order_main.arn }
