# Emojis Unicode inline — investigación y propuesta de experimento

Estado: investigación **exploratoria**, 2026-10-08. El usuario autorizó después
una primera implementación con el fork Slug; su alcance y validación están en
[emoji-mvp.md](emoji-mvp.md). Esta comparación no cierra la arquitectura definitiva.
La arquitectura vigente sigue en
[architecture.md](architecture.md); las reglas visuales, en [ui.md](ui.md).

Objetivo: mostrar emojis junto al texto del chat conservando su Unicode original.
El diseño es portable entre GDScript, C++, Rust u otra integración nativa. xat hoy
usa Godot 3.6 del fork; esa restricción contextual no convierte Slug ni una API del
motor en parte obligatoria del modelo.

## 1. Contratos propuestos y semántica XMPP

- El cuerpo enviado, recibido y guardado conserva su secuencia Unicode. No se
  reemplaza por nombres de archivos, shortcodes, IDs privados ni caracteres PUA.
- Interpretar emoji es responsabilidad de presentación. Cambiar de artwork o
  actualizar cobertura no requiere migrar historial ni negociar un XEP.
- Copiar una selección que contiene un emoji devuelve su secuencia original;
  pegarla en otro cliente conserva su significado, aunque cambie su apariencia.
- Historial, MAM, carbons y correcciones siguen trabajando con texto. La igualdad
  exigida es de secuencias Unicode del cuerpo, no de los bytes de serialización XML.
- La búsqueda usa el cuerpo original. Equivalencias de presentación, tonos o
  nombres localizados serían índices derivados optativos, nunca reescrituras.
- Accesibilidad conserva el texto original y permite una descripción localizada
  del emoji; una imagen sin representación textual pierde información. No se
  presupone que el control actual ya exponga ese contrato a lectores de pantalla.

