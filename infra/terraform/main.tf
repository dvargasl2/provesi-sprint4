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

variable "key_name" {
  description = "Nombre del keypair de AWS para SSH"
  type        = string
}

locals {
  project       = "provesi-asr"
  instance_type = "t2.micro" # sube a t3.medium si necesitas más RAM
  repo_url      = "https://github.com/tu-org/provesi-sprint4.git" # ajusta a tu repo real
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
    values = ["ubuntu/images/hvm-ssd/ubuntu-*24.04-amd64-server-*"]
  }
}

# Zona privada para self-registration DNS
resource "aws_route53_zone" "private" {
  name = local.zone_name
  vpc {
    vpc_id = data.aws_vpc.default.id
  }
}

# Role/Instance profile para que las VMs puedan registrar sus A records
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance_role" {
  name               = "provesi-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "instance_policy" {
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    actions = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.private.arn]
  }
  statement {
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "instance_policy" {
  name   = "provesi-ec2-policy"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.instance_policy.json
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "provesi-ec2-profile"
  role = aws_iam_role.instance_role.name
}

# Security group compartido
resource "aws_security_group" "sg" {
  name        = "provesi-sg"
  description = "Puertos para microservicios, DB, Kong y SSH"

  ingress { from_port = 22   to_port = 22   protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8000 to_port = 8000 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8001 to_port = 8001 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8002 to_port = 8002 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8003 to_port = 8003 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8080 to_port = 8080 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8089 to_port = 8089 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8090 to_port = 8090 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 8443 to_port = 8443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 5432 to_port = 5432 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }

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

# Snippet para registrar DNS al arranque
locals {
  dns_register = <<'EOSNIPPET'
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
ZONE_ID="${ZONE_ID_PLACEHOLDER}"
NAME="${DNS_NAME}"
IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
cat >/tmp/rr.json <<EOF
{
  "Comment": "UPSERT A record",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${NAME}",
      "Type": "A",
      "TTL": 30,
      "ResourceRecords": [{ "Value": "${IP}" }]
    }
  }]
}
EOF
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/rr.json
EOSNIPPET
}

# User-data generico para servicios Django
locals {
  python_user_data = <<'EOF'
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y python3 python3-pip python3-venv git awscli
mkdir -p /labs
cd /labs
git clone ${local.repo_url} provesi-sprint4 || true
cd provesi-sprint4/${SERVICE_DIR}
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
nohup python manage.py migrate >/tmp/${SERVICE_DIR}-migrate.log 2>&1 &
nohup python manage.py runserver 0.0.0.0:${SERVICE_PORT} >/tmp/${SERVICE_DIR}.log 2>&1 &

# Registro DNS
ZONE_ID_PLACEHOLDER=${aws_route53_zone.private.zone_id}
DNS_NAME=${DNS_NAME}
${local.dns_register}
EOF
}

# User-data para guard (Spring)
locals {
  guard_user_data = <<'EOF'
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y git maven openjdk-17-jdk awscli
mkdir -p /labs
cd /labs
git clone ${local.repo_url} provesi-sprint4 || true
cd provesi-sprint4/ms-security-guard
mvn -q -DskipTests package
nohup mvn spring-boot:run >/tmp/ms-security-guard.log 2>&1 &

# Registro DNS
ZONE_ID_PLACEHOLDER=${aws_route53_zone.private.zone_id}
DNS_NAME=${DNS_NAME}
${local.dns_register}
EOF
}

# User-data para Kong
locals {
  kong_user_data = <<'EOF'
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y docker.io awscli
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Resolver IP del guard por tag
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
GUARD_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=provesi-ms-guard" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

mkdir -p /home/ubuntu/kong
cat <<EOK > /home/ubuntu/kong/kong.yml
_format_version: "3.0"
services:
- name: security-guard
  url: http://$GUARD_IP:8090
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

# Registro DNS
ZONE_ID_PLACEHOLDER=${aws_route53_zone.private.zone_id}
DNS_NAME=${DNS_NAME}
${local.dns_register}
EOF
}

