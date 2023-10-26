module "vpc" {
  source  = "punkerside/vpc/aws"
  version = "0.0.6"

  name = var.name
}

resource "aws_ecr_repository" "main" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = var.name
  }
}