
resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-main-vpc"
  }

}
