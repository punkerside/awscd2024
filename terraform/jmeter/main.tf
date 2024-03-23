resource "aws_iam_role" "main" {
  name               = "${var.name}-jmeter"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "${var.name}-jmeter"
  }
}


resource "aws_iam_role_policy" "main" {
  name = "${var.name}-jmeter"
  role = aws_iam_role.main.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:Get*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.name}-jmeter",
        "arn:aws:s3:::${var.name}-jmeter/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.main.name}:${data.aws_caller_identity.main.account_id}:log-group:${var.name}-jmeter",
        "arn:aws:logs:${data.aws_region.main.name}:${data.aws_caller_identity.main.account_id}:log-group:${var.name}-jmeter:log-stream:*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "arn:aws:codebuild:${data.aws_region.main.name}:${data.aws_caller_identity.main.account_id}:project/${var.name}-jmeter"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_s3_bucket" "main" {
  bucket        = "${var.name}-jmeter"
  force_destroy = true

  tags = {
    Name = var.name
  }
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "main" {
  bucket = aws_s3_bucket.main.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.main
  ]
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = <<POLICY
{
    "Id": "ExamplePolicy",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSSLRequestsOnly",
            "Action": "s3:*",
            "Effect": "Deny",
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.main.id}",
                "arn:aws:s3:::${aws_s3_bucket.main.id}/*"
            ],
            "Condition": {
                "Bool": {
                     "aws:SecureTransport": "false"
                }
            },
           "Principal": "*"
        }
    ]
}
POLICY
}

resource "aws_cloudwatch_log_group" "main" {
  name = "${var.name}-jmeter"

  tags = {
    Name = "${var.name}-jmeter"
  }
}

resource "aws_codebuild_project" "main" {
  name          = "${var.name}-jmeter"
  description   = "${var.name}-jmeter"
  build_timeout = 30
  service_role  = aws_iam_role.main.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_LARGE"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "apiEndpoint"
      value = ""
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.main.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
version: 0.2
phases:
  build:
    commands:
      - ./terraform/jmeter/run.sh
BUILDSPEC
  }

  tags = {
    Name = "${var.name}-jmeter"
  }
}

resource "aws_codestarconnections_connection" "main" {
  name          = "${var.name}"
  provider_type = "GitHub"
}

resource "aws_codepipeline" "main" {
  name          = "${var.name}-jmeter"
  role_arn      = aws_iam_role.main.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.main.bucket
    type     = "S3"
  }

  variable {
    name          = "apiEndpoint"
    default_value = "ecs.punkerside.io"
    description   = "API endpoint to test"
  }

  variable {
    name          = "numThreads"
    default_value = "1000"
    description   = "numero de hilos"
  }

  variable {
    name          = "startUsers"
    default_value = "100"
    description   = "usuarios iniciales"
  }

  variable {
    name          = "flightTime"
    default_value = "180"
    description   = "tiempo de vuelo"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.main.arn
        FullRepositoryId     = "punkerside/ecs-vs-eks"
        BranchName           = "main"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.main.name
        EnvironmentVariables = jsonencode([
          {
            type  = "PLAINTEXT"
            name  = "apiEndpoint"
            value = "#{variables.apiEndpoint}"
          }
        ])
      }
    }
  }

  tags = {
    Name = "${var.name}-jmeter"
  }
}