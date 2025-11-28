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

##############################################
# VARIABLES
##############################################

variable "key_name" {
  description = "Nombre del keypair de AWS para SSH"
  type        = string
}

##############################################
# SECURITY GROUPS
##############################################

resource "aws_security_group" "traffic_app" {
  name        = "int-traffic-app"
  description = "Allow application traffic on port 8080"

  ingress {
    description = "HTTP access for Django app"
    from_port   = 8080
    to_port     = 8080
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
    Name      = "int-traffic-app"
    ManagedBy = "Terraform"
    Project   = "int-asr-integridad"
  }
}

resource "aws_security_group" "traffic_db" {
  name        = "int-traffic-db"
  description = "Allow PostgreSQL access"

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # LAB — NO PRODUCCIÓN
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "int-traffic-db"
    ManagedBy = "Terraform"
    Project   = "int-asr-integridad"
  }
}

resource "aws_security_group" "traffic_ssh" {
  name        = "int-traffic-ssh"
  description = "Allow SSH access"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
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
    Name      = "int-traffic-ssh"
    ManagedBy = "Terraform"
    Project   = "int-asr-integridad"
  }
}

##############################################
# AMI UBUNTU
##############################################

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*24.04-amd64-server-*"]
  }
}

##############################################
# INSTANCE: DATABASE
##############################################

resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y postgresql postgresql-contrib

    sudo -u postgres psql -c "CREATE USER appuser WITH PASSWORD 'appPass';"
    sudo -u postgres createdb -O appuser appdb

    echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
    echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
    echo "max_connections=2000" | sudo tee -a /etc/postgresql/16/main/postgresql.conf

    sudo service postgresql restart
  EOT

  tags = {
    Name      = "int-db"
    Role      = "database"
    Project   = "int-asr-integridad"
    ManagedBy = "Terraform"
  }
}

##############################################
# INSTANCE: APPLICATION (Django + Gunicorn)
##############################################

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.traffic_app.id, aws_security_group.traffic_ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -eux

    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv git

    mkdir -p /labs
    cd /labs

    git clone https://github.com/dvargasl2/App-ASR-Integridad.git App-ASR-Integridad || true
    cd App-ASR-Integridad

    python3 -m venv venv
    source venv/bin/activate

    pip install --upgrade pip
    pip install -r requirements.txt

    export DATABASE_URL="postgresql://appuser:appPass@${aws_instance.database.private_ip}/appdb"
    export DJANGO_ALLOWED_HOSTS="*"

    nohup venv/bin/python3 manage.py migrate &
    nohup venv/bin/python3 manage.py runserver 0.0.0.0:8080 &
  EOT

  tags = {
    Name      = "int-app"
    Role      = "integridad-app"
    Project   = "int-asr-integridad"
    ManagedBy = "Terraform"
  }
}

##############################################
# INSTANCE: LOCUST LOAD TESTING
##############################################

resource "aws_instance" "jmeter" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.traffic_ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    set -eux

    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv

    python3 -m venv locust-venv
    source locust-venv/bin/activate
    pip install locust
  EOT

  tags = {
    Name      = "int-jmeter"
    Role      = "jmeter-client"
    Project   = "int-asr-integridad"
    ManagedBy = "Terraform"
  }
}

##############################################
# OUTPUTS
##############################################

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "db_public_ip" {
  value = aws_instance.database.public_ip
}

output "db_private_ip" {
  value = aws_instance.database.private_ip
}

output "jmeter_public_ip" {
  value = aws_instance.jmeter.public_ip
}