# User-data para DB compartida
locals {
  db_user_data = <<'EOF'
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y postgresql postgresql-contrib awscli
sudo -u postgres psql -c "CREATE USER shared_user WITH PASSWORD 'sharedPass';"
sudo -u postgres createdb -O shared_user shared_db
echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/*/main/postgresql.conf
systemctl restart postgresql

# Registro DNS
ZONE_ID_PLACEHOLDER=${aws_route53_zone.private.zone_id}
DNS_NAME=${DNS_NAME}
${local.dns_register}
EOF
}

# ================= INSTANCIAS =================

resource "aws_instance" "shared_db" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(local.db_user_data, "DNS_NAME", "db.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-db-shared"
    Project = local.project
    Role    = "db-shared"
  }
}

resource "aws_instance" "orders" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(replace(replace(local.python_user_data, "${SERVICE_DIR}", "ms-orders"), "${SERVICE_PORT}", "8001"), "DNS_NAME", "orders.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-orders"
    Project = local.project
    Role    = "orders"
  }
}

resource "aws_instance" "trace" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(replace(replace(local.python_user_data, "${SERVICE_DIR}", "ms-trace"), "${SERVICE_PORT}", "8002"), "DNS_NAME", "trace.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-trace"
    Project = local.project
    Role    = "trace"
  }
}

resource "aws_instance" "inventory" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(replace(replace(local.python_user_data, "${SERVICE_DIR}", "ms-inventory"), "${SERVICE_PORT}", "8003"), "DNS_NAME", "inventory.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-inventory"
    Project = local.project
    Role    = "inventory"
  }
}

resource "aws_instance" "order_detail" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(replace(replace(local.python_user_data, "${SERVICE_DIR}", "ms-order-detail"), "${SERVICE_PORT}", "8080"), "DNS_NAME", "order-detail.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-order-detail"
    Project = local.project
    Role    = "order-detail"
  }
}

resource "aws_instance" "guard" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(local.guard_user_data, "DNS_NAME", "guard.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-ms-guard"
    Project = local.project
    Role    = "guard"
  }
}

resource "aws_instance" "kong" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  user_data                   = replace(local.kong_user_data, "DNS_NAME", "kong.${local.zone_name}")
  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-kong"
    Project = local.project
    Role    = "kong"
  }
}

resource "aws_instance" "locust" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.instance_type
  key_name                    = var.key_name
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name

  user_data = <<EOF
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y python3 python3-pip git awscli
mkdir -p /labs
cd /labs
git clone ${local.repo_url} provesi-sprint4 || true
cd provesi-sprint4
pip3 install --upgrade pip
pip3 install -r requirements.txt
nohup locust -f locustfile.py --host http://${aws_instance.order_detail.private_ip}:8080 >/tmp/locust.log 2>&1 &

# Registro DNS
ZONE_ID_PLACEHOLDER=${aws_route53_zone.private.zone_id}
DNS_NAME=locust.${local.zone_name}
${local.dns_register}
EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "provesi-locust"
    Project = local.project
    Role    = "locust"
  }
}

# Outputs
output "shared_db_public_ip"    { value = aws_instance.shared_db.public_ip }
output "orders_public_ip"       { value = aws_instance.orders.public_ip }
output "trace_public_ip"        { value = aws_instance.trace.public_ip }
output "inventory_public_ip"    { value = aws_instance.inventory.public_ip }
output "order_detail_public_ip" { value = aws_instance.order_detail.public_ip }
output "guard_public_ip"        { value = aws_instance.guard.public_ip }
output "kong_public_ip"         { value = aws_instance.kong.public_ip }
output "locust_public_ip"       { value = aws_instance.locust.public_ip }

output "ssh_shared_db"     { value = "ssh -i <key.pem> ubuntu@${aws_instance.shared_db.public_dns}" }
output "ssh_orders"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.orders.public_dns}" }
output "ssh_trace"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.trace.public_dns}" }
output "ssh_inventory"     { value = "ssh -i <key.pem> ubuntu@${aws_instance.inventory.public_dns}" }
output "ssh_order_detail"  { value = "ssh -i <key.pem> ubuntu@${aws_instance.order_detail.public_dns}" }
output "ssh_guard"         { value = "ssh -i <key.pem> ubuntu@${aws_instance.guard.public_dns}" }
output "ssh_kong"          { value = "ssh -i <key.pem> ubuntu@${aws_instance.kong.public_dns}" }
output "ssh_locust"        { value = "ssh -i <key.pem> ubuntu@${aws_instance.locust.public_dns}" }
