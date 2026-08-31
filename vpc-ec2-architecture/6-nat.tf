resource "aws_eip" "ec2_eip" {
  count  = length(local.azs)
  domain = "vpc"

  tags = {
    Name = "${var.environment}-ec2-eip-${local.azs[count.index]}"
  }
}

resource "aws_nat_gateway" "ec2_nat" {
  count = length(local.azs)

  allocation_id = aws_eip.ec2_eip[count.index].id
  subnet_id     = aws_subnet.ec2_public_subnet[count.index].id

  tags = {
    Name = "${var.environment}-ec2-nat-${local.azs[count.index]}"
  }
  depends_on = [aws_internet_gateway.ec2_igw]
}


