variable "environment" { type = string }
variable "table_name" { type = string }

resource "aws_dynamodb_table" "test_db" {
  name         = "${var.table_name}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
}

output "table_name" { value = aws_dynamodb_table.test_db.name }
output "table_arn" { value = aws_dynamodb_table.test_db.arn }
