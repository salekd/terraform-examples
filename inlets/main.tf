provider "aws" {
  region = "eu-central-1"
}


##########
# Key pair
##########

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "david-test3-key"
  public_key = tls_private_key.this.public_key_openssh
}


#####
# VPC
#####

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

# Internet gateway

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

# Route tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_default_route_table" "private" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  tags = {
    Name = "private"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public1"
  }
}

resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.101.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private1"
  }
}

# Subnet associations

resource "aws_route_table_association" "public1_assoc" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1_assoc" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_default_route_table.private.id
}


#################
# Security groups
#################

resource "aws_security_group" "public_sg" {
  name        = "sg_public"
  description = "Used for public instances"
  vpc_id      = aws_vpc.vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inlets
  ingress {
    from_port   = 8090
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_sg" {
  name        = "sg_private"
  description = "Used for private instances"
  vpc_id      = aws_vpc.vpc.id

  # Access from other security groups
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#####
# EC2
#####

data "aws_ami" "amazon_linux" {
  most_recent = true
  name_regex  = "^amzn-.*"
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "user_data" {
  template = "${file("templates/inlets.tpl")}"

  vars = {
    token = "${var.inlets_token}"
  }
}

resource "aws_instance" "inlets_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"

  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  subnet_id              = aws_subnet.public1.id
  associate_public_ip_address = true

  user_data = data.template_file.user_data.rendered

  tags = {
    Name = "inlets_server"
  }
}


##########
# Route 53
##########

resource "aws_route53_record" "inlets" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"
  ttl     = "300"
  records = [aws_instance.inlets_server.public_ip]
}
