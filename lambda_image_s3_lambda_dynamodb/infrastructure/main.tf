variable "environment" { type = string }
variable "floci_endpoint" { type = string }
variable "aws_region" { type = string }


module "db" {
  source      = "./modules/db"
  environment = var.environment
}

module "s3" {
  source      = "./modules/s3"
  environment = var.environment
}

module "lambda" {
  source              = "./modules/functions"
  environment         = var.environment
  source_bucket_arn   = module.s3.source_bucket_arn
  source_bucket_name  = module.s3.source_bucket_name
  dest_bucket_arn     = module.s3.dest_bucket_arn
  dest_bucket_name    = module.s3.dest_bucket_name
  dynamodb_table_arn  = module.db.table_arn
  floci_endpoint      = var.floci_endpoint
  dynamodb_table_name = module.db.table_name
}

output "source_bucket_name" {
  value = module.s3.source_bucket_arn
}

output "destination_bucket_name" {
  value = module.s3.dest_bucket_arn
}

output "dynamodb_table_name" {
  value = module.db.table_arn
}
