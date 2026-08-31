
resource "aws_eip" "ec2_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.environment}-ec2-eip"
  }
}

resource "aws_nat_gateway" "ec2_nat" {
  count = length(local.azs)

  allocation_id = aws_eip.ec2_eip.id
  subnet_id     = aws_subnet.ec2_public_subnet[count.index].id

  tags = {
    Name = "${var.environment}-ec2-nat-${count.index}"
  }
  depends_on = [aws_internet_gateway.ec2_igw]
}


