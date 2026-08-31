
locals {
  azs            = ["us-east-1a", "us-east-1b"]
  vpc_cidr       = "10.100.0.0/16"
  public_subnet  = ["10.100.0.0/24", "10.100.1.0/24"]
  private_subnet = ["10.100.10.0/24", "10.100.11.0/24"]
}
