data "aws_caller_identity" "main" {}
data "aws_region" "main" {}

data "tls_certificate" "main" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}