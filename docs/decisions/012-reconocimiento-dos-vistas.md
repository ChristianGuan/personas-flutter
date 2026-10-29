# ADR 012 — Descriptor de dos vistas del mismo rostro

Estado: implementado para Android/iOS; validado con el modelo real en Android API 36, páginas de 16 KiB. Pendiente aceptación con el álbum del usuario.

## Problema y decisión

Hay fotos correctas en «Por revisar» y también se han comunicado coincidencias con otras personas. No se reduce el umbral: MATCH sigue en 0,50, REVIEW en [0,363; 0,50), NONE por debajo. Probar 0,45 con el descriptor anterior introdujo falsos positivos en la base de regresión.

Después de alinear una cara, SFace procesa el recorte original y su reflejo horizontal. Se normaliza cada vector, se suman y se normaliza la suma. Sólo se fusionan dos vistas de **la misma cara**; nunca personas distintas ni referencias diferentes. Una suma degenerada conserva el vector original. Se mantiene la segunda normalización previa a comparación. Android e iOS aplican la misma operación y cambian la versión de sus claves de caché para impedir reutilizar descriptores anteriores.

No cambian pesos, detector, escalas, resolución, elección de cara de referencia, máximo entre referencias ni confirmaciones manuales. No hay aprendizaje desde resultados. Los datos faciales siguen en el dispositivo. Las repeticiones reutilizan el descriptor fusionado; una cara sin caché necesita dos inferencias SFace en vez de una. No se promete el mismo tiempo de primera búsqueda.

## Evidencia y límites

Regresión interna sobre las 400 imágenes públicas AT&T/ORL descritas en ADR007: sujetos 1–20 de calibración, 21–40 de evaluación; referencias 1, 1–2 o 1–4 y consultas posteriores. OpenCV 4.12, umbral fijo 0,50 para ambos descriptores. Esta base ya se había consultado: no es una evaluación nueva ciega, no representa álbumes familiares y los protocolos no son independientes.

| Referencias | Positivos de evaluación | Aciertos anteriores | Aciertos nuevos | Falsos positivos anteriores/nuevos | Negativos |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 180 | 177 | 179 | 0 / 0 | 3420 |
| 2 | 160 | 160 | 160 | 0 / 0 | 3040 |
| 4 | 120 | 120 | 120 | 0 / 0 | 2280 |

En calibración los aciertos se conservan en 179/180, 159/160 y 120/120, con cero FP. La evaluación nativa Android coincide con los nuevos conteos del host. En el protocolo de una referencia queda un positivo en revisión. No se demuestra reducción de falsos positivos donde ambos descriptores ya tenían cero, ni se garantiza que desaparezcan las confusiones del álbum del usuario.

Validación adicional: 27 pruebas JVM; 4 instrumentadas `FilteringTest` (conteos, alias/caché parcial, contenido cambiado, EXIF y archivo grande); analizador Flutter sin incidencias; 71 pruebas Flutter aprobadas y una prueba opt-in de producción omitida. Sintaxis Objective-C++ iOS aprobada con SDK de simulador; no se ejecutó la app iOS. No se usaron fotos del usuario ni se probaron eventos contra producción.

## Reproducción

Con OpenCV Python 4.12.0.88 y numpy 2.2.6:

```sh
python3 tools/prepare_filter_qa.py --output /tmp/personas-filter-qa/android
python3 tools/evaluate_filtering.py --fixtures /tmp/personas-filter-qa/android --descriptor original --output /tmp/personas-filter-qa/baseline.json
python3 tools/evaluate_filtering.py --fixtures /tmp/personas-filter-qa/android --descriptor flip-mean --output /tmp/personas-filter-qa/improved.json
```

Crédito: AT&T Laboratories Cambridge; [base oficial y límites](https://www.cl.cam.ac.uk/research/dtg/attarchive/facedatabase.html). Las imágenes, vectores y artefactos de compilación no se versionan. Los conteos nativos son agregados; el campo histórico `previousTP/FP` de `FilteringTest` compara el descriptor actual con umbral 0,363, **no** con el descriptor anterior a este ADR. La comparación anterior/nuevo de la tabla proviene de las dos ejecuciones del host.

Para comprobar la mejora real hay que repetir la búsqueda con la versión nueva y revisar tanto fotos omitidas como personas incorrectas, usando referencias explícitas de la persona correcta. No se modifican automáticamente las decisiones de una búsqueda ya terminada.
