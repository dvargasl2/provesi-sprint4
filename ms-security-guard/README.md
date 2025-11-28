# ms-security-guard

Microservicio guardia de seguridad (Spring Boot) que protege el endpoint `/orders/{id}/full` frente a elevación de privilegios. Actúa como un BFF/API Gateway especializado: valida el JWT, verifica que el pedido pertenece al vendedor y solo entonces reenvía la petición al agregador de detalle.

## Cómo ejecutarlo local

```bash
cd ms-security-guard
mvn spring-boot:run
```

Variables importantes (todas tienen defaults pensados para el entorno actual):

- `ORDERS_BASE_URL` (default `http://localhost:8001`)
- `ORDER_DETAIL_BASE_URL` (default `http://localhost:8080`)
- `AUTH0_ISSUER`, `AUTH0_AUDIENCE`, `AUTH0_JWKS_URI` para validar el JWT.
- `VENDOR_ID_CLAIM` (default `vendorId`) indica de qué claim se extrae el id del vendedor en el token.
- `HTTP_CONNECT_TIMEOUT`, `HTTP_READ_TIMEOUT` (default `2s`) para asegurar tiempos < 5s en solicitudes válidas.

El servicio expone `GET /orders/{id}/full` (puerto 8090 por defecto).

## Docker (Service instance per Container)

```bash
cd ms-security-guard
docker build -t ms-security-guard .
docker run -p 8090:8090 \
  -e ORDERS_BASE_URL=http://ms-orders:8001 \
  -e ORDER_DETAIL_BASE_URL=http://ms-order-detail:8080 \
  -e AUTH0_ISSUER=https://<tu-dominio>.us.auth0.com/ \
  -e AUTH0_AUDIENCE=orders-api \
  ms-security-guard
```

## Arquitectura y patrones usados

- **Deployment – Service instance per Container:** el guard corre en su propio contenedor Java/Spring Boot.
- **Communication – Remote Procedure Invocation (REST):** expone HTTP/REST y se comunica con ms-orders y ms-order-detail por REST interno.
- **External API – API Gateway / BFF:** único punto público para `/orders/{id}/full`; centraliza autenticación/autorización y reenvía solo si pasa la validación.
- **Service discovery – Server-side discovery:** el cliente solo conoce al guard; las URLs internas hacia orders y order-detail se configuran en variables de entorno.
- **Data management – API Composition + Database per Service:** la información de negocio sigue viviendo en sus servicios; el guard no persiste datos, solo compone/valida respuestas remotas.

## Flujo de autorización

1. Extrae `vendorId` del JWT (`VENDOR_ID_CLAIM` o `sub` como fallback).
2. Llama a `ms-orders /orders/{id}` para conocer el dueño (`ownerVendorId`/`vendorId`/`vendor_id`; como último recurso usa `customer_name`).
3. Si no coincide con el vendedor autenticado → `403`.
4. Si coincide → llama al agregador `ms-order-detail /orders/{id}/full` y devuelve la respuesta tal cual.

Esto cumple el ASR: 100% de intentos de ver pedidos ajenos se bloquean con 403, manteniendo tiempos bajo 5s para accesos válidos (timeouts configurados a 2s por backend).
