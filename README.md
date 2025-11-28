# 1. Prerrequisitos

- Python 3.9+
- `pip`
- Puertos libres: `8001`, `8080`, `8089`
- Entorno virtual creado y dependencias instaladas:

bash
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 2. Levantar microservicios
   
En una primera terminal:

cd C:\Users\samue\provesi-sprint4
.\venv\Scripts\Activate.ps1

cd .\ms-orders
python manage.py migrate
python manage.py runserver 0.0.0.0:8001


Endpoints útiles para probar:

http://localhost:8001/orders/1

http://localhost:8001/trace?order_id=1

http://localhost:8001/inventory?order_id=1

# 2.1. Levantar ms-order-detail (puerto 8080)

En una segunda terminal:

cd C:\Users\samue\provesi-sprint4
.\venv\Scripts\Activate.ps1

cd .\ms-order-detail
python manage.py migrate
python manage.py runserver 0.0.0.0:8080


Probar el endpoint principal del experimento:

http://localhost:8080/orders/1/full


Debe devolver un JSON con tres secciones: order, trace e inventory.

# 3. Correr las pruebas de carga con Locust

En una tercera terminal:

cd C:\Users\samue\provesi-sprint4
.\venv\Scripts\Activate.ps1

locust -f .\locustfile.py --host http://localhost:8080


Luego abre en el navegador:

http://localhost:8089

# 3.2. Levantar ms-security-guard (Spring Boot, puerto 8090)

En una terminal con Java 17 y Maven:

```
cd ms-security-guard
mvn spring-boot:run
```

Variables de entorno clave:

- `ORDERS_BASE_URL` (default `http://localhost:8001`)
- `ORDER_DETAIL_BASE_URL` (default `http://localhost:8080`)
- `AUTH0_ISSUER`, `AUTH0_AUDIENCE`, `AUTH0_JWKS_URI` para validar JWT
- `VENDOR_ID_CLAIM` para extraer el vendor del token (default `vendorId`)

Punto de entrada protegido: `GET http://localhost:8090/orders/{id}/full`

Solo si el JWT pertenece al dueño del pedido (según `ms-orders`) el guard reenvía la petición al agregador y devuelve su respuesta; de lo contrario responde 403.
