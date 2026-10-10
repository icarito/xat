# Diseño de la barra de composición (input bar) rediseñada

Estado: **propuesta de diseño**, 2026-10-10. No se implementó nada todavía.
Reemplaza al composer actual de
[`addon/xat_xmpp/ui/chat_panel.gd`](../addon/xat_xmpp/ui/chat_panel.gd)
(`_build()`, líneas ~224–276; `_fit_input`, `_on_input_event`, `_on_send`,
`_on_mic`, `_on_mic_cancel`, `set_recording`). Ver también el contrato visual en
[`ui.md`](ui.md) y los tokens en
[`addon/xat_xmpp/ui/palette.gd`](../addon/xat_xmpp/ui/palette.gd).

Este documento sólo diseña; no toca código de la app.

---

## 1. Objetivos y no-objetivos

Objetivos:

1. Composer **súper compacto y cordial**, limpio, cómodo con el pulgar en el
   teléfono.
2. Grabación de voz **por gesto**: mantener presionado el micrófono para
   grabar, deslizar para cancelar, soltar para enviar, con temporizador y
   forma de onda visibles y una afordancia clara de cancelar (estilo
   Telegram/WhatsApp).
3. **Igualmente usable en escritorio** como Telegram Desktop: Enter envía,
   Shift+Enter inserta salto de línea, adjuntar fácil, emoji, arrastrar y
   soltar, sin gestos exclusivos del tacto.
4. Iconos **2D de contorno** (estilo Noun Project, ya usados en la app,
   `docs/credits.md`), **sin etiquetas de texto**.
5. Consciente del **teclado virtual y de las safe areas/notch** (la app ya sigue
   el teclado; ver `_follow_keyboard` en [`app/main.gd`](../app/main.gd):1325 y
   `_update_safe_area()` en `app/main.gd`).

No-objetivos (por ahora): stickers, reacciones, hilos, formato enriquecido,
editor de fotos, notas de voz en video.

---

## 2. Investigación: qué hacen los referentes

Resumen de patrones vigentes, con lo que conviene copiar y lo que conviene
evitar.

### 2.1 Gesto de voz (mantener para grabar)

