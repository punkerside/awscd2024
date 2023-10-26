data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.name]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"    
    values = ["${var.name}-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"    
    values = ["${var.name}-private-*"]
  }
}

data "aws_route53_zone" "main" {
  name         = "punkerside.io."
  private_zone = false
}

# data "aws_db_instance" "main" {
#   db_instance_identifier = var.name
# }

data "aws_caller_identity" "main" {}
data "aws_region" "main" {}