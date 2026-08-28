variable "aws_region" { type = string }
variable "floci_endpoint" { type = string }
variable "environment" { type = string }
variable "table_name" { type = string }
variable "queue_name" { type = string }

module "storage" {
  source      = "./modules/db"
  environment = var.environment
  table_name  = var.table_name
}

module "events" {
  source      = "./modules/events"
  environment = var.environment
  queue_name  = var.queue_name
}

module "compute" {
  source              = "./modules/functions"
  environment         = var.environment
  floci_endpoint      = var.floci_endpoint
  queue_url           = module.events.queue_id
  queue_arn           = module.events.queue_arn
  dynamodb_table_name = module.storage.table_name
  dynamodb_table_arn  = module.storage.table_arn
}
