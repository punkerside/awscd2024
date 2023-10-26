resource "aws_iam_role" "main" {
  name               = "${var.name}-ecs"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "${var.name}-ecs"
  }
}

resource "aws_iam_role_policy" "main" {
  name = "${var.name}-ecs"
  role = aws_iam_role.main.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "ecs:*",
        "ecr:*",
        "ec2:*",
        "acm:*",
        "logs:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

resource "aws_ecs_cluster" "main" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_cloudwatch_log_group" "main" {
  name = var.name

  tags = {
    Name = var.name
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.main.arn

  container_definitions    = jsonencode([
    {
      name      = var.name
      image     = "${data.aws_caller_identity.main.account_id}.dkr.ecr.${data.aws_region.main.name}.amazonaws.com/${var.name}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.main.name
          awslogs-region        = data.aws_region.main.name
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = [
        {
          name = "DB_HOSTNAME"
          value = aws_db_instance.main.address
        }
      ]
    }
  ])
}

resource "aws_security_group" "main" {
  name        = "${var.name}-ecs"
  description = "inbound traffic"
  vpc_id      = data.aws_vpc.main.id

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
    Name = "${var.name}-ecs"
  }
}

resource "aws_lb" "main" {
  name                             = var.name
  internal                         = false
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.main.id]
  subnets                          = data.aws_subnets.public.ids
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true
  idle_timeout                     = 15

  tags = {
    Name = var.name
  }
}

resource "aws_lb_target_group" "main" {
  name        = var.name
  target_type = "ip"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id

  health_check {
    enabled           = true
    healthy_threshold = 2
    interval          = 5
    matcher           = "200-299"
    path              = "/"
    port              = 3000
    protocol          = "HTTP"
    unhealthy_threshold = 2
    timeout             = 3
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_ecs_service" "main" {
  name                              = var.name
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.main.arn
  desired_count                     = 2
  health_check_grace_period_seconds = 0
  propagate_tags                    = "NONE"
  platform_version                  = "LATEST"
  launch_type                       = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.private.ids
    security_groups = [aws_security_group.main.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.name
    container_port   = 3000
  }

  depends_on = [
    aws_lb.main,
    aws_iam_role_policy.main,
    aws_lb_target_group.main
  ]

  tags = {
    Name = var.name
  }
}

resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "ecs.punkerside.io"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "main" {
  domain_name       = "ecs.punkerside.io"
  validation_method = "DNS"
}

resource "aws_route53_record" "this" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
  ttl             = 60
}

resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = data.aws_subnets.private.ids

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
  instance_class         = "db.m5.large"
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