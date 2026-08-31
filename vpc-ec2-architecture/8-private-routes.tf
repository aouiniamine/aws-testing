

resource "aws_route_table" "ec2_private_route_table" {
  count  = length(local.azs)
  vpc_id = aws_vpc.ec2_vpc.id

  route {
    nat_gateway_id = aws_nat_gateway.ec2_nat[count.index].id
    cidr_block     = "0.0.0.0/0"
  }

  tags = {
    Name = "${var.environment}-ec2-private-route-table-${count.index}"
  }
}

resource "aws_route_table_association" "ec2_private_route_table_association" {
  count          = length(local.azs)
  route_table_id = aws_route_table.ec2_private_route_table[count.index].id
  subnet_id      = aws_subnet.ec2_private_subnet[count.index].id
}
