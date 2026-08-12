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

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnet" "existing" {
  id = var.subnet_id
}

# Block First Half: eg For /26, this creates 172.31.0.0/27 (32 IPs)
resource "aws_ec2_subnet_cidr_reservation" "block_first_half" {
  count            = var.enable_subnet_reservation ? 1 : 0
  subnet_id        = data.aws_subnet.existing.id
  cidr_block       = cidrsubnet(data.aws_subnet.existing.cidr_block, 1, 0)
  reservation_type = "explicit"
}

# Block Second Half: eg For /26, this creates 172.31.0.32/27 (32 IPs)
resource "aws_ec2_subnet_cidr_reservation" "block_second_half" {
  count            = var.enable_subnet_reservation ? 1 : 0
  subnet_id        = data.aws_subnet.existing.id
  cidr_block       = cidrsubnet(data.aws_subnet.existing.cidr_block, 1, 1)
  reservation_type = "explicit"
}

resource "aws_security_group" "private_app" {
  name        = "ephemeral-janitor-private-sg"
  description = "Allow private traffic to port 8080"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    description = "Allow internal access to 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
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
  subnet_id                   = data.aws_subnet.existing.id
  vpc_security_group_ids      = [aws_security_group.private_app.id]
  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = false
    tags = {
      Ephemeral   = "true"
      Environment = var.environment_name
    }
  }


  # Ensure IP reservations are applied BEFORE attempting instance creation
  depends_on = [
    aws_ec2_subnet_cidr_reservation.block_first_half,
    aws_ec2_subnet_cidr_reservation.block_second_half
  ]

  tags = {
    Name        = "ephemeral-janitor-instance-${count.index + 1}"
    Environment = var.environment_name
  }

  lifecycle {
    create_before_destroy = false
  }
}
