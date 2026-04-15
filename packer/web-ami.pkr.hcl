packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "environment" {
  type    = string
  default = "prod"
}

source "amazon-ebs" "web" {
  ami_name      = "ha-webapp-web-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  ssh_username = "ec2-user"

  tags = {
    Name        = "ha-webapp-web-{{timestamp}}"
    Tier        = "web"
    Environment = var.environment
    ManagedBy   = "Packer"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y nginx jq amazon-cloudwatch-agent",
      "sudo systemctl enable nginx"
    ]
  }
}
