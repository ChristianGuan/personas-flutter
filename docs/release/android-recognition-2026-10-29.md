# Android 0.9.2 (17) — Reconocimiento de dos vistas

El motor usa el recorte alineado y su reflejo para construir un único descriptor por cara. Mantiene el umbral automático de 0,50 y el acceso a «Por revisar». Decisión, resultados y límites: [ADR012](../decisions/012-reconocimiento-dos-vistas.md).

## Compilación

Desde la raíz de este repositorio, con Flutter y firma configurados localmente:

```sh
./tools/flutter.sh build appbundle --release --dart-define=ANALYTICS_API_URL=https://halladin.cloud
```

AAB para cargar manualmente en **Prueba interna → Crear nueva versión** de Play Console: `flutter_app/build/app/outputs/bundle/release/app-release.aab`. Número de versión 17; sustituye la 16. No se ha publicado en Play Console desde este entorno. Tras instalar la actualización, iniciar una búsqueda nueva para obtener las decisiones del motor actualizado.

Notas sugeridas:

```text
<es-419>
Mejoramos el reconocimiento de personas para recuperar más coincidencias sin reducir el umbral de aceptación. Conservamos la revisión manual de resultados y el procesamiento local de las fotos.
</es-419>
```

## Verificación

- `bundletool validate` y manifiesto: versión 0.9.2, código 17.
- Firma AAB comprobada; APK universal generado y firma comprobada con el mismo certificado de la versión 16.
- Configuración `PAGE_ALIGNMENT_16K`; comprobación ELF de 14 bibliotecas de 64 bits aprobada; `zipalign -c -P 16 -v 4` del APK aprobado.
- URL HTTPS de producción comprobada en el binario Flutter.
- 27 tests JVM, 71 tests Flutter aprobados (una prueba opt-in omitida), analizador sin incidencias y 4 tests instrumentados nativos aprobados en emulador API36/16KB. Los tests instrumentados ejecutaron el motor de la variante debug; no son una prueba funcional completa del APK firmado. Sintaxis iOS aprobada, sin ejecución iOS.
- El emulador temporal se cerró tras las pruebas; no se instaló la actualización ni se modificaron fotos en el teléfono físico. Los ejemplos AT&T/ORL permanecieron en almacenamiento temporal de QA, fuera de los recursos de la app. No se enviaron datos de pruebas a producción.

SHA-256 AAB: `eb9a8276080048a70e1c8489b9d08c9b7a9137e07cdd750831cc78250f5754a3`.

SHA-256 APK: `604bd718f7710382b0a76856d7557e1de69a89d8063f1ab8a5774344787111d8`.

Certificado SHA-256: `c0e32c9d006af4c933853fb9fa70185a5057d4242389f9572db744b8f0e55780`.

Primera búsqueda: dos inferencias SFace por rostro sin caché; puede tardar más. Se conserva la reutilización del descriptor fusionado y la salida anticipada. La mejora medida es limitada a una base controlada; falta contrastarla con el álbum del usuario y sus fotos de otras personas.
