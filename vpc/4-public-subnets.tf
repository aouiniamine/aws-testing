
resource "aws_subnet" "public_zone" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_cidr[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.environment}-public-${local.azs[count.index]}"
  }
  map_public_ip_on_launch = true
}

