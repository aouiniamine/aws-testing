
resource "aws_vpc" "ec2_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-ec2-vpc"
  }
}
