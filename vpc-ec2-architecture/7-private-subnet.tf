
resource "aws_subnet" "ec2_private_subnet" {
  count  = length(local.azs)
  vpc_id = aws_vpc.ec2_vpc.id

  cidr_block        = local.private_subnet[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.environment}-ec2-private-subnet-${count.index}"
  }
}

