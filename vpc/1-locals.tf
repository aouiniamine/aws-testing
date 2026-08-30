

locals {
  azs      = ["${var.aws_region}a", "${var.aws_region}b"]
  vpc_cidr = "10.10.0.0/16"

  private_subnet_cidr = ["10.10.11.0/24", "10.10.12.0/24"]
  public_subnet_cidr  = ["10.10.0.0/24", "10.10.1.0/24"]

}
