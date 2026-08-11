variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment_name" {
  type    = string
  default = "dev"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the existing AWS VPC to use for the janitor environment."
}

variable "subnet_id" {
  type        = string
  description = "The ID of the existing AWS subnet where janitor instances will be launched."
}

variable "enable_subnet_reservation" {
  type    = bool
  default = false
  description = "When true, create an aws_ec2_subnet_cidr_reservation using the subnet's CIDR to simulate IP exhaustion."
}