XMPP define `<body>` como datos de caracteres XML; su stream usa UTF-8. Los emoji
Unicode no necesitan una extensión específica. Stickers y emoji personalizados
son otro problema: pueden necesitar archivos, referencias y metadatos, por ejemplo
[XEP-0449](https://xmpp.org/extensions/xep-0449.html). Su soporte y un picker,
shortcodes o reacciones quedan fuera de este experimento.
[RFC 6121 §5.2.3](https://www.rfc-editor.org/rfc/rfc6121.html#section-5.2.3),
[RFC 6120 §11.5](https://www.rfc-editor.org/rfc/rfc6120.html#section-11.5).

## 2. Reconocimiento: secuencias, no codepoints sueltos

| Clase | Ejemplo / composición | Implicación |
|---|---|---|
| Básico | 😀, U+1F600 | Puede ser un solo escalar; la presentación por defecto depende de las propiedades Unicode. |
| Presentación | ❤️ = U+2764 U+FE0F | VS16 solicita emoji; VS15 (U+FE0E) solicita texto. No eliminar selectores indiscriminadamente. |
| Tono de piel | 👍🏽 = base + U+1F3FD | El modificador pertenece a la secuencia; no combinarlo con cualquier base. |
| ZWJ | 👩‍💻 = U+1F469 U+200D U+1F4BB | Una representación puede abarcar varios escalares y componentes. |
| Bandera regional | 🇵🇪 = U+1F1F5 U+1F1EA | Emparejar indicadores regionales no demuestra que exista artwork para la región. |
| Keycap | 1️⃣ = U+0031 U+FE0F U+20E3 | No tratar todos los dígitos, `#` o `*` como emoji por sí solos. |
| Bandera con tags | Bandera negra + tags de región + terminador | Incluir en cobertura y fallback; no todas las banderas usan indicadores regionales. |

La sintaxis y el repertorio recomendado para intercambio (RGI) están definidos
en [UTS #51](https://www.unicode.org/reports/tr51/). La tabla ilustra casos, no
sustituye sus datos oficiales.

Separar **segmentación de grafemas extendidos** de **reconocimiento de emoji**.
Un grafema no necesariamente es un emoji; una secuencia reconocida tampoco
garantiza que el pack tenga su imagen. UAX #29 ofrece límites para selección y
edición, incluyendo ZWJ e indicadores regionales. Los RGI son grafemas únicos;
no asumir lo mismo para cualquier secuencia arbitraria.
[UAX #29](https://www.unicode.org/reports/tr29/).

Fuentes para generar tablas, con versiones fijadas:

| Datos | Uso |
|---|---|
| `emoji-data.txt` del UCD | Propiedades `Emoji`, `Emoji_Presentation`, `Emoji_Modifier`, `Extended_Pictographic`, etc. |
| `emoji-variation-sequences.txt` del UCD | Pares válidos de presentación texto/emoji. |
| `emoji-sequences.txt`, `emoji-zwj-sequences.txt` | Repertorio explícito, incluyendo modificadores, banderas, keycaps y ZWJ. |
| `emoji-test.txt` | Corpus y estados fully/minimally-qualified, unqualified y component; no renderizar todos igual automáticamente. |
| `auxiliary/GraphemeBreakProperty.txt`, `GraphemeBreakTest.txt` | Propiedades y conformidad de segmentación. |

Consultar [datos Emoji](https://www.unicode.org/Public/emoji/) y
[UCD](https://www.unicode.org/Public/UCD/). Algunas releases publican estos archivos
en ubicaciones diferentes: guardar rutas exactas, versión y checksum. `latest`
sirve para explorar, no para builds reproducibles. Datos y artwork pueden tener
versiones distintas; medir explícitamente su intersección de cobertura.

[ICU BreakIterator](https://unicode-org.github.io/icu/userguide/boundaryanalysis/)
es una opción madura de segmentación;
[utf8proc](https://github.com/JuliaStrings/utf8proc) ofrece una alternativa C más
acotada. Ninguno reemplaza el mapa secuencia→artwork. Una tabla generada de
secuencias es otra opción para reconocimiento, pero no reemplaza la segmentación
general del texto. Comparar tamaño, versión Unicode y dependencias antes de elegir.

**Fallback propuesto:** distinguir secuencia conocida con arte, conocida sin arte
y no reconocida. Intentar representar el grafema completo con una fuente fallback;
si no es posible, conservar sus componentes o mostrar una indicación de ausencia,
manteniendo su Unicode para copia. El fallback de un ZWJ puede verse como varias
figuras: no prometer que expresen el mismo significado. No consumir un prefijo
conocido dejando modificadores o joiners huérfanos. Los aliases de presentación
se resuelven en el lookup, nunca modificando el cuerpo.

## 3. Comparación de renderizado

Las alternativas pueden combinarse: SVG puede ser la fuente de un atlas y una
fuente de color puede rasterizarse a una caché. GLES3 dibuja el resultado; no
interpreta por sí mismo Unicode, SVG ni tablas OpenType.

| Enfoque | Ventajas | Costes / límites | Packaging |
|---|---|---|---|
| A. Atlas raster PNG/RGBA | Resultado reproducible; lookup de secuencia completa; quads compatibles con un pipeline 2D. | VRAM proporcional a resolución; padding y filtrado; varias páginas; alternar texto/emoji puede cortar batches. | Assets + tabla de regiones/métricas; variantes de resolución o caché. |
| B. SVG rasterizado antes de empaquetar | Fuente escalable; runtime sencillo; se puede generar A. | Más etapas de build; fijar rasterizador y validar fidelidad; tamaño final depende del raster. | Sólo resultado raster en runtime, SVG y herramientas en fuentes/build si conviene. |
| B. SVG rasterizado en runtime | Tamaño ajustable a zoom/DPI; carga bajo demanda. | Parser, rasterización y caché; diferencias de soporte SVG; evitar trabajo repetido por frame. | Biblioteca y dependencias para cada plataforma; conservar licencias. |
| C. OpenType color | Cobertura y métricas de fuente; posible integración con shaping existente. | Formato y versión del stack importan; shaping, decodificación y composición son capacidades separadas. | Fuente redistribuible + stack compatible, o dependencia del sistema sin apariencia uniforme. |
| D. Outlines monocromos | Escalables, tintables; útiles para símbolos y fallback. | No recuperan los colores de artwork moderno; ZWJ/ligaduras requieren resolución de secuencias. | Fuente/outlines y renderer vectorial; verificar cobertura real. |

Para A, estimación sin compresión: `W × H × 4` bytes por página RGBA8; una página
2048² ocupa **16 MiB**, aproximadamente **21,3 MiB** con cadena completa de mipmaps.
Eso no equivale al tamaño PNG en disco. Reservar gutters/extrusión para evitar
bleeding, especialmente con mipmaps; medir nitidez a tamaño de chat y zoom.
Resoluciones múltiples aumentan disco y memoria si se cargan todas. Un atlas
facilita batching, pero no garantiza un draw call: importan orden, materiales,
clipping y cambios entre texturas de texto y emoji. Son costes a medir.

Godot 3.6 importa SVG rasterizándolo mediante NanoSVG, con soporte limitado; esa
importación no implica un renderer SVG vectorial general durante el dibujo.
[Importación de imágenes](https://docs.godotengine.org/en/3.6/tutorials/assets_pipeline/importing_images.html).

### OpenType: soporte que hay que distinguir

| Formato | Representación | Requisito de consumo |
|---|---|---|
| COLR v0 / CPAL | Capas de outlines con colores de paleta | Leer capas y componerlas; FreeType moderno dispone de renderizado de v0. |
| COLR v1 / CPAL | Paint graph con gradientes, transforms y composición | Intérprete gráfico adicional; leer las tablas en FreeType no implica render completo. |
| CBDT/CBLC | Bitmaps de color a tamaños concretos | Decodificar strikes, elegir tamaño y conservar píxeles de color. |
| sbix | Imágenes por glifo y tamaño | Soporte del decoder/build; mismas limitaciones de escala de bitmaps. |
| SVG-in-OpenType | Documentos SVG por glifo | Renderer SVG externo; FreeType ofrece integración, no un rasterizador SVG completo incorporado. |

Fuentes: especificaciones OpenType
[COLR](https://learn.microsoft.com/en-us/typography/opentype/spec/colr),
[CPAL](https://learn.microsoft.com/en-us/typography/opentype/spec/cpal),
[CBDT](https://learn.microsoft.com/en-us/typography/opentype/spec/cbdt),
[sbix](https://learn.microsoft.com/en-us/typography/opentype/spec/sbix),
[SVG](https://learn.microsoft.com/en-us/typography/opentype/spec/svg);
[FreeType: carga de glifos](https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html),
[capas y COLRv1](https://freetype.org/freetype2/docs/reference/ft2-layer_management.html).

Godot 3.6 estándar **sí tiene soporte parcial de color**: `DynamicFont` solicita
`FT_LOAD_COLOR` y convierte bitmaps BGRA a su caché de texturas. CBDT/CBLC y sbix
son rutas plausibles si su FreeType los decodifica; COLR v0 depende de que esa
versión/build produzca el bitmap compuesto. Esto no demuestra soporte de COLRv1
ni SVG-in-OpenType. Auditar también el build concreto del fork.
[Código de DynamicFont 3.6](https://github.com/godotengine/godot/blob/3.6-stable/scene/resources/dynamic_font.cpp).

Además, Godot 3 estándar documenta ausencia de shaping y ligaduras: un glifo
individual coloreado no demuestra composición de familias, tonos o banderas.
Cargar un `.ttf` no resuelve el reconocimiento/layout de secuencias.
[DynamicFont 3.6](https://docs.godotengine.org/en/3.6/classes/class_dynamicfont.html).

En Linux es habitual Noto Color Emoji (CBDT/CBLC), sujeto a instalación y stack.
Windows suele usar Segoe UI Emoji con COLR/CPAL; DirectWrite documenta capacidades
que el renderer Godot no hereda automáticamente. macOS suele usar Apple Color
Emoji con sbix/Core Text. Inspeccionar tablas de la fuente y versión del OS,
sin inferir soporte por el nombre. Las fuentes instaladas no garantizan cobertura
ni permiso de redistribución.
[Noto](https://github.com/googlefonts/noto-emoji),
[DirectWrite](https://learn.microsoft.com/en-us/windows/win32/directwrite/color-fonts),
[Apple: fuentes](https://developer.apple.com/fonts/).

### Matriz de recomendación condicional

| Si la prioridad es… | Candidato a probar primero | Condición para adoptarlo |
|---|---|---|
| Color reproducible en desktop con poca dependencia del stack de fuentes | A o B offline→A | Baseline, copia y presupuesto de atlas comprobados en el fork. |
| Muchos tamaños/DPI o arte vectorial dinámico | B runtime | Fidelidad SVG, caché y coste de rasterización aceptables. |
| Aprovechar un stack tipográfico ya capaz de shaping y color | C | Demostrar cada formato necesario y packaging en los OS objetivo. |
| Símbolos tintables o fallback | D | Cobertura suficiente; no exigir aspecto multicolor. |
| Apariencia del sistema y paquete mínimo | C con fuente del OS | Aceptar variaciones de estilo/cobertura y fallback por plataforma. |

Hipótesis para el experimento: raster es una referencia de menor incertidumbre
para evaluar layout; esto no elige atlas, renderer ni artwork para producción.

## 4. Artwork y licencias

| Fuente | Formato / estilo | Licencia | Cobertura, cadencia y distribución |
|---|---|---|---|
| [Twemoji comunitario](https://github.com/jdecked/twemoji) | SVG y PNG; estilo plano | Arte CC BY 4.0; código MIT | Continuación mantenida; README consultado declara Emoji 17 RGI. Fijar release, conservar atribución. El [repo original](https://github.com/twitter/twemoji) declara Emoji 14. |
| [Noto Emoji / Noto Color Emoji](https://github.com/googlefonts/noto-emoji) | SVG/PNG, fuente color CBDT/CBLC y opciones monocromas; estilo Google | Fuentes OFL 1.1; herramientas y gran parte de imágenes Apache 2.0; revisar notices/excepciones por archivo | Actualizaciones por releases y trabajo upstream, sin asumir sincronía inmediata con Unicode. Algunas banderas tienen tratamiento PNG específico. Elegir explícitamente imágenes o fuente. |
| [OpenMoji](https://github.com/hfg-gmuend/openmoji) | SVG/PNG, variantes color/negro; contornos marcados | Gráficos CC BY-SA 4.0; código LGPL 3.0 | Releases comunitarias; comparar Unicode declarado con assets. Distinguir extras propios del repertorio Unicode. Conservar atribución y condiciones del arte derivado/atlas. |
| Sistema | Fuente dependiente de OS; estilo nativo | Licencia del proveedor y de la fuente | Actualiza con OS/distribución; versión, disponibilidad y cobertura variables. No empaquetar por asumir que está instalada. |

La licencia del código de un pack no licencia sus imágenes. La rasterización no
elimina las obligaciones del artwork. Los datos Unicode tienen su propia
[licencia de datos/software](https://www.unicode.org/license.txt), independiente
del arte. Registrar tag, cobertura, notices y proceso de regeneración; actualizar
por releases verificadas, sin prometer una cadencia común ni depender de un CDN.

## 5. Modelo mínimo neutral de contenido inline

Esquema conceptual, sin clases ni tipos obligatorios de ningún lenguaje:

```text
Document:
  source_utf8                    # cuerpo original, inmutable
  unicode_version
  runs[]

Run:
  kind: text | emoji             # image/custom: extensión futura
  source_spans[]: [byte_start, byte_end)  # offsets UTF-8 del original
  display_text                   # para text; incluye mapping si hay Markdown
  style_ref                      # formato, enlace, contexto de código

EmojiRun:
  sequence_unicode               # secuencia original completa
  recognition: known | unknown
  presentation: text | emoji | default

ResolvedInline:                  # resultado efímero del proveedor
  status: available | fallback | missing
  draw_handle                    # opaco: glifo, textura, vector, etc.
  advance, ascent, descent
  baseline_offset, bounds
  accessible_label_optional
```

`source_spans` permite mapear contenido tras quitar delimitadores Markdown;
no confundir bytes UTF-8 con índices GDScript, escalares, UTF-16 o glifos.
La resolución visual usa secuencia, proveedor/versión, estilo y tamaño/DPI como
identidad de caché; sus IDs internos nunca son identidad del mensaje.

Las métricas viven en unidades lógicas de layout. `advance` mueve el cursor;
`bounds` describe tinta/dibujo y puede diferir. Ascent/descent reservan altura
respecto a la baseline; `baseline_offset` desplaza el dibujo, positivo hacia abajo
en este modelo. La caja de línea debe cubrir los extremos desplazados para no
recortar imágenes ni superponer líneas.

Cada emoji reconocido y cada grafema usado como fallback es una unidad indivisible
para wrapping, selección y reveal. Dentro de un `TextRun` puede haber múltiples
oportunidades de corte: no convertir todo el run en una palabra indivisible.
Los cortes externos siguen las reglas de párrafo/espacios y
[UAX #14](https://www.unicode.org/reports/tr14/); no insertar espacios para forzar
el layout. Si una unidad excede el ancho completo, definir overflow o reducción
visual explícita, sin partir su Unicode. Bidi es orden visual de layout, nunca
reordenamiento del texto fuente.

## 6. Riesgos y preguntas específicas de xat

Observado en el código: `ui/bubble.gd` usa `RichTextLabel`, asigna BBCode desde
`xmpp/markdown.gd`, estima el ancho con `Font.get_string_size(body)` y revela con
`percent_visible`; `ui/xat_theme.gd` crea `DynamicFont` con fallback. El build apunta
a `godot-gdtk-slug`, pero eso no verifica sus capacidades de emoji.

- ¿Qué shaping y formatos de color soporta realmente el fork? Auditar fuente,
  versión FreeType, flags y composición. No extrapolar desde Slug ni Godot 4.
- `RichTextLabel` 3.6 admite imágenes inline y baseline, pero alinearlas por su
  borde inferior no garantiza la alineación óptica deseada. Comprobar zoom y
  descent. La API no garantiza el mapping de una imagen a Unicode para copia.
- La documentación 3.6 advierte sobre caracteres no BMP en Windows. Probar la
  representación interna, selección y round-trip del fork: dibujar una imagen
  no arregla por sí solo el almacenamiento/recorrido de strings.
  [RichTextLabel 3.6](https://docs.godotengine.org/en/3.6/classes/class_richtextlabel.html).
- El ancho medido desde texto crudo puede no coincidir con el contenido mixto;
  reveal por caracteres puede descubrir parte de una secuencia. ¿Se puede
  extender el layout existente con una modificación pequeña del motor?
- ¿Cómo interactúan runs con negrita, enlaces, código y escape de BBCode?
  Reconocer en contenido textual, no mediante sustitución sobre markup generado.
  Propuesta a validar: mantener código en presentación tipográfica, sin insertar
  imágenes; preservar emoji Unicode al copiarlo.
- ¿Cuántas páginas y qué tamaños de textura tolera el hardware GLES3 objetivo?
  Medir mezclas alternadas, clipping del scroll y pérdidas/recreación de caché.
- Mantener el contrato de `low_processor_mode` de [ui.md](ui.md): emoji estático
  no justifica redibujo continuo. Las correcciones invalidan sólo lo necesario.
- Accesibilidad y composer requieren verificación propia; el experimento no
  promete un editor con emojis, IME ni integración con lectores de pantalla.

## 7. Experimento MVP propuesto, sin implementar

Una vista de laboratorio con el mismo documento lógico y un adaptador intercambiable
de dibujo. Usar inicialmente **12–20 secuencias de prueba**, más texto sin emoji;
un subconjunto con licencia registrada basta. Comparar una representación raster
de referencia y un proveedor alternativo sólo si el stack disponible lo permite.
No descargar ni empaquetar un catálogo completo para responder preguntas de layout.

Corpus: `Hola 😀 mundo`, `❤ / ❤️ / ❤︎`, `👍🏽`, `👩‍💻`, una familia ZWJ,
`🇵🇪`, `1️⃣`, una bandera con tags, `é`, árabe + emoji, enlaces/código y texto
literal `[img]`. Forzar una secuencia conocida sin asset y una secuencia ZWJ no
enumerada: separar ausencia de arte de reconocimiento desconocido.

| Pregunta | Evidencia / aceptación propuesta |
|---|---|
| ¿Se ve inline y alinea? | Capturas a 16/24/32 px y DPI 1×/2×, texto `Ag` y líneas sucesivas; sin clipping ni solapamiento, revisión visual de baseline. |
| ¿Wrap/reveal son atómicos? | Anchos justo antes/después del advance; familia, tono, bandera y keycap nunca se parten ni aparecen parcialmente. |
| ¿Fallback es honesto? | Casos disponible/sin arte/desconocido identificables; sin pérdida de Unicode ni modificadores huérfanos por sustitución parcial. |
| ¿Copia conserva contenido? | Seleccionar texto + emoji, pegar y comparar escalares/UTF-8 con el segmento esperado; incluir VS15/16 y ZWJ. |
| ¿Se conserva por XMPP? | Dos clientes: envío→recepción→historial/MAM→corrección; comparar secuencias de cuerpo y observar en otro cliente. |
| ¿Cuánto cuesta? | Base sólo texto frente a 100 mensajes × 10 emojis, repetidos y variados; draw calls, CPU layout/raster frío y caliente, frame time, RAM, VRAM estimada/medida y tamaño exportado. |
| ¿Respeta el reposo? | Sin actividad ni animación, sin redibujos continuos añadidos; repetir tras scroll, zoom y corrección. |

Registrar binario/fork, plataforma/GPU/driver, Unicode, proveedor y licencia,
resoluciones/páginas cargadas, métricas y capturas. Ejecutar primero en Linux/gdtk
real; la afirmación de portabilidad exige pruebas Windows/macOS adicionales.
Los presupuestos numéricos de rendimiento se fijan después de medir la referencia,
no se inventan antes. La aceptación visual requiere revisión del usuario.

Salida del experimento: informe con resultados y fallos por adaptador, matriz de
cobertura del subconjunto y propuesta de siguiente decisión. Sólo entonces decidir
renderer, artwork, tamaño del catálogo y si hace falta extender el motor. Esta nota
documenta el experimento; no afirma haberlo ejecutado.
