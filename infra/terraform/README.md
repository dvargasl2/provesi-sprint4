# Terraform - despliegue mínimo en AWS

Este módulo crea:
- 1 instancia EC2 Amazon Linux 2023
- Security Group con puertos para ms-orders (8001), ms-order-detail (8080), Locust (8089), ms-security-guard (8090) y Kong (8000/8443 proxy, 8001 admin)
- (Opcional) key pair si entregas la clave pública

> Nota: `t2.micro` tiene ~1 GB RAM. Si necesitas 4 GB usa `t3.medium` o similar cambiando `instance_type`.

## Requisitos
- Terraform 1.6+
- Credenciales AWS configuradas (`AWS_PROFILE`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, etc.)
- VPC y subred pública existentes (entregas `vpc_id` y `subnet_id`)

## Uso rápido
```bash
cd infra/terraform
terraform init

terraform apply \
  -var "vpc_id=vpc-xxxxxxxx" \
  -var "subnet_id=subnet-xxxxxxxx" \
  -var "key_pair_name=mi-key" \
  -var "create_key_pair=false" \
  -var "repo_url=https://github.com/<tu-org>/provesi-sprint4.git" \
  -var "checkout_branch=main"
```

Variables importantes (`variables.tf`):
- `instance_type`: default `t2.micro` (cámbialo si requieres 4 GB, ej. `t3.medium`)
- `allowed_cidrs`: default `["0.0.0.0/0"]`
- `allowed_app_ports`: default `[8000, 8001, 8080, 8089, 8090, 8443]`
- `repo_url`, `checkout_branch`: para clonar el repo automáticamente
- `create_key_pair` + `public_key`: crea un key pair administrado por Terraform si lo necesitas

## Qué deja listo el user-data
- Instala Docker, git y pip.
- Instala Java 17 (amazon-corretto) y Maven (`maven`) para ejecutar el guard.
- Clona el repo (si `repo_url` no está vacío).
- Crea unit file de systemd para `ms-security-guard` (requiere Java 17/Maven wrapper en la instancia).
- Genera config DB-less de Kong y unit file para levantarlo en Docker (ruta proxy 8000 hacia `ms-security-guard`).
- No se habilita por defecto el servicio; actívalo manualmente cuando tengas configurados los secretos de JWT (Auth0).

## Outputs
- `instance_public_ip`
- `public_dns`
- `ssh_command`
