terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  project       = "provesi-asr"
  instance_type = "t2.micro" # súbelo a t3.small/t3.medium si se queda corto
  repo_url      = "https://github.com/dvargasl2/provesi-sprint4.git" # TU REPO
  branch        = "main"
}

# ================= VPC / SUBNET / AMI =================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ================= SECURITY GROUP =================

resource "aws_security_group" "sg" {
  name        = "provesi-sg"
  description = "Puertos para microservicios, DBs, Kong y SSH"
  vpc_id      = data.aws_vpc.default.id

  # SSH (solo lab)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kong proxy
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kong admin / ms-orders
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-trace
  ingress {
    from_port   = 8002
    to_port     = 8002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-inventory
  ingress {
    from_port   = 8003
    to_port     = 8003
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-order-detail
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # locust
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-security-guard (Spring Boot)
  ingress {
    from_port   = 8090
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kong SSL
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DB compartida (solo para lab)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "provesi-sg"
    Project   = local.project
    ManagedBy = "Terraform"
  }
}

# ================= BASE DE DATOS COMPARTIDA (Postgres) =================

resource "aws_instance" "shared_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y postgresql postgresql-contrib
    sudo -u postgres psql -c "CREATE USER shared_user WITH PASSWORD 'sharedPass';"
    sudo -u postgres createdb -O shared_user shared_db
    echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/*/main/postgresql.conf
    systemctl restart postgresql
  EOF

  tags = {
    Name    = "provesi-db-shared"
    Project = local.project
    Role    = "db-shared"
  }
}

# ================= MICROSERVICIOS DJANGO/PYTHON =================

resource "aws_instance" "orders" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-orders
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    nohup python manage.py migrate >/tmp/ms-orders-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8001 >/tmp/ms-orders.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-ms-orders"
    Project = local.project
    Role    = "orders"
  }
}

resource "aws_instance" "trace" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-trace
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    nohup python manage.py migrate >/tmp/ms-trace-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8002 >/tmp/ms-trace.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-ms-trace"
    Project = local.project
    Role    = "trace"
  }
}

resource "aws_instance" "inventory" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-inventory
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    nohup python manage.py migrate >/tmp/ms-inventory-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8003 >/tmp/ms-inventory.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-ms-inventory"
    Project = local.project
    Role    = "inventory"
  }
}

resource "aws_instance" "order_detail" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-order-detail
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    nohup python manage.py migrate >/tmp/ms-order-detail-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8080 >/tmp/ms-order-detail.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-ms-order-detail"
    Project = local.project
    Role    = "order-detail"
  }
}

# ================= GUARDIA (SPRING BOOT) =================

resource "aws_instance" "guard" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y git maven openjdk-17-jdk
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-security-guard
    mvn -q -DskipTests package
    nohup mvn spring-boot:run >/tmp/ms-security-guard.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-ms-guard"
    Project = local.project
    Role    = "guard"
  }
}

# ================= KONG (API GATEWAY) =================

resource "aws_instance" "kong" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    mkdir -p /home/ubuntu/kong
    cat <<EOK > /home/ubuntu/kong/kong.yml
_format_version: "3.0"
services:
- name: security-guard
  url: http://${aws_instance.guard.private_ip}:8090
  routes:
  - name: guard-orders-full
    methods: [ "GET" ]
    paths:
      - "~^/orders/\\d+/full$"
    strip_path: false
EOK
    docker run --name kong --network host \
      -e KONG_DATABASE=off \
      -e KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml \
      -e KONG_PROXY_LISTEN=0.0.0.0:8000 \
      -e KONG_PROXY_LISTEN_SSL=0.0.0.0:8443 ssl \
      -e KONG_ADMIN_LISTEN=0.0.0.0:8001 \
      -v /home/ubuntu/kong/kong.yml:/usr/local/kong/declarative/kong.yml:ro \
      -d kong:3.6
  EOF

  tags = {
    Name    = "provesi-kong"
    Project = local.project
    Role    = "kong"
  }
}

# ================= LOCUST =================

resource "aws_instance" "locust" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4
    pip3 install --upgrade pip
    pip3 install -r requirements.txt
    nohup locust -f locustfile.py --host http://${aws_instance.order_detail.private_ip}:8080 >/tmp/locust.log 2>&1 &
  EOF

  tags = {
    Name    = "provesi-locust"
    Project = local.project
    Role    = "locust"
  }
}

# ================= OUTPUTS =================

output "orders_public_ip"       { value = aws_instance.orders.public_ip }
output "trace_public_ip"        { value = aws_instance.trace.public_ip }
output "inventory_public_ip"    { value = aws_instance.inventory.public_ip }
output "order_detail_public_ip" { value = aws_instance.order_detail.public_ip }
output "guard_public_ip"        { value = aws_instance.guard.public_ip }
output "kong_public_ip"         { value = aws_instance.kong.public_ip }
output "locust_public_ip"       { value = aws_instance.locust.public_ip }
output "shared_db_public_ip"    { value = aws_instance.shared_db.public_ip }

output "ssh_orders"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.orders.public_dns}" }
output "ssh_trace"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.trace.public_dns}" }
output "ssh_inventory"     { value = "ssh -i <key.pem> ubuntu@${aws_instance.inventory.public_dns}" }
output "ssh_order_detail"  { value = "ssh -i <key.pem> ubuntu@${aws_instance.order_detail.public_dns}" }
output "ssh_guard"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.guard.public_dns}" }
output "ssh_kong"          { value = "ssh -i <key.pem> ubuntu@${aws_instance.kong.public_dns}" }
output "ssh_locust"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.locust.public_dns}" }
output "ssh_shared_db"     { value = "ssh -i <key.pem> ubuntu@${aws_instance.shared_db.public_dns}" }
