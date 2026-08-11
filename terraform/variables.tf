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

variable "reservation_cidr_block" {
  type        = string
  default     = "10.0.0.0/29"
  description = "The CIDR block to reserve inside the existing subnet."
}