- **Telegram**: mantener el micrófono para grabar; al soltar **se envía**;
  deslizar a la izquierda **cancela**
  ([core.telegram.org/blackberry/chat-voice](https://core.telegram.org/blackberry/chat-voice)).
  La versión "2.0" sumó **forma de onda** y "raise to speak"
  ([telegram.org/blog/voice-2-secret-3](https://telegram.org/blog/voice-2-secret-3)).
- **WhatsApp**: tocar el micrófono empieza a grabar; el check **envía**, la X
  cancela, y hay **pausa/reanudar y vista previa** antes de enviar
  ([faq.whatsapp.com/657157755756612](https://faq.whatsapp.com/657157755756612)).
  La forma de onda *en vivo* llegó en 2022
  ([blog.whatsapp.com/making-voice-messages-better](https://blog.whatsapp.com/making-voice-messages-better)).
  Deslizar hacia arriba **bloquea** la grabación para dejar las manos libres.
- **Umbrales concretos** de librerías actuales:
  - Zyeon `HoldToTalk` ([ui.zyeon.ai/docs/mobile/hold-to-talk](https://ui.zyeon.ai/docs/mobile/hold-to-talk)):
    `holdDelay = 220 ms` (press más corto = tap, no grabación),
    `minDuration = 800 ms` (release antes descarta, "too short"),
    `lockThreshold = 56 px` hacia arriba, `cancelThreshold = 96 px` hacia el
    borde, y **cancelar gana el empate en 1.0** ("discarding must be the easier
    escape"). Regla de oro: *one pointer, two escapes* (eje X cancela, eje Y
    bloquea, soltar envía). Nada es gesto-exclusivo: Enter/Espacio y botones
    ofrecen lo mismo.
  - Compose Multiplatform `voice-message`
    ([github.com/NadeemIqbal/voice-message](https://github.com/NadeemIqbal/voice-message)):
    `lockThresholdDp = 100`, `cancelThresholdDp = 60`.
- **Deslizar hacia arriba para bloquear** es incómodo con mouse/teclado: hay
  pedidos históricos pidiendo un clic simple para iniciar/detener con botones de
  cancelar/enviar en escritorio
  ([tdesktop#3208](https://github.com/telegramdesktop/tdesktop/issues/3208),
  [tdesktop#9047](https://github.com/telegramdesktop/tdesktop/issues/9047)).
  Conclusión: en escritorio, **clic = grabar bloqueado**, con botones visibles
  de cancelar y enviar; el gesto de mantener no es obligatorio.

### 2.2 Enviar vs. salto de línea

- Escritorio chat: **Enter envía, Shift+Enter nueva línea** es el consenso
  (MUI X
  [mui.com/x/react-chat/basics/composer](https://mui.com/x/react-chat/basics/composer),
  Helix UI
  [helix-ui.com/docs/components/chat-composer](https://helix-ui.com/docs/components/chat-composer)).
  Además hay que ser **IME-safe**: Enter no debe enviar mientras se compone
  texto CJK (MUI X).
- Zulip y Slack hacen configurable el comportamiento (Enter = nueva línea por
  defecto en Zulip, Ctrl+Enter envía)
  ([zulip.ietf.org/help/configure-send-message-keys](https://zulip.ietf.org/help/configure-send-message-keys));
  hay debate y expectativas cruzadas
  ([ux.stackexchange.com/questions/79157](https://ux.stackexchange.com/questions/79157)).
- **Móvil**: lo esperable es que Enter del teclado **inserte salto de línea** y
  se envíe con el botón (Telegram/WhatsApp). El composer actual envía con Enter
  también en móvil (`_on_input_event`): esto hay que corregirlo.

### 2.3 Afordancias de adjuntar/emoji

- **Element/Matrix**: Enter envía, Shift+Enter salta línea; el **clip** adjunta
  y el **smiley** a la derecha abre el menú de emoji; emoji por `:` + 2 letras
  ([docs.test.matrix.scc.kit.edu/…/formatting](https://docs.test.matrix.scc.kit.edu/en/messaging/formatting/index.html)).
- **CometChat** describe dos anatomías: *single-line* (campo a todo ancho y
  **fila de botones debajo**: adjuntar, emoji, voz, enviar) y *multiline*; el
  `enterKeyBehavior` es `SendMessage | NewLine | None`
  ([cometchat.com/docs/ui-kit/angular/components/cometchat-message-composer](https://www.cometchat.com/docs/ui-kit/angular/components/cometchat-message-composer)).
- **MUI/Helix**: superficie redondeada, **adjuntar a la izquierda**, **enviar a
  la derecha**, textarea que auto-crece y luego scrollea; el botón de enviar se
  deshabilita con texto vacío o mientras el agente responde en streaming.

### 2.4 Accesibilidad

- **WCAG 2.5.1 Pointer Gestures**: toda función con gesto de trazo debe poder
  operarse con un pointer simple (tap/clic)
  ([w3.org/WAI/WCAG21/Understanding/input-modalities](https://www.w3.org/WAI/WCAG21/Understanding/input-modalities)).
  Nuestro gesto de voz necesita alternativa de un solo toque.
- **WCAG 2.5.2 Pointer Cancellation**: no actuar al *presionar*, sólo al
  *soltar*.
- **WCAG 2.5.7 Dragging Movements**: el arrastre (p. ej. soltar archivos) debe
  tener alternativa.
- **Tamaño de objetivo**: mínimo 24×24 px (2.5.8) y 44×44 px como buena práctica
  (2.5.5 / Material 48 dp). Apuntamos a **48 px lógicos**.

---

## 3. Composer propuesto

### 3.1 Idea

Una **sola pastilla redondeada** (campo) con:

- **icono de adjuntar** incrustado a la izquierda (dentro de la pastilla);
- **icono de emoji** incrustado a la derecha del texto;
- un **botón cola que muta**: micrófono (vacío) → flecha de enviar (con texto)
  → enviar/stop (grabando bloqueado).

Al grabar, la pastilla **se transforma en una tira de grabación** con punto
rojo, temporizador, forma de onda y pista "desliza para cancelar"; al bloquear
aparece el icono de papelera. Todo con iconos 2D de contorno y sin texto en los
botones.

### 3.2 Teléfono, retrato

```
 con texto (teclado abierto; el split ya se eleva con _follow_keyboard)
 ╭──────────────────────────────────────────────────╮
 │  ⊕   ╭─────────────────────────────────╮   ╭───╮  │
 │      │ Escribe un mensaje…          🙂 │   │ ▲ │  │  tail = enviar
 │      ╰─────────────────────────────────╯   ╰───╯  │
 ╰──────────────────────────────────────────────────╯
    adjuntar      campo (crece 1..6 líneas)   emoji  enviar

 vacío
 ╭──────────────────────────────────────────────────╮
 │  ⊕   ╭─────────────────────────────────╮   ╭───╮  │
 │      │ Escribe un mensaje…             │   │ 🎤 │  │  tail = micrófono
 │      ╰─────────────────────────────────╯   ╰───╯  │
 ╰──────────────────────────────────────────────────╯

 grabando (dedo apoyado, sin bloquear)
 ╭──────────────────────────────────────────────────╮
 │      ╭───────────────────────────────────╮  ╭───╮  │
 │      │ ● 0:07  ▁▃▅▂▆▃▁▅   ← desliza cancelar │  │ 🎤 │  │
 │      ╰───────────────────────────────────╯  ╰───╯  │
 ╰──────────────────────────────────────────────────╯
        (soltar = enviar · deslizar ↑ = bloquear · ← = cancelar)

 grabando bloqueado (manos libres)
 ╭──────────────────────────────────────────────────╮
 │      ╭───────────────────────────────────╮  ╭───╮  │
 │      │ ● 0:42  ▁▃▅▂▆▃▁▅             🗑    │  │ ▲ │  │
 │      ╰───────────────────────────────────╯  ╰───╯  │
 ╰──────────────────────────────────────────────────╯
                                        trash = cancelar  tail = enviar
```

### 3.3 Teléfono, landscape

Misma fila; el campo se ensancha. El sidebar ya navega y la cabecera es
compacta (`set_nav_visible`). Se mantiene **una fila** para no comer altura
(regla de `CometChat` single-line: maximizar el ancho del campo). El límite de
crecimiento vertical baja a 4 líneas en landscape para no tapar el chat; pasado
el tope, el `TextEdit` scrollea internamente.

### 3.4 Escritorio

```
 ╭────────────────────────────────────────────────────────────────╮
 │  ⊕   ╭────────────────────────────────────────────────╮  🙂  ╭───╮
 │      │ Escribe un mensaje…                               │     │ 🎤 │
 │      ╰────────────────────────────────────────────────╯     ╰───╯
 ╰────────────────────────────────────────────────────────────────╯
   Enter = enviar (Shift+Enter = salto)   ·  clic en 🎤 = grabar bloqueado
```

- Botón cola con **hover** y tooltip (`hint_tooltip`), foco de teclado visible.
- El clic del micrófono **inicia grabación bloqueada** y muestra papelera y
  enviar (sin exigir mantener el mouse).
- Arrastrar archivos sobre la ventana los adjunta (`files_dropped`).

### 3.5 Esbozo anotado (medidas lógicas)

```
 composer (MarginContainer; l/r 8, top 6, bottom 6 + safe-inset)
 └─ fila (HBox, sep 8, alto según el mayor hijo)
    ├─ [adjuntar]  40×40   icono 22   (inside-order = 1)
    ├─ pastilla (PanelContainer EXPAND)  min-alto 44, radio 22, borde LINE 1
    │   └─ (HBox, sep 0)
    │       ├─ texto (TextEdit EXPAND)  fuente 15, crece 1..6 líneas
    │       └─ [emoji]   36×36  icono 20
    └─ [cola]       48×48  círculo  icono 22   (mic / enviar)
```

Radio del campo 22 (= `RADIUS + 6`) para pastilla; contenido con margen interno
`l=14, r=4, t=11, b=11` para que el texto no quede pegado al borde. En la tira de
grabación el radio es 22 y el contenido es punto + temporizador + onda.

---

## 4. Árbol de nodos Godot 3.6, widgets y adaptación

Todo por código, como el resto de la UI (sin escenas). Se reemplaza la sección
del composer dentro de `_build()` de `chat_panel.gd` (hoy: `h: HBox` con
`_input`, `tools`, `send`).

```
foot : PanelContainer                      # se mantiene (BG1, radio superior)
└─ f : VBoxContainer  (sep 6)              # se mantiene
   ├─ _state : RichTextLabel               # se mantiene ("pensando…")
   ├─ _preview : MarginContainer            # NUEVO (Fase 2): chips de adjuntos
   │   └─ VBoxContainer (sep 4)
   ├─ _compose : MarginContainer            # NUEVO (l/r 8, top 6, bottom 6+inset)
   │   └─ _row : HBoxContainer (sep 8)
   │      ├─ _attach_btn : IconButton (40×40)     # "paperclip.png"
   │      ├─ _field : PanelContainer (EXPAND_FILL) # pastilla BG2, radio 22
   │      │   └─ _field_row : HBoxContainer (sep 0)
   │      │      ├─ _input : TextEdit (EXPAND_FILL)
   │      │      ├─ _hint : Label (overlay, MOUSE_FILTER_IGNORE)  # se mantiene
   │      │      └─ _emoji_btn : IconButton (36×36)  # "emoji.png"
   │      ├─ _rec_strip : PanelContainer (EXPAND_FILL, oculto)  # NUEVO
   │      │   └─ _rec_row : HBoxContainer (sep 8)
   │      │      ├─ _rec_dot : Control (libre, dibuja círculo rojo)
   │      │      ├─ _rec_timer : Label (mono, "0:07")
   │      │      ├─ _rec_wave : Waveform (EXPAND_FILL)  # NUEVO
   │      │      ├─ _rec_hint : Label ("← desliza" / "bloqueado")
   │      │      └─ _rec_trash : IconButton (40×40, oculto)  # "trash.png"
   │      └─ _tail_btn : IconButton (48×48, círculo)  # mic/send
```

Reutilizamos: `XatTheme.box`, `XatTheme.with_border`, `Palette`, `Juice`
(háptica/sonido), el patrón `_anim` (Timer que pide `update()` sin violar
`low_processor_mode`, ver `ui.md`), y los diálogos de adjunto/cámara existentes
(`_open_file_dialog`, `camera_requested`, singleton `XatMedia`).

### 4.1 Widgets nuevos (helpers puros)

- `addon/xat_xmpp/ui/icon_button.gd` — `extends Button`. Carga una textura
  `res://icons/<nombre>.png`, la dibuja centrada en `_draw()` con
  `draw_texture_rect(tex, rect, false, icon_color)` para poder **recolorear** los
  contornos (TEXT, USER, ERROR, TEXT_DIM) sin duplicar PNGs. Alto 40–48,
  `focus_mode = FOCUS_ALL` en escritorio y `FOCUS_NONE` en móvil, tooltip.
- `addon/xat_xmpp/ui/waveform.gd` — `extends Control`. Buffer circular de N
  amplitudes (0..1) que dibuja barras verticales redondeadas con la misma pluma
  que el resto (2 px, puntas redondas). Sólo redibuja cuando se le empuja una
  muestra y mientras `visible`.

### 4.2 Estilo y tokens

- Pastilla: `XatTheme.with_border(XatTheme.box(Palette.BG2, 22, 0, 0), Palette.LINE)`.
- `TextEdit`: sin estilo propio (`StyleBoxEmpty` en `normal`/`focus`) para que el
  borde lo dibuje la pastilla; se aplica un `focus` con borde
  `Palette.AGENT_EDGE` a la **pastilla** (no al TextEdit) al enfocar.
- Botón cola: `BG2` con icono `TEXT` en estado mic; `USER` con icono `TEXT` en
  estado enviar. `hover`: `USER.lightened(0.15)`.
- Tira de grabación: mismo radio 22; fondo `BG2`; al entrar en zona de cancelar
  el borde/fondo se tiñe con `Palette.ERROR` (tinte, no sólo color: cumple 1.4.1
  "no sólo color" porque además aparece la papelera y cambia la pista).
- La forma de onda se dibuja con `Palette.AGENT_EDGE`; el punto de grabación con
  `Palette.ERROR`.

### 4.3 Adaptación (tamaño, orientación, plataforma)

- **Crecimiento multilínea** (`_fit_input` reescrito sobre el mismo cálculo):
  `n = clamp(1 + wraps por línea, 1, max_lines)`; `max_lines = 6` retrato /
  escritorio, `4` landscape de teléfono. Alto = `n * line_height + 22`.
  Al superar el tope, el `TextEdit` scrollea solo (no crece más la pastilla).
- **Ancho/estirpe**: el split ya usa `STRETCH_ASPECT_EXPAND` con base de lado
  corto 420 (`_apply_mobile_stretch`), así que las medidas lógicas se conservan
  al girar. La fila se ensancha; `_input` es `SIZE_EXPAND_FILL`.
- **Teclado**: se conserva `_follow_keyboard` (margen inferior del split). No
  hace falta lógica nueva; el composer vive en `foot` y sube con el split.
- **Safe area inferior** (barra de gestos): nueva API
  `ChatPanel.set_bottom_inset(px)` que ajusta `margin_bottom` de `_compose`
  (súmalo a 6). `main.gd` lo calcula en `_update_safe_area()` con
  `OS.get_window_safe_area()` (hoy sólo usa `safe.position.y` para el notch
  superior) y lo pone a 0 mientras el teclado está visible (el teclado ya eleva).
- **Notch lateral en landscape**: si `get_window_safe_area()` reporta insets
  laterales, se suman a `margin_left/right` de `_compose` (limitación: Godot 3
  sólo expone un `Rect2`, no insets por lado; ver riesgos).
- **Móvil vs. escritorio**: `OS.has_feature("mobile")` decide el
  comportamiento de Enter (ver §5.3) y los tamaños de objetivo/tooltips.

---

## 5. Manejo de gestos y de entrada

### 5.1 Máquina de estados del gesto de voz

Variables nuevas en `chat_panel.gd`:

```
var _rec_phase := "idle"      # idle | armed | held | locked | cancel_armed
var _rec_index := -1          # índice de toque que posee el gesto
var _rec_origin := Vector2.ZERO
var _rec_arm_timer : Timer    # HOLD_DELAY_MS antes de grabar de verdad
var _rec_cancel := false
var _rec_lock := false
```

Umbrales (px lógicos ≈ dp por la base de stretch):

| Constante | Valor | Razón |
|---|---|---|
| `HOLD_DELAY_MS` | 150 | un toque más corto es tap, no grabación (Zyeon: 220; bajamos por latencia percibida) |
| `MIN_RECORD_MS` | 800 | release antes descarta "demasiado corto" (Zyeon) |
| `LOCK_THRESHOLD` | 72 | deslizar ↑ para bloquear (56–100 en referentes) |
| `CANCEL_THRESHOLD` | 110 | deslizar ← para cancelar (96 en Zyeon; algo más por pulgar) |
| `MAX_RECORD_MS` | min(5 min, límite servidor) | `Recorder.MAX_MS` + `session.upload_max_bytes()` |

### 5.2 Tacto (`InputEventScreenTouch` / `InputEventScreenDrag`)

Godot 3 no tiene *pointer capture*: el gesto se rastrea en `_input(event)` de
`ChatPanel` (que ya existe para rueda/selección), probando si el toque inicial
cayó dentro del rect del botón cola (expandido 6 px). Se rastrea **por
`event.index`** para no chocar con otros dedos/scroll.

```
const LOCK_T := 72.0
const CANCEL_T := 110.0

func _input(e):
    if not visible or _peer == "" or _file_dialog_visible(): return
    if _composer_gesture(e): return          # NUEVO, primero
    if _handle_wheel(e): return
    ...selección de burbujas existente...     # con guard: no si e cae en el composer

func _composer_gesture(e) -> bool:
    if e is InputEventScreenTouch:
        if e.pressed and _tail_btn.get_global_rect().grow(6).has_point(e.position) and _rec_phase == "idle":
            _rec_index = e.index
            _rec_origin = e.position
            _rec_phase = "armed"
            _rec_arm_timer.start(HOLD_DELAY_MS)   # al timeout -> _start_recording(); _rec_phase = "held"
            get_tree().set_input_as_handled(); return true
        if not e.pressed and e.index == _rec_index:
            _release_recording(); get_tree().set_input_as_handled(); return true
    elif e is InputEventScreenDrag and e.index == _rec_index:
        _rec_update(e.position); get_tree().set_input_as_handled(); return true
    return false

func _rec_update(p):
    var dx = p.x - _rec_origin.x     # <0 = izquierda
    var dy = p.y - _rec_origin.y     # <0 = arriba
    # antes de armar (aún "armed"): el movimiento no cancela (subir para bloquear es válido)
    if _rec_phase == "locked": return
    var lock_p = clamp(-dy / LOCK_T, 0, 1)
    var cancel_p = clamp(-dx / CANCEL_T, 0, 1)
    _rec_wave.set_progress(lock_p, cancel_p)   # pista de bloqueo + tinte de cancelar
    if lock_p >= 1.0:
        _lock_recording()                       # suelta el dedo del gesto, sigue grabando
        return
    if cancel_p >= 1.0:
        if not _rec_cancel: _rec_cancel = true;  _on_cancel_enter()   # háptica de aviso
    else:
        if _rec_cancel: _rec_cancel = false; _on_cancel_leave()
```

- **Cancelar gana el empate**: canalizamos X e Y por separado y el umbral de
  cancelar se evalúa con prioridad, igual que Zyeon.
- **Liberar** (`_release_recording`): si `cancel_armed` → descartar
  (`voice_cancel`, háptica de error). Si `_rec_phase == "armed"` (tap corto, sin
  grabar aún) → **iniciar grabación bloqueada** (alternativa de un toque, WCAG
  2.5.1). Si duración < `MIN_RECORD_MS` → descartar con pista "mantén para
  grabar". En otro caso → `voice_toggle(peer, false)` = enviar.
- **Bloquear** (`_lock_recording`): `_rec_phase = "locked"`, se deja de rastrear
  el dedo (el gesto ya no cancela), se muestra `_rec_trash`, el botón cola pasa a
  enviar, háptica "success". La grabación sigue hasta tocar enviar/papelera o
  llegar a `MAX_RECORD_MS` (auto-envía + aviso, como hoy `_tick_recording`).

Visuales durante el arrastre: la pista "desliza para cancelar" se desplaza y
baja de opacidad con `cancel_p`; se dibuja un riel de bloqueo que se llena con
`lock_p` y una flecha/llave discreta; la papelera se resalta al entrar en la zona
de cancelar. Al bloquear, la pista cambia a "bloqueado" y aparecen los botones.

### 5.3 Escritorio: mouse y teclado

- **Micrófono (clic)**: inicia `RECORDING_LOCKED` directamente (no mantener).
  El botón cola muta a enviar; la tira muestra papelera + temporizador + onda.
  Clic en papelera = cancelar; clic en cola = enviar. (Paridad opcional:
  mantener el botón también graba y soltar envía, para ratones/touchpads.)
- **Enter**: en escritorio **envía**; **Shift+Enter** inserta salto de línea (ya
  funciona: `_on_input_event` envía sólo cuando `not p_ev.shift`). Se añade
  **Ctrl+Enter = enviar** como atajo opcional (convención Zulip/IDE).
- **Móvil**: el **Enter del teclado inserta salto de línea** (`OS.has_feature("mobile")`)
  y se envía con el botón. Esto corrige el comportamiento actual (envía en
  móvil). Se ignora el envío con Enter como "nueva línea" cuando el usuario
  eligió lo contrario en ajustes (Fase 2).
- **IME (CJK)**: no enviar con Enter mientras se compone texto; requiere detectar
  composición (ver riesgos) — guardia previsto.
- **Portapapeles**: `_input.context_menu_enabled = true` y
  `shortcut_keys_enabled = true` en el `TextEdit` para Ctrl+V/C/X/A y menú
  contextual (Godot 3.2+).
- **Arrastrar y soltar**: `get_tree().connect("files_dropped", self, "_on_files_dropped")`.
  Con `_peer != ""` y el composer visible, se envían los archivos (o se encolan
  como adjuntos en Fase 2). Alternativa sin arrastre: el botón adjuntar
  (obligatorio por WCAG 2.5.7).
- **Emoji**: el botón 🙂 abre el panel de emoji (Fase 2) o el IME del sistema;
  en Fase 1 el botón abre el selector de emoji del SO si existe, si no se oculta.

### 5.4 Sonido y háptica (juice)

- Inicio de grabación: `juice.haptic("receive")` + `juice.play("tool_start")`.
- Cruzar el umbral de bloqueo: `juice.haptic("success")` + `juice.pop(_tail_btn)`.
- Entrar en zona de cancelar: `juice.haptic("alert")` (una vez).
- Enviar: `juice.haptic("tick")` + `juice.play("send")`.
- Descartar/cancelar: `juice.haptic("error")` + `juice.play("alert")`.
- Demasiado corto: `juice.haptic("tick")` + `juice.toast("Mantén para grabar")`.

---

## 6. Máquina de estados del campo

Estados y qué hace el **botón cola**:

| Estado | Disparador de entrada | Campo / tira | Botón cola (icono) | Acción del cola |
|---|---|---|---|---|
| `IDLE_EMPTY` | texto == "" y no grabando | pastilla con hint | **mic** (BG2) | móvil: arma gesto; escritorio: graba bloqueado |
| `COMPOSING` | texto no vacío (ni sólo espacios) | pastilla creciendo | **enviar** (USER) | enviar |
| `RECORDING_ARMED` | touch apoyado en mic, < `HOLD_DELAY_MS` | pastilla (aún) | mic pulsando | (se resuelve al soltar) |
| `RECORDING_HELD` | pasó `HOLD_DELAY_MS` | tira: ● + timer + onda + "← desliza" | mic activo | soltar = enviar/descartar |
| `RECORDING_CANCEL` | arrastre ← ≥ `CANCEL_THRESHOLD` | tira teñida ERROR + papelera resaltada | mic activo | soltar = descartar |
| `RECORDING_LOCKED` | tap corto o arrastre ↑ ≥ `LOCK_THRESHOLD` o clic escritorio | tira: ● + timer + onda + papelera | **enviar** (USER) | enviar (papelera cancela) |
| `SENDING/MEDIA` | (existente) envío en curso | — | deshabilitado | — |

Transiciones clave:

```
IDLE_EMPTY ──escribe──▶ COMPOSING ──borra todo──▶ IDLE_EMPTY
IDLE_EMPTY ──press mic──▶ RECORDING_ARMED
RECORDING_ARMED ──hold──▶ RECORDING_HELD
RECORDING_ARMED ──release(tap)──▶ RECORDING_LOCKED
RECORDING_HELD ──slide←≥T──▶ RECORDING_CANCEL ──slide→<T──▶ RECORDING_HELD
RECORDING_HELD ──slide↑≥T──▶ RECORDING_LOCKED
RECORDING_HELD/CANCEL ──release──▶ IDLE_EMPTY (envía o descarta)
RECORDING_LOCKED ──tap tail──▶ COMPOSING|IDLE_EMPTY (envía)
RECORDING_LOCKED ──tap trash──▶ IDLE_EMPTY (descarta)
RECORDING_* ──MAX_RECORD_MS──▶ envía automáticamente + toast
```

`set_recording(on, elapsed)` (ya invocado por `main.gd`) mapea el estado real del
micrófono a la UI; se extiende para pasar también la amplitud si la hay.

---

## 7. Iconos necesarios (Noun Project, 2D de contorno)

PNGs nuevos en `app/icons/` (CC0/dominio público, recolorizados), registrados en
`docs/credits.md` con su id, como los existentes. Se dibujan con
`IconButton` para poder teñirlos.

| icono | archivo | dónde | estados |
|---|---|---|---|
| clip / adjuntar | `paperclip.png` | botón izquierdo, dentro de la fila | normal/hover |
| emoji (carita) | `emoji.png` | borde derecho dentro de la pastilla | normal/hover |
| micrófono | `mic.png` | botón cola | vacío |
| enviar (flecha ↑) | `send.png` | botón cola | con texto / bloqueado |
| papelera | `trash.png` | tira de grabación (bloqueado y zona de cancelar) | normal/hover, resaltado en cancelar |
| bloqueo (llave ↑) | `lock.png` | pista de la tira al mantener | sólo mientras se desliza |
| pausa | `pause.png` | tira de grabación (Fase 2) | pausado |
| cerrar (chip) | `close.png` | chips de adjunto (Fase 2) | normal/hover |

Notas de estilo: trazo 2 px, puntas redondeadas, coherentes con el resto de
`app/icons/` y con las flechas dibujadas hoy (`_draw_send`, `_draw_jump`). El
botón cola puede seguir dibujando la flecha de enviar por `_draw` (ya existe) si
se prefiere no sumar un PNG; el resto conviene hacerlo con PNG recoloreable.

---

## 8. Casos límite

- **Crecimiento multilínea**: tope 6 (retrato/escritorio) / 4 (landscape); luego
  scroll interno del `TextEdit`. El botón cola se mantiene alineado abajo
  (`SIZE_SHRINK_END`).
- **Texto muy largo**: sin límite duro de caracteres (el `<body>` XMPP es
  texto); el problema de tamaño es de adjuntos (`session.upload_max_bytes()`).
  Con la pastilla topada, el scroll interno evita saltos de layout.
- **Edición/selección**: la selección nativa del `TextEdit` manda; el código de
  pulsación larga de burbujas (`_input`/`_on_long_press`) debe **saltarse** los
  eventos cuyo punto caiga en el rect del composer o cuando `_input.has_focus()`,
  para no robar el gesto.
- **Emoji**: Fase 1 sin picker propio (usar IME del SO o dejar el slot sin
  acción); Fase 2 reutilizar el atlas de `app/emoji/` (ver `emoji.md`,
  `emoji-mvp.md`). Actualmente **no hay picker** — es deuda explícita.
- **Adjuntos**: Fase 1 mantiene el envío inmediato al elegir (comportamiento
  actual); Fase 2 chips de vista previa con quitar (x) antes de enviar.
- **Permisos de grabación**: en Android, `RECORD_AUDIO` en runtime; si falta, el
  gesto pide permiso (`OS.request_permissions()`), no muestra la tira y avisa
  (`juice.toast`). Escritorio no requiere permiso (driver
  `audio/driver/enable_input=true` ya está).
- **Teléfono vs. escritorio**: móvil = mantener/tap; escritorio = clic. Enter
  envía sólo en escritorio.
- **Safe areas/notch**: superior ya cubierto por `_update_safe_area`; se agrega
  inset inferior (barra de gestos). Android puede reportar `Rect2` con insets
  laterales en landscape; se suman a los márgenes si el dato existe.
- **Duración**: el WAV PCM actual es voluminoso; `MAX_RECORD_MS` ya acota a
  `min(5 min, max-file-size)`. Al llegar, auto-envío con aviso.
- **Rotación/bloqueo durante grabación**: al perder foco o al cambiar de chat,
  definir política (propuesta: cancelar y avisar, como WhatsApp al salir del
  chat).
- **Accesibilidad**: objetivos ≥48 px; camino sin gesto (tap para bloquear +
  botones); tooltips/nombres accesibles. Godot 3 no expone un árbol de
  accesibilidad completo en Android (TalkBack ve la app como un lienzo): es una
  limitación reconocida, no resuelta por este diseño.

---

## 9. MVP vs. fases posteriores

### Fase 1 — MVP

1. Pastilla única con iconos incrustados (adjuntar izquierda, emoji derecha) y
   botón cola que muta mic ↔ enviar. **Sin etiquetas de texto.**
2. Gesto de voz completo: mantener para grabar, deslizar ← cancelar, ↑
   bloquear, soltar enviar, tap para grabar bloqueado; temporizador, **forma de
   onda real** (amplitud del micrófono), papelera, háptica.
3. Escritorio: clic para grabar bloqueado; Enter envía / Shift+Enter salto;
   Ctrl+V/contexto; arrastrar y soltar archivos.
4. Móvil: Enter inserta salto (no envía); enviar con el botón.
5. Crecimiento topado + scroll interno; inset inferior de safe area; íconos
   Noun Project + `docs/credits.md`.

### Fase 2

- Picker de emoji reutilizando el atlas de `app/emoji/`.
- Chips de adjuntos con vista previa y quitar; menú de adjunto (Archivo / Foto /
  Cámara) en una hoja emergente en móvil.
- Pausa/reanudar grabación y previsualización antes de enviar.
- Ajuste "Enter envía" configurable; refinamientos landscape/tablet.
- Scrub de la forma de onda en la burbuja enviada.

### Fase 3

- Velocidad de reproducción, reproducción fuera del chat, raise-to-listen.
- Árbol de accesibilidad real; envío IME-safe robusto.
- (Opcional) codificación OGG/Opus vía módulo nativo en lugar de WAV PCM.

---

## 10. Riesgos

- **Sin pointer capture en Godot 3**: hay que rastrear el dedo por
  `InputEventScreenDrag`/`index` en `_input`; riesgo de conflicto con el scroll
  del chat y con la selección por pulsación larga de burbujas. Mitigación:
  procesar el gesto del composer primero y consumir el evento; guard por rect.
- **Amplitud en vivo**: `AudioEffectRecord` no expone un medidor de nivel
  continuo claro. Propuesta: `AudioEffectSpectrumAnalyzer` en el bus `XatRecord`
  y leer la magnitud por rango cada ~50 ms. Verificar disponibilidad/rendimiento
  en el fork; fallback: punto + temporizador sin onda (nunca onda simulada, por
  la regla de honestidad de `ui.md`).
- **IME/CJK**: Godot 3 no expone explícitamente el estado de composición; el
  Enter podría enviar a mitad de composición. Riesgo acotado a idiomas CJK.
- **Rendimiento**: el waveform no debe redibujar por frame con
  `low_processor_mode`; usar un `Timer` acotado que llame `update()` sólo
  mientras se graba (mismo patrón que `_anim`/shimmer).
- **Safe areas**: `get_window_safe_area()` es un `Rect2` global; no da insets por
  lado ni distingue teclado de barra de gestos. Puede requerir heurística.
- **Licencias de iconos**: confirmar CC0/dominio público de cada Noun Project y
  anotar autoría si fuera CC BY en `docs/credits.md`.
- **Tamaño del WAV**: PCM 16 bits estéreo es grande; limita la duración útil de
  notas de voz hasta migrar a Opus.
- **Alcance del picker de emoji**: hoy no existe; prometer "emoji" en Fase 1 sin
  picker propio es un riesgo de expectativa.
- **Accesibilidad del motor**: sin árbol accesible, TalkBack no ve los botones;
  el gesto tendrá alternativa visual, pero no lectura por lector de pantalla.

---

## 11. Preguntas abiertas para el product owner

1. **Enter**: ¿dejamos Enter = enviar / Shift+Enter = salto por defecto
   (escritorio) con ajuste configurable en Fase 2, o adoptamos el estilo Zulip
   (Enter = salto, Ctrl+Enter = enviar)?
2. **Tap en el micrófono vacío**: ¿iniciar grabación **bloqueada** (mi
   propuesta, alternativa accesible de un toque) o cambiar el teclado a un modo
   de voz?
3. **Emoji**: ¿hace falta el picker propio en el MVP (reutilizando el atlas
   Noto) o alcanza con el IME del sistema y lo dejamos para Fase 2?
4. **Adjuntos**: ¿mantenemos el envío inmediato al elegir archivo en Fase 1, o el
   MVP ya debe mostrar vista previa con "quitar" antes de enviar?
5. **Grabación y navegación**: si el usuario sale del chat o scrollea mientras
   graba, ¿cancelamos (estilo WhatsApp) o mantenemos la nota?
6. **Formato de audio**: ¿aceptamos WAV PCM con el tope actual, o invertimos en
   OGG/Opus nativo (más duración y compatibilidad) ya en esta etapa?
7. **Landscape de teléfono**: ¿una sola fila (mi propuesta) o dos filas
   (campo arriba, botones abajo, estilo CometChat single-line) en pantallas
   bajas?

---

## 12. Fuentes

- Telegram: [chat-voice](https://core.telegram.org/blackberry/chat-voice),
  [Voice Messages 2.0](https://telegram.org/blog/voice-2-secret-3),
  [tdesktop#3208](https://github.com/telegramdesktop/tdesktop/issues/3208),
  [tdesktop#9047](https://github.com/telegramdesktop/tdesktop/issues/9047).
- WhatsApp: [ayuda enviar voz](https://faq.whatsapp.com/657157755756612),
  [blog voz](https://blog.whatsapp.com/making-voice-messages-better),
  [WABetaInfo/Gesture](https://thenextweb.com/news/whatsapp-voice-message-button).
- Librerías de gesto: [Zyeon HoldToTalk](https://ui.zyeon.ai/docs/mobile/hold-to-talk),
  [voice-message (Compose MP)](https://github.com/NadeemIqbal/voice-message).
- Composer: [MUI X](https://mui.com/x/react-chat/basics/composer),
  [Helix UI](https://helix-ui.com/docs/components/chat-composer),
  [CometChat](https://www.cometchat.com/docs/ui-kit/angular/components/cometchat-message-composer).
- Teclas: [Zulip](https://zulip.ietf.org/help/configure-send-message-keys),
  [UX SE 79157](https://ux.stackexchange.com/questions/79157),
  [Element/Matrix](https://docs.test.matrix.scc.kit.edu/en/messaging/formatting/index.html).
- Accesibilidad: [WCAG 2.5 Input Modalities](https://www.w3.org/WAI/WCAG21/Understanding/input-modalities),
  [2.5.1 Pointer Gestures](https://accessibility.build/wcag/2-5-1),
  [Mobile a11y / target size](https://aaardvarkaccessibility.com/wcag-guideline/input-modalities).
- iMessage (botón circular, mantener para efectos):
  [How-To Geek](https://www.howtogeek.com/272074/how-to-use-imessages-new-effects).
