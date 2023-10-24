# base

module "vpc" {
  source  = "punkerside/vpc/aws"
  version = "0.0.6"

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

resource "aws_iam_role" "main" {
  name               = var.name
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com", "eks.amazonaws.com", "eks-fargate-pods.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = var.name
  }
}

resource "aws_iam_role_policy" "main" {
  name = var.name
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
        "cognito-idp:*"
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

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.main.name
}

# ecs

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

resource "aws_ecs_task_definition" "main" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  container_definitions    = jsonencode([
    {
      name      = var.name
      image     = "punkerside/noroot:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
    }
  ])
}


resource "aws_security_group" "main" {
  name        = var.name
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
    Name = var.name
  }
}

resource "aws_lb" "main" {
  name                             = var.name
  internal                         = false
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.main.id]
  subnets                          = module.vpc.subnet_public_ids.*.id
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
  vpc_id      = module.vpc.vpc.id
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

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
  depends_on                        = [aws_iam_role_policy.main]
  health_check_grace_period_seconds = 0
  propagate_tags                    = "NONE"
  platform_version                  = "LATEST"
  launch_type                       = "FARGATE"

  network_configuration {
    subnets         = module.vpc.subnet_private_ids.*.id
    security_groups = [aws_security_group.main.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.name
    container_port   = 3000
  }

  tags = {
    Name = var.name
  }
}

# # eks

# resource "aws_eks_cluster" "main" {
#   name                      = var.name
#   role_arn                  = aws_iam_role.main.arn
#   version                   = "1.27"
#   enabled_cluster_log_types = []

#   tags = {
#     Name = var.name
#   }

#   vpc_config {
#     subnet_ids              = concat(sort(module.vpc.subnet_private_ids.*.id), sort(module.vpc.subnet_public_ids.*.id), )
#     endpoint_private_access = false
#     endpoint_public_access  = true
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
#     aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
#     aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy
#   ]
# }

# resource "aws_eks_fargate_profile" "main" {
#   cluster_name           = aws_eks_cluster.main.name
#   fargate_profile_name   = "default"
#   pod_execution_role_arn = aws_iam_role.main.arn
#   subnet_ids             = module.vpc.subnet_private_ids.*.id

#   selector {
#     namespace = "default"
#   }

#   selector {
#     namespace = "kube-system"
#   }
# }

# resource "aws_iam_role" "k8s" {
#   name               = "${var.name}-k8s"
#   assume_role_policy = <<EOF
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Principal": {
#                 "Federated": "arn:aws:iam::${data.aws_caller_identity.main.account_id}:oidc-provider/oidc.eks.${data.aws_region.main.name}.amazonaws.com/id/${substr(aws_eks_cluster.main.identity.0.oidc.0.issuer, -32, -1)}"
#             },
#             "Action": "sts:AssumeRoleWithWebIdentity",
#             "Condition": {
#                 "StringEquals": {
#                     "oidc.eks.${data.aws_region.main.name}.amazonaws.com/id/${substr(aws_eks_cluster.main.identity.0.oidc.0.issuer, -32, -1)}:aud": "sts.amazonaws.com"
#                 }
#             }
#         }
#     ]
# }
# EOF

#   tags = {
#     Name = "${var.name}-k8s"
#   }
# }

# resource "aws_iam_role_policy" "k8s" {
#   name = "${var.name}-k8s"
#   role = aws_iam_role.k8s.id

#   policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Action": [
#         "elasticloadbalancing:*",
#         "ecs:*",
#         "ecr:*",
#         "ec2:*",
#         "acm:*",
#         "cognito-idp:*",
#         "iam:*"
#       ],
#       "Resource": "*"
#     }
#   ]
# }
# EOF
# }