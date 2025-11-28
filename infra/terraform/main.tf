terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.42"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["137112412989"] # Amazon
}

resource "aws_key_pair" "default" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = var.key_pair_name
  public_key = var.public_key
}

resource "aws_security_group" "guard_sg" {
  name        = "${var.project}-sg"
  description = "Security group for security guard and related services"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  dynamic "ingress" {
    for_each = var.allowed_app_ports
    content {
      description = "App port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "guard_host" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.guard_sg.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.sh", {
    repo_url          = var.repo_url
    checkout_branch   = var.checkout_branch
    orders_port       = var.orders_port
    order_detail_port = var.order_detail_port
    guard_port        = var.guard_port
  })

  tags = {
    Name    = "${var.project}-guard-host"
    Project = var.project
  }
}

output "instance_public_ip" {
  value       = aws_instance.guard_host.public_ip
  description = "IP pública de la instancia"
}

output "ssh_command" {
  value       = "ssh -i <path-a-tu-llave.pem> ec2-user@${aws_instance.guard_host.public_dns}"
  description = "Comando SSH de referencia"
}
