data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.name]
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

data "aws_caller_identity" "main" {}
data "aws_region" "main" {}

# data "aws_db_instance" "main" {
#   db_instance_identifier = var.name
# }