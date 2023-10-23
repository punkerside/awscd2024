module "vpc" {
  source  = "punkerside/vpc/aws"
  version = "0.0.6"

  name = var.name
}