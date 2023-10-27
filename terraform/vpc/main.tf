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

resource "aws_security_group" "main" {
  name        = "${var.name}-rds"
  description = "inbound traffic"
  vpc_id      = module.vpc.vpc.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = module.vpc.subnet_private_ids.*.id

  tags = {
    Name = var.name
  }
}

resource "aws_db_instance" "main" {
  identifier             = var.name
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "users"
  engine                 = "postgres"
  engine_version         = "15.3"
  instance_class         = "db.t3.medium"
  username               = "postgres"
  password               = "postgres"
  skip_final_snapshot    = true
  apply_immediately      = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  deletion_protection    = false
  network_type           = "IPV4"
  multi_az               = false
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = var.name
  }
}