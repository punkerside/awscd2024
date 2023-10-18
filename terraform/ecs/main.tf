module "vpc" {
  source  = "punkerside/vpc/aws"
  version = "0.0.5"

  name = var.name
}

resource "aws_ecr_repository" "main" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}