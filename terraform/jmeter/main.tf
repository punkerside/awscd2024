resource "aws_iam_role" "main" {
  name               = var.name
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com"]
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
        "ec2:*",
        "ssm:*",
        "ec2messages:*",
        "ssmmessages:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "main" {
  name = var.name
  role = aws_iam_role.main.name
}

resource "aws_security_group" "main" {
  name        = var.name
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
    Name = var.name
  }
}

resource "aws_instance" "main" {
  ami                         = data.aws_ami.main.id
  associate_public_ip_address = true
  instance_type               = "c7a.2xlarge"
  disable_api_termination     = false
  ebs_optimized               = true
  iam_instance_profile        = aws_iam_instance_profile.main.name
  subnet_id                   = data.aws_subnets.main.ids[1]
  vpc_security_group_ids      = [aws_security_group.main.id]

  # instance_market_options {
  #   spot_options {}
  # }

  ebs_block_device {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    encrypted             = false
    volume_size           = 60
    volume_type           = "gp3"
  }

  tags = {
    Name = var.name
  }
}