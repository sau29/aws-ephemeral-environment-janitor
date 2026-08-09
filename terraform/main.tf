terraform {
  required_version = ">= 1.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0.0"
    }
  }

  backend "s3" {
    bucket = "aws-ephemeral-environment-janitor-state"
    region = "us-east-1"
    # key is still passed dynamically with -backend-config="key=..."
    # backend settings cannot use normal root-module variables like var.aws_region.
    # The S3 bucket must already exist before terraform init.
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"]
}

resource "aws_vpc" "private" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = false
  tags = {
    Name        = "ephemeral-janitor-private-vpc"
    Environment = var.environment_name
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.private.id
  cidr_block              = "10.0.0.0/28"
  map_public_ip_on_launch = false
  tags = {
    Name        = "ephemeral-janitor-private-subnet"
    Environment = var.environment_name
  }
}

resource "aws_ec2_subnet_cidr_reservation" "reserved_capacity" {
  subnet_id        = aws_subnet.private.id
  cidr_block       = "10.0.0.0/29"
  reservation_type = "explicit"
}

resource "aws_security_group" "private_app" {
  name        = "ephemeral-janitor-private-sg"
  description = "Allow private traffic to port 8080"
  vpc_id      = aws_vpc.private.id

  ingress {
    description = "Allow internal access to 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.private.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ephemeral-janitor-private-sg"
    Environment = var.environment_name
  }
}

resource "aws_instance" "janitor" {
  count                       = 3
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private_app.id]
  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = false
    tags = {
      Ephemeral   = "true"
      Environment = var.environment_name
    }
  }

  tags = {
    Name        = "ephemeral-janitor-instance-${count.index + 1}"
    Environment = var.environment_name
  }

  lifecycle {
    create_before_destroy = false
  }
}
