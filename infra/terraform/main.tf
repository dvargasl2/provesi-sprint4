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

locals {
  project       = "provesi-asr"
  instance_type = "t2.micro" # sube a t3.medium si necesitas más RAM
  repo_url      = "https://github.com/dvargasl2/provesi-sprint4.git"
  branch        = "main"
  zone_name     = "provesi.local"
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

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ================= Security Group =================
resource "aws_security_group" "sg" {
  name        = "provesi-sg"
  description = "Puertos para microservicios, DB, Kong y SSH"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kong HTTP
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-orders
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

  # Locust UI
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Guard
  ingress {
    from_port   = 8090
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kong HTTPS
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Postgres (DB compartida)
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

# ================= DB compartida =================
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

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-shared"
    Project = local.project
    Role    = "db-shared"
  }
}

# ================= ms-orders =================
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
    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" orders_service/settings.py || true    
    nohup python manage.py migrate >/tmp/ms-orders-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8001 >/tmp/ms-orders.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-orders"
    Project = local.project
    Role    = "orders"
  }
}

# ================= ms-trace =================
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
    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" trace_service/settings.py || true
    nohup python manage.py migrate >/tmp/ms-trace-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8002 >/tmp/ms-trace.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-trace"
    Project = local.project
    Role    = "trace"
  }
}

# ================= ms-inventory =================
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
    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" inventory_service/settings.py || true
    nohup python manage.py migrate >/tmp/ms-inventory-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8003 >/tmp/ms-inventory.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-inventory"
    Project = local.project
    Role    = "inventory"
  }
}

# ================= ms-order-detail =================
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

    # Variables para hablarle a los otros servicios por IP privada
    export ORDERS_BASE_URL="http://${aws_instance.orders.private_ip}:8001"
    export TRACE_BASE_URL="http://${aws_instance.trace.private_ip}:8002"
    export INVENTORY_BASE_URL="http://${aws_instance.inventory.private_ip}:8003"
    export EXTERNAL_TIMEOUT="1.5"

    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*']/" order_detail_service/settings.py || true

    nohup python manage.py migrate >/tmp/ms-order-detail-migrate.log 2>&1 &
    nohup python manage.py runserver 0.0.0.0:8080 >/tmp/ms-order-detail.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-order-detail"
    Project = local.project
    Role    = "order-detail"
  }
}

# ================= ms-security-guard (Spring Boot) =================
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

    # Variables de entorno para Auth0 y microservicios
    export AUTH0_ISSUER="https://dev-yflhyvs1wshg0ugh.us.auth0.com/"
    export AUTH0_AUDIENCE="https://provesi.orders.api"
    export ORDERS_BASE_URL="http://${aws_instance.orders.private_ip}:8001"
    export ORDER_DETAIL_BASE_URL="http://${aws_instance.order_detail.private_ip}:8080"

    mvn -q -DskipTests package

    # Usamos spring-boot:run para evitar problemas de manifest en el jar
    nohup mvn spring-boot:run >/tmp/ms-security-guard.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-guard"
    Project = local.project
    Role    = "guard"
  }
}

# ================= Kong (API Gateway) =================
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
      - "/orders/"
    strip_path: false
EOK

    docker run --name kong --network host \
      -e KONG_DATABASE=off \
      -e KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml \
      -e KONG_PROXY_LISTEN=0.0.0.0:8000 \
      -e KONG_PROXY_LISTEN_SSL="0.0.0.0:8443 ssl" \
      -e KONG_ADMIN_LISTEN=0.0.0.0:8001 \
      -v /home/ubuntu/kong/kong.yml:/usr/local/kong/declarative/kong.yml:ro \
      -d kong:3.6
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-kong"
    Project = local.project
    Role    = "kong"
  }
}

# ================= Locust =================
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
    pip3 install -r requirements.txt || true
    pip3 install locust
    # Locust va contra Kong (gateway)
    nohup locust -f locustfile.py --host http://${aws_instance.kong.private_ip}:8000 >/tmp/locust.log 2>&1 &
  EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-locust"
    Project = local.project
    Role    = "locust"
  }
}

# =============== Outputs ===============
output "shared_db_public_ip"    { value = aws_instance.shared_db.public_ip }
output "orders_public_ip"       { value = aws_instance.orders.public_ip }
output "trace_public_ip"        { value = aws_instance.trace.public_ip }
output "inventory_public_ip"    { value = aws_instance.inventory.public_ip }
output "order_detail_public_ip" { value = aws_instance.order_detail.public_ip }
output "guard_public_ip"        { value = aws_instance.guard.public_ip }
output "kong_public_ip"         { value = aws_instance.kong.public_ip }
output "locust_public_ip"       { value = aws_instance.locust.public_ip }

output "ssh_shared_db"    { value = "ssh -i <key.pem> ubuntu@${aws_instance.shared_db.public_dns}" }
output "ssh_orders"       { value = "ssh -i <key.pem> ubuntu@${aws_instance.orders.public_dns}" }
output "ssh_trace"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.trace.public_dns}" }
output "ssh_inventory"    { value = "ssh -i <key.pem> ubuntu@${aws_instance.inventory.public_dns}" }
output "ssh_order_detail" { value = "ssh -i <key.pem> ubuntu@${aws_instance.order_detail.public_dns}" }
output "ssh_guard"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.guard.public_dns}" }
output "ssh_kong"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.kong.public_dns}" }
output "ssh_locust"       { value = "ssh -i <key.pem> ubuntu@${aws_instance.locust.public_dns}" }