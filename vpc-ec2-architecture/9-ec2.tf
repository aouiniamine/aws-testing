resource "aws_security_group" "allow_local" {
  name        = "allow_local"
  description = "Allow all traffic from local vpc"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.ec2_vpc.id
  tags = {
    Name = "${var.environment}-ec2-allow-local"
  }
  depends_on = [aws_vpc.ec2_vpc]
}

# resource "aws_key_pair" "ec2_key_pair" {
#   key_name   = "test-ec2"
#   public_key = file("./../.ssh/id_ed25519.pub")
# }

resource "aws_instance" "private-ec2" {
  count             = length(local.azs)
  ami               = "ami-0f02b24005e4aec36"
  availability_zone = local.azs[count.index]
  instance_type     = "t2.micro"
  #   key_name          = aws_key_pair.ec2_key_pair.key_name
  tags = {
    Name = "${var.environment}-private-ec2-${local.azs[count.index]}"
  }
  subnet_id              = aws_subnet.ec2_private_subnet[count.index].id
  vpc_security_group_ids = [aws_security_group.allow_local.id]
  depends_on             = [aws_vpc.ec2_vpc, aws_subnet.ec2_private_subnet]
}

output "private-ec2" {
  value = aws_instance.private-ec2[*].id
}


resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all traffic in/out"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.ec2_vpc.id
  tags = {
    Name = "${var.environment}-ec2-allow-all"
  }
  depends_on = [aws_vpc.ec2_vpc]
}


resource "aws_instance" "public-ec2" {
  count             = length(local.azs)
  ami               = "ami-0f02b24005e4aec36"
  availability_zone = local.azs[count.index]
  instance_type     = "t2.micro"
  #   key_name          = aws_key_pair.ec2_key_pair.key_name

  tags = {
    Name = "${var.environment}-public-ec2-${local.azs[count.index]}"
  }
  subnet_id              = aws_subnet.ec2_public_subnet[count.index].id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  depends_on             = [aws_vpc.ec2_vpc, aws_subnet.ec2_public_subnet]
}

output "public-ec2" {
  value = aws_instance.private-ec2[*].id
}
output "public-ec2-ips" {
  value = aws_instance.public-ec2[*].public_ip

}

