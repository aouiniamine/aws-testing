
resource "aws_subnet" "ec2_public_subnet" {
  count  = length(local.azs)
  vpc_id = aws_vpc.ec2_vpc.id

  cidr_block        = local.public_subnet[count.index]
  availability_zone = local.azs[count.index]

  map_public_ip_on_launch = true
  tags = {
    Name = "${var.environment}-ec2-public-subnet-${count.index}"
  }
}

