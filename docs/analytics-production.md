# API de producción de Halladin

Base: `https://halladin.cloud`. Contrato consultado el 29-10-2026: [OpenAPI](https://halladin.cloud/docs-json), versión 1.1.0; [Swagger](https://halladin.cloud/docs).

Desde la raíz del repositorio:

```sh
./tools/flutter.sh run --dart-define=ANALYTICS_API_URL=https://halladin.cloud
./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
./tools/flutter.sh build ios --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

La firma Android y los perfiles iOS se configuran localmente. No se incluye ninguna credencial de servidor. `String.fromEnvironment` aplica la URL en compilación; reiniciar o hacer hot reload no cambia un binario ya compilado. Sin URL no hay transporte y la búsqueda local sigue disponible. El argumento explícito tiene prioridad sobre el `.env` que carga el helper. VS Code usa el mismo argumento de producción.

`HttpAnalyticsTransport` exige una base HTTPS sin ruta, query, credenciales ni fragmento. Sólo admite HTTP de loopback/emulador en debug. Resuelve rutas absolutas, por lo que no debe configurarse `/v1` en la base:

| Operación | Método y ruta | Cuerpo / confirmación HTTP 200 |
|---|---|---|
| Registro | `POST /v1/analytics/installations` | `installationId` / `registered: true` |
| Lote | `POST /v1/analytics/events/batch` | `installationId`, `events` (hasta 50) / `acceptedEventIds`, `rejectedIndices` |
| Revocación | `DELETE /v1/analytics/installations/{id}` | Sin cuerpo / `deleted: true` |

Las tres operaciones usan `Content-Type: application/json` y `Authorization: Bearer <token de instalación>`. La app ya genera UUIDv4 y 32 bytes con `Random.secure`, codificados en 64 caracteres hexadecimales. El token se conserva en `flutter_secure_storage`, fuera de SQLite. No se usa `ADMIN_TOKEN` ni PostgreSQL.

Se conserva el servicio existente: consentimiento explícito, captura desactivada al revocar, cola SQLite persistente, deduplicación por UUID y backoff con jitter. Una respuesta HTTP correcta no vacía el lote: sólo se eliminan sus eventos incluidos en `acceptedEventIds`. Errores HTTP, desconexión y respuestas inválidas dejan los eventos pendientes. Se mantienen los límites de minimización existentes (30 días / 5000 eventos) y el vaciado local al revocar, independientes del ACK. La app funciona sin red y los payloads cerrados excluyen fotos, nombres, rutas y datos personales.

## Validación reproducible

```sh
./tools/flutter.sh analyze
./tools/flutter.sh test --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

`analytics_transport_test.dart` prueba el transporte HTTP real contra un servidor local con datos sintéticos: rutas y cabeceras, registro, ACK parcial, reintento con el mismo UUID, borrado y conservación ante 401/429/500 y ACK inválido. Las suites existentes cubren consentimiento, cola offline persistente, deduplicación, revocación y reactivación. Las pruebas locales no envían eventos a producción; la consulta del contrato sólo lee documentación pública.

Resultado del 29-10-2026: análisis estático sin incidencias y 69 pruebas aprobadas con la URL de producción definida. La suite se ejecutó con `--concurrency=1` tras liberar intermediarios Android regenerables por falta de espacio. No se generó una nueva build de tienda ni se realizaron escrituras en producción.
