# ADR 001 — YuNet y SFace mediante OpenCV DNN

Estado: elegido para la prueba técnica, sujeto a evaluación real. Consulta 2026-10-21.

| Opción | Procedencia y licencia | Decisión |
|---|---|---|
| ML Kit Face Detection | SDK Google; detección y landmarks; no identidad | No basta para reconocimiento; no incorporado |
| MobileFaceNet de foamliu | Código Apache-2.0; una licencia de repo no demuestra por sí sola alcance de todos los pesos/datasets | No descargar pesos para esta prueba |
| InsightFace/ArcFace | Código MIT; modelos preentrenados publicados con restricciones de uso no comercial/investigación | No incorporar al producto comercial por defecto |
| OpenCV Zoo YuNet + SFace | Cada directorio tiene licencia específica; README de SFace declara todos sus archivos Apache-2.0 | Elegido; alineación y motor nativos disponibles en Android |

Fuentes primarias:
- https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet (YuNet, MIT, autor Shiqi Yu).
- https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface (SFace contribuido por Yaoyao Zhong, conversión ONNX por Chengrui Wang).
- https://raw.githubusercontent.com/opencv/opencv_zoo/main/models/face_recognition_sface/README.md (sección License: todos los archivos del directorio).
- https://github.com/zhongyy/SFace (trabajo original).
- https://github.com/foamliu/MobileFaceNet
- https://github.com/deepinsight/insightface (sección License).
- https://developers.google.com/ml-kit/vision/face-detection/android
- https://docs.opencv.org/4.x/d0/dd4/tutorial_dnn_face.html

No se deduce la licencia de pesos de la raíz: se usa la declaración específica del directorio de modelos. Se incluyen copias completas de ambas licencias en assets/models y atribuciones en NOTICE.txt. Apache-2.0/MIT permiten uso comercial bajo sus condiciones de conservación de avisos/licencias. No se ha auditado de forma independiente la cadena de derechos de datos de entrenamiento ni hay garantía universal de derechos de terceros; T14 revisa distribución y avisos antes de publicar.

## Artefactos instalados

- YuNet face_detection_yunet_2023mar.onnx, 232589 bytes, ONNX float, SHA256 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4. Entrada BGR con dimensiones ajustadas al bitmap; salida filas de 15 floats (caja, 5 landmarks, score). Umbral detector 0.85/NMS 0.3.
- SFace face_recognition_sface_2021dec.onnx, 38696353 bytes, ONNX float, SHA256 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79. Alineación cinco puntos a 112×112 BGR; FaceRecognizerSF.feature convierte a RGB, sin dividir por 255 ni restar 127.5; embedding 128 dimensiones; normalización L2 explícita.
- Motor org.opencv:opencv:4.12.0, CPU DNN por defecto. No usar TFLite con estos ONNX. La publicación oficial incluye Java y bibliotecas nativas Android.

Las descargas se fijan por digest de contenido incluso si cambia la rama upstream. El runtime verifica ambos digests antes de cargar la copia privada no incluida en backup.

No trasladar métricas de LFW a este producto. El umbral inicial coseno 0.363 proviene del tutorial OpenCV; ajuste interno en Matching.THRESHOLD tras T10. Falsos positivos/negativos por edad, pose, luz, oclusiones y tamaño son posibles.

Actualización R15/0.2.1: detector con dos escalas (resolución de análisis y lado máximo 960) y fusión de cajas/landmarks reproyectados. Score YuNet 0.65 sólo en referencia confirmada manualmente; análisis de álbum mantiene 0.85. Los pesos, alineación SFace, normalización y comparación coseno se conservan. El nuevo score de referencia requiere reevaluación con fotos reales y puede proponer caras espurias; no se presenta como certeza. Ver plan R15 y validación V11.
