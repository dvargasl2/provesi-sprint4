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
  region = "us-east-1"
}

locals {
  project           = "provesi"
  instance_type     = "t3.medium" # ~4GB RAM (ajusta si quieres t2.micro)
  repo_url          = "https://github.com/tu-org/provesi-sprint4.git"
  checkout_branch   = "main"
  orders_port       = 8001
  order_detail_port = 8080
  guard_port        = 8090
  allowed_cidrs     = ["0.0.0.0/0"]
  allowed_ports     = [22, 8000, 8001, 8080, 8089, 8090, 8443]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
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
  owners = ["137112412989"]
}

resource "aws_security_group" "guard_sg" {
  name        = "${locals.project}-sg"
  description = "Security group for guard + Kong"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = toset(local.allowed_ports)
    content {
      description = "Port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = local.allowed_cidrs
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
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.guard_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    REPO_URL="${local.repo_url}"
    CHECKOUT_BRANCH="${local.checkout_branch}"
    ORDERS_PORT="${local.orders_port}"
    ORDER_DETAIL_PORT="${local.order_detail_port}"
    GUARD_PORT="${local.guard_port}"

    sudo yum update -y
    sudo yum install -y git docker python3-pip maven java-17-amazon-corretto
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker ec2-user
    sudo pip3 install --upgrade pip

    if [ -n "$REPO_URL" ]; then
      sudo -u ec2-user git clone "$REPO_URL" /home/ec2-user/provesi
      cd /home/ec2-user/provesi
      sudo -u ec2-user git checkout "$CHECKOUT_BRANCH" || true
    fi

    sudo -u ec2-user mkdir -p /home/ec2-user/kong
    if [ -f "/home/ec2-user/provesi/infra/kong/kong.yml" ]; then
      sudo -u ec2-user sed "s/%%GUARD_PORT%%/${GUARD_PORT}/g" /home/ec2-user/provesi/infra/kong/kong.yml > /home/ec2-user/kong/kong.yml
    else
      cat <<'EOK' | sudo -u ec2-user tee /home/ec2-user/kong/kong.yml
_format_version: "3.0"
services:
- name: security-guard
  url: http://localhost:${GUARD_PORT}
  routes:
  - name: guard-orders-full
    methods: [ "GET" ]
    paths:
      - "~^/orders/\\d+/full$"
    strip_path: false
EOK
    fi

    cat <<EOG | sudo tee /etc/systemd/system/ms-security-guard.service
[Unit]
Description=Spring Boot Security Guard
After=network.target docker.service

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/provesi/ms-security-guard
ExecStart=/bin/bash -lc "cd /home/ec2-user/provesi/ms-security-guard && mvn spring-boot:run -Dspring-boot.run.profiles=default"
Restart=on-failure
Environment=ORDERS_BASE_URL=http://localhost:${ORDERS_PORT}
Environment=ORDER_DETAIL_BASE_URL=http://localhost:${ORDER_DETAIL_PORT}
Environment=SERVER_PORT=${GUARD_PORT}

[Install]
WantedBy=multi-user.target
EOG

    cat <<'EOKONG' | sudo tee /etc/systemd/system/kong.service
[Unit]
Description=Kong API Gateway (DB-less)
After=docker.service
Requires=docker.service

[Service]
Restart=on-failure
ExecStart=/usr/bin/docker run --rm --name kong --network host \
  -e KONG_DATABASE=off \
  -e KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml \
  -e KONG_PROXY_LISTEN=0.0.0.0:8000 \
  -e KONG_PROXY_LISTEN_SSL=0.0.0.0:8443 ssl \
  -e KONG_ADMIN_LISTEN=0.0.0.0:8001 \
  -v /home/ec2-user/kong/kong.yml:/usr/local/kong/declarative/kong.yml:ro \
  kong:3.6
ExecStop=/usr/bin/docker stop kong

[Install]
WantedBy=multi-user.target
EOKONG

    sudo systemctl daemon-reload
  EOF

  tags = {
    Name    = "${locals.project}-guard-host"
    Project = locals.project
  }
}
