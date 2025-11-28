terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Única variable: key pair para SSH
variable "key_name" {
  description = "Nombre del keypair de AWS para SSH"
  type        = string
}

locals {
  project       = "provesi-asr"
  instance_type = "t2.micro"       # cambia a t3.small/t3.medium si quieres más RAM
  repo_url      = "https://github.com/tu-org/provesi-sprint4.git" # ajusta a tu repo
  branch        = "main"
}

# VPC y subred por defecto
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# AMI Ubuntu 24.04
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*24.04-amd64-server-*"]
  }
}

# Security group compartido (puertos de todos los microservicios + Kong opcional)
resource "aws_security_group" "sg" {
  name        = "provesi-sg"
  description = "Puertos para microservicios y SSH"

  ingress { from_port = 22   to_port = 22   protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8000 to_port = 8000 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # Kong proxy opcional
  ingress { from_port = 8001 to_port = 8001 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # ms-orders
  ingress { from_port = 8002 to_port = 8002 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # ms-trace
  ingress { from_port = 8003 to_port = 8003 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # ms-inventory
  ingress { from_port = 8080 to_port = 8080 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # ms-order-detail
  ingress { from_port = 8089 to_port = 8089 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # locust opcional
  ingress { from_port = 8090 to_port = 8090 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # ms-security-guard
  ingress { from_port = 8443 to_port = 8443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # Kong SSL opcional
  ingress { from_port = 5432 to_port = 5436 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] } # bases de datos

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

# Template común para user_data Python (Django)
locals {
  python_user_data = <<-EOPY
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/${1}
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    nohup python manage.py migrate >/tmp/${1}-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:${2} >/tmp/${1}.log 2>&1 &
  EOPY
}

# Template para el guard (Java/Maven)
locals {
  guard_user_data = <<-EOGUARD
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y git docker.io maven openjdk-17-jdk
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    mkdir -p /labs
    cd /labs
    git clone ${local.repo_url} provesi-sprint4 || true
    cd provesi-sprint4/ms-security-guard
    mvn -q -DskipTests package
    nohup mvn spring-boot:run >/tmp/ms-security-guard.log 2>&1 &
  EOGUARD
}

# ms-orders (puerto 8001)
resource "aws_instance" "orders" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(local.python_user_data, "${1}", "ms-orders")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-orders"
    Project = local.project
    Role    = "orders"
  }
}

# ms-trace (puerto 8002)
resource "aws_instance" "trace" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(local.python_user_data, "${1}", "ms-trace")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-trace"
    Project = local.project
    Role    = "trace"
  }
}

# ms-inventory (puerto 8003)
resource "aws_instance" "inventory" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(local.python_user_data, "${1}", "ms-inventory")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-inventory"
    Project = local.project
    Role    = "inventory"
  }
}

# ms-order-detail (puerto 8080)
resource "aws_instance" "order_detail" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(local.python_user_data, "${1}", "ms-order-detail")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-order-detail"
    Project = local.project
    Role    = "order-detail"
  }
}

# Bases de datos (PostgreSQL) por microservicio
locals {
  db_user_data = <<-EODB
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y postgresql postgresql-contrib
    sudo -u postgres psql -c "CREATE USER ${1} WITH PASSWORD '${2}';"
    sudo -u postgres createdb -O ${1} ${3}
    echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/*/main/postgresql.conf
    echo "max_connections=500" | sudo tee -a /etc/postgresql/*/main/postgresql.conf
    systemctl restart postgresql
  EODB
}

resource "aws_instance" "orders_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(replace(replace(local.db_user_data, "${1}", "orders_user"), "${2}", "ordersPass"), "${3}", "orders_db")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-orders"
    Project = local.project
    Role    = "db-orders"
  }
}

resource "aws_instance" "trace_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(replace(replace(local.db_user_data, "${1}", "trace_user"), "${2}", "tracePass"), "${3}", "trace_db")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-trace"
    Project = local.project
    Role    = "db-trace"
  }
}

resource "aws_instance" "inventory_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(replace(replace(local.db_user_data, "${1}", "inventory_user"), "${2}", "inventoryPass"), "${3}", "inventory_db")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-inventory"
    Project = local.project
    Role    = "db-inventory"
  }
}

