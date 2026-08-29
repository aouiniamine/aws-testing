variable "environment" { type = string }

resource "aws_dynamodb_table" "image_metadata" {
  name         = "image_metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ImageId"

  attribute {
    name = "ImageId"
    type = "S"
  }
}

output "table_name" { value = aws_dynamodb_table.image_metadata.name }
output "table_arn" { value = aws_dynamodb_table.image_metadata.arn }

