#!/bin/bash
set -euo pipefail

REPO_URL="${repo_url}"
CHECKOUT_BRANCH="${checkout_branch}"
ORDERS_PORT="${orders_port}"
ORDER_DETAIL_PORT="${order_detail_port}"
GUARD_PORT="${guard_port}"

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

# Preparar configuración de Kong (DB-less)
sudo -u ec2-user mkdir -p /home/ec2-user/kong
if [ -f "/home/ec2-user/provesi/infra/kong/kong.yml" ]; then
  # Sustituir placeholder del puerto del guard
  sudo -u ec2-user sed "s/%%GUARD_PORT%%/${GUARD_PORT}/g" /home/ec2-user/provesi/infra/kong/kong.yml > /home/ec2-user/kong/kong.yml
else
  cat <<EOF | sudo -u ec2-user tee /home/ec2-user/kong/kong.yml
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
EOF
fi

# Placeholder: instala dependencias de ms-orders y ms-order-detail si se desea levantar en la misma instancia
# cd /home/ec2-user/provesi && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt

cat <<EOF | sudo tee /etc/systemd/system/ms-security-guard.service
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
EOF

sudo systemctl daemon-reload
# No se habilita por defecto; activarlo manualmente tras ajustar credenciales/JWT
# sudo systemctl enable --now ms-security-guard

# Kong API Gateway (DB-less)
cat <<'EOF' | sudo tee /etc/systemd/system/kong.service
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
EOF

# No se habilita por defecto; activarlo cuando el guard esté corriendo
# sudo systemctl enable --now kong
