resource "aws_route_table" "ec2_public_route_table" {
  vpc_id = aws_vpc.ec2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ec2_igw.id
  }

  tags = {
    Name = "${var.environment}-ec2-public-route-table"
  }
}

resource "aws_route_table_association" "ec2_public_route_table_association" {
  count          = length(local.azs)
  route_table_id = aws_route_table.ec2_public_route_table.id
  subnet_id      = aws_subnet.ec2_public_subnet[count.index].id
}
