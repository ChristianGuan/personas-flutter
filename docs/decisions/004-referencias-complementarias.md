# ADR 004 — Referencias complementarias confirmadas

El usuario reporta falsos negativos frecuentes con caras detectadas. Se revisó la implementación oficial OpenCV 4.12.0 de FaceRecognizerSF: la alineación, canales, escala y normalización del pipeline actual coinciden con su contrato. No se encontró evidencia suficiente para atribuir el fallo a un bug de preprocesamiento. Las pruebas anteriores con copias del mismo archivo eran insuficientes para evaluar cambios de apariencia.

Se reprodujo pérdida de coincidencias con distintos fotogramas del vídeo público David de OpenCV (pose/iluminación). La comparación supera o no el umbral según la referencia. La decisión es conservar el umbral 0.363 e incorporar varias referencias de la MISMA persona, siempre elegidas y confirmadas por el usuario. La foto candidata coincide si cualquier cara supera el umbral con cualquiera de los ejemplos. No se promedian caras ni se añaden automáticamente resultados al conjunto de referencias, para evitar que un falso positivo propague una identidad equivocada.

Desde una descartada se abre el selector de rostro y el usuario confirma antes de volver a buscar. El conjunto original se conserva, lo que permite comparar el antes/después. Las referencias se pueden quitar; reemplazar persona las reinicia. Fallo de lectura, cero caras o cancelación de una referencia complementaria conserva el estado válido anterior. Miniaturas a 256 px y embeddings en memoria, sin datos nuevos en disco, logs o backup. Comparación y preparación de miniaturas fuera de Main.

Riesgos: una referencia incorrecta puede mezclar personas; por eso se muestran recortes anteriores e instrucciones explícitas y se permite quitar ejemplos. Más referencias no garantizan recuperación y pueden aumentar oportunidades de falsos positivos: sigue siendo necesaria calibración real con positivos y negativos. No se retocó el modelo ni se eligió un umbral menor sólo para hacer pasar las fotos positivas.

Fuentes primarias:
- https://raw.githubusercontent.com/opencv/opencv/4.12.0/modules/objdetect/src/face_recognize.cpp
- https://docs.opencv.org/4.x/d0/dd4/tutorial_dnn_face.html
- https://github.com/opencv/opencv_extra/tree/4.x/testdata/cv/face (README: origen del material de David)

Los resultados numéricos de regresión se registran en docs/validation.md. No son una evaluación independiente ni se extrapolan a los álbumes del usuario.
