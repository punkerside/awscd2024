resource "aws_iam_role" "main" {
  name               = "${var.name}-eks"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["eks.amazonaws.com", "eks-fargate-pods.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "${var.name}-eks"
  }
}

resource "aws_iam_role_policy" "main" {
  name = "${var.name}-eks"
  role = aws_iam_role.main.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "wafv2:*",
        "waf-regional:*",
        "sts:AssumeRoleWithWebIdentity",
        "sts:*",
        "ec2:*",
        "acm:*"
      ],
      "Resource": "*"
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

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AutoScalingFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2RoleforSSM" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.main.name
}

resource "aws_eks_cluster" "main" {
  name                      = var.name
  role_arn                  = aws_iam_role.main.arn
  version                   = "1.28"
  enabled_cluster_log_types = []

  vpc_config {
    subnet_ids              = concat(sort(data.aws_subnets.private.ids), sort(data.aws_subnets.public.ids), )
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  tags = {
    Name = var.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy
  ]
}

resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "default"
  pod_execution_role_arn = aws_iam_role.main.arn
  subnet_ids             = data.aws_subnets.private.ids

  selector {
    namespace = "default"
  }

  selector {
    namespace = "kube-system"
  }
}

resource "aws_iam_openid_connect_provider" "main" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.main.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity.0.oidc.0.issuer
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ingress"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${data.aws_caller_identity.main.account_id}:oidc-provider/oidc.eks.${data.aws_region.main.name}.amazonaws.com/id/${substr(aws_eks_cluster.main.identity.0.oidc.0.issuer, -32, -1)}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.${data.aws_region.main.name}.amazonaws.com/id/${substr(aws_eks_cluster.main.identity.0.oidc.0.issuer, -32, -1)}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

  tags = {
    Name = "${var.name}-ingress"
  }
}

resource "aws_iam_role_policy" "this" {
  name = "${var.name}-ingress"
  role = aws_iam_role.this.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_acm_certificate" "main" {
  domain_name       = "eks.punkerside.io"
  validation_method = "DNS"
}

resource "aws_route53_record" "main" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.main.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
  ttl             = 60
}