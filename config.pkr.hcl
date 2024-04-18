packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

variable "name" {
  type = string
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "main" {
  ami_name      = "${var.name}-${local.timestamp}"
  instance_type = "c7a.large"

  subnet_filter {
    filters = {
          "tag:Name": "*-public-us-east-1b"
    }
    most_free = true
    random    = false
  }

  associate_public_ip_address = true

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
}

build {
  sources = ["source.amazon-ebs.main"]

  // provisioner "file" {
  //   source      = "./testbase.jmx"
  //   destination = "/tmp/testbase.jmx"
  // }

  // provisioner "shell" {
  //   inline = ["sudo mv /tmp/testbase.jmx /opt/testbase.jmx"]
  // }

  provisioner "ansible" {
    playbook_file = "ansible/playbook.yml"
    use_proxy     = false
  }
}