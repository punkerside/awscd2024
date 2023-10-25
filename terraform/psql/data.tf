data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.name]
  }
}

data "aws_caller_identity" "main" {}

data "aws_region" "main" {}

data "aws_db_instance" "main" {
  db_instance_identifier = var.name
}