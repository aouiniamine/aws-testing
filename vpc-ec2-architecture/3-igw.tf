resource "aws_internet_gateway" "ec2_igw" {
  vpc_id = aws_vpc.ec2_vpc.id

  tags = {
    Name = "${var.environment}-ec2-igw"
  }
}
