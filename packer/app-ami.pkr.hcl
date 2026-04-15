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

source "amazon-ebs" "app" {
  ami_name      = "ha-webapp-app-{{timestamp}}"
  instance_type = "t3.small"
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

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "ha-webapp-app-{{timestamp}}"
    Tier        = "app"
    Environment = var.environment
    ManagedBy   = "Packer"
  }
}

build {
  sources = ["source.amazon-ebs.app"]

  provisioner "shell" {
    inline = [
      "sudo dnf update -y",
      "sudo dnf install -y python3 python3-pip python3-devel mariadb105 gcc jq amazon-cloudwatch-agent",
      "sudo pip3 install flask gunicorn pymysql boto3 cryptography --quiet",
      "sudo useradd -r -s /bin/false appuser",
      "sudo mkdir -p /opt/app /var/log/app",
      "sudo chown appuser:appuser /opt/app /var/log/app"
    ]
  }

  provisioner "file" {
    source      = "../terraform/scripts/app.py"
    destination = "/tmp/app.py"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/app.py /opt/app/app.py",
      "sudo chown appuser:appuser /opt/app/app.py"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