resource "aws_instance" "order_detail_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = replace(replace(replace(local.db_user_data, "${1}", "detail_user"), "${2}", "detailPass"), "${3}", "detail_db")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-order-detail"
    Project = local.project
    Role    = "db-order-detail"
  }
}

# ms-security-guard (puerto 8090)
resource "aws_instance" "guard" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = local.guard_user_data
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-guard"
    Project = local.project
    Role    = "guard"
  }
}

# Kong (API Gateway) - Docker DB-less
locals {
  kong_user_data = <<-EOKONG
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    mkdir -p /home/ubuntu/kong
    cat <<'EOF' > /home/ubuntu/kong/kong.yml
_format_version: "3.0"
services:
- name: security-guard
  url: http://YOUR_GUARD_IP:8090
  routes:
  - name: guard-orders-full
    methods: [ "GET" ]
    paths:
      - "~^/orders/\\d+/full$"
    strip_path: false
EOF
    docker run --rm --name kong --network host \
      -e KONG_DATABASE=off \
      -e KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml \
      -e KONG_PROXY_LISTEN=0.0.0.0:8000 \
      -e KONG_PROXY_LISTEN_SSL=0.0.0.0:8443 ssl \
      -e KONG_ADMIN_LISTEN=0.0.0.0:8001 \
      -v /home/ubuntu/kong/kong.yml:/usr/local/kong/declarative/kong.yml:ro \
      -d kong:3.6
  EOKONG
}

resource "aws_instance" "kong" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = local.kong_user_data
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-kong"
    Project = local.project
    Role    = "kong"
  }
}

# Locust (puerto 8089) opcional para pruebas de carga
locals {
  locust_user_data = <<-EOLOC
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
    nohup locust -f locustfile.py --host http://localhost:8080 >/tmp/locust.log 2>&1 &
  EOLOC
}

resource "aws_instance" "locust" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  user_data                   = local.locust_user_data
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-locust"
    Project = local.project
    Role    = "locust"
  }
}

# Outputs: IPs de cada servicio
output "orders_public_ip"       { value = aws_instance.orders.public_ip }
output "trace_public_ip"        { value = aws_instance.trace.public_ip }
output "inventory_public_ip"    { value = aws_instance.inventory.public_ip }
output "order_detail_public_ip" { value = aws_instance.order_detail.public_ip }
output "guard_public_ip"        { value = aws_instance.guard.public_ip }
output "kong_public_ip"         { value = aws_instance.kong.public_ip }
output "locust_public_ip"       { value = aws_instance.locust.public_ip }
output "orders_db_public_ip"    { value = aws_instance.orders_db.public_ip }
output "trace_db_public_ip"     { value = aws_instance.trace_db.public_ip }
output "inventory_db_public_ip" { value = aws_instance.inventory_db.public_ip }
output "order_detail_db_public_ip" { value = aws_instance.order_detail_db.public_ip }

output "ssh_orders"       { value = "ssh -i <key.pem> ubuntu@${aws_instance.orders.public_dns}" }
output "ssh_trace"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.trace.public_dns}" }
output "ssh_inventory"    { value = "ssh -i <key.pem> ubuntu@${aws_instance.inventory.public_dns}" }
output "ssh_order_detail" { value = "ssh -i <key.pem> ubuntu@${aws_instance.order_detail.public_dns}" }
output "ssh_guard"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.guard.public_dns}" }
output "ssh_kong"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.kong.public_dns}" }
output "ssh_locust"       { value = "ssh -i <key.pem> ubuntu@${aws_instance.locust.public_dns}" }
output "ssh_orders_db"    { value = "ssh -i <key.pem> ubuntu@${aws_instance.orders_db.public_dns}" }
output "ssh_trace_db"     { value = "ssh -i <key.pem> ubuntu@${aws_instance.trace_db.public_dns}" }
output "ssh_inventory_db" { value = "ssh -i <key.pem> ubuntu@${aws_instance.inventory_db.public_dns}" }
output "ssh_order_detail_db" { value = "ssh -i <key.pem> ubuntu@${aws_instance.order_detail_db.public_dns}" }
