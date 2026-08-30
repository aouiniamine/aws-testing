
resource "aws_subnet" "private_zone" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id

  cidr_block        = local.private_subnet_cidr[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.environment}-private-${local.azs[count.index]}"
  }
}